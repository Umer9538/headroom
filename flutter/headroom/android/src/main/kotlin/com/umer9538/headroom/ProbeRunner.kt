package com.umer9538.headroom

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.TreeMap

/**
 * Produces the same ProbeReport JSON (schema version 1) the Swift core
 * writes, from what Android exposes: the C core's CPU triad, memory from
 * ActivityManager, thermal status from PowerManager, battery from
 * BatteryManager and the device from Build.
 *
 * There is no GPU probe on Android in this version, so the `gpu` section is
 * null and a warning says so; the Dart side then reports throughput as
 * unknown rather than borrowing the Apple-derived efficiency.
 */
internal class ProbeRunner(private val context: Context) {
    class Cancelled : Exception("the probe was cancelled")

    class InvalidOptions(message: String) : Exception(message)

    /** The Dart `ProbeOptions`; the same validation rules as the Swift core. */
    data class Options(
        val gpuArrayBytes: Long = 128L shl 20,
        val gpuWarmupIterations: Int = 1,
        val gpuTimedIterations: Int = 10,
        val cpuArrayBytes: Long = 64L shl 20,
        val cpuThreads: Int = 0,
        val cpuWarmupIterations: Int = 1,
        val cpuTimedIterations: Int = 7,
        val runsGPUProbe: Boolean = true,
        val runsCPUProbe: Boolean = true,
    ) {
        fun validate() {
            if (gpuArrayBytes <= 0 || gpuArrayBytes % (256 * 16) != 0L) {
                throw InvalidOptions("gpuArrayBytes must be a positive multiple of ${256 * 16}")
            }
            if (cpuArrayBytes < 4 || cpuArrayBytes % 4 != 0L) {
                throw InvalidOptions("cpuArrayBytes must be a positive multiple of 4")
            }
            if (gpuTimedIterations < 1 || cpuTimedIterations < 1) {
                throw InvalidOptions("each probe needs at least one timed iteration")
            }
            if (gpuWarmupIterations < 0 || cpuWarmupIterations < 0 || cpuThreads < 0) {
                throw InvalidOptions("warm-up iterations and thread count cannot be negative")
            }
        }
    }

    private class Figure(
        val bytesPerIteration: Long,
        val iterationSeconds: DoubleArray,
        val verified: Boolean,
        val basis: Map<String, Any?>,
    ) {
        val rates: DoubleArray = DoubleArray(iterationSeconds.size) { bytesPerIteration / iterationSeconds[it] / 1e9 }
        val best: Double = rates.max()
        val median: Double = Statistics.median(rates)
        val interval: Pair<Double, Double> = Statistics.bootstrapMedianInterval(rates)

        fun toJson(): Map<String, Any?> = mapOf(
            "bestGBps" to mapOf("basis" to basis, "value" to best),
            "bytesPerIteration" to bytesPerIteration,
            "iterationSeconds" to iterationSeconds.toList(),
            "kernel" to "triad",
            "medianCI95GBps" to mapOf("basis" to basis, "high" to interval.second, "low" to interval.first),
            "medianGBps" to mapOf("basis" to basis, "value" to median),
            "verified" to verified,
        )
    }

    private class Attempt(val threads: Int, val figure: Figure)

    /** Runs the probe on the calling thread and returns the report as JSON. */
    fun run(options: Options, isCancelled: () -> Boolean): String {
        options.validate()
        val startedNanos = SystemClock.elapsedRealtimeNanos()
        // ISO 8601 carries whole seconds, so the timestamp is truncated here.
        val capturedAt = Date(System.currentTimeMillis() / 1000 * 1000)

        val device = deviceInfo()
        val conditions = conditions()
        val memoryInfo = ActivityManager.MemoryInfo().also {
            context.getSystemService(ActivityManager::class.java).getMemoryInfo(it)
        }
        val warnings = mutableListOf<String>()
        if (isEmulator) {
            warnings += "Running in the Android Emulator: the bandwidth figures are the host machine's, not a phone's."
        }

        if (isCancelled()) throw Cancelled()
        if (options.runsGPUProbe) {
            warnings += "GPU probe did not run: this version has no GPU probe on Android (the STREAM kernels run through Metal on iOS only), so the ceiling and any throughput estimate are unknown here."
        }

        if (isCancelled()) throw Cancelled()
        var cpu: Map<String, Any?>? = null
        if (options.runsCPUProbe) {
            // A probe never allocates past what the OS reports as available:
            // the arrays must fit in availMem, with no margin invented.
            val needed = 3 * options.cpuArrayBytes
            if (needed > memoryInfo.availMem) {
                warnings += "CPU probe skipped: it needs ${needed / 1_000_000} MB of memory and the OS reports ${memoryInfo.availMem / 1_000_000} MB available"
            } else {
                try {
                    val (section, optimised) = cpuProbe(options, isCancelled)
                    cpu = section
                    if (!optimised) {
                        warnings += "CHeadroom was compiled without optimisation; the CPU triad figure is not a ceiling and carries basis unknown."
                    }
                } catch (cancelled: Cancelled) {
                    throw cancelled
                } catch (error: Exception) {
                    warnings += "CPU probe did not run: ${error.message ?: error.javaClass.simpleName}"
                }
            }
        }

        if (isCancelled()) throw Cancelled()
        val durationSeconds = (SystemClock.elapsedRealtimeNanos() - startedNanos) / 1e9

        val report = mapOf(
            "capturedAt" to iso8601Seconds(capturedAt),
            "conditions" to conditions,
            "cpu" to cpu,
            "device" to device,
            "durationSeconds" to durationSeconds,
            "gpu" to null,
            "headroomVersion" to CORE_VERSION,
            "memory" to mapOf(
                "availableBytes" to mapOf("basis" to MEASURED, "value" to memoryInfo.availMem),
                "lowMemory" to memoryInfo.lowMemory,
                "lowMemoryThresholdBytes" to memoryInfo.threshold,
                "physicalBytes" to memoryInfo.totalMem,
            ),
            "schemaVersion" to SCHEMA_VERSION,
            "warnings" to warnings.toList(),
        )
        return (toJson(report) as JSONObject).toString(2)
    }

    /** The CPU triad for every candidate thread count; returns the section and whether the core is optimised. */
    private fun cpuProbe(options: Options, isCancelled: () -> Boolean): Pair<Map<String, Any?>, Boolean> {
        val optimised = NativeBridge.cOptimized() != 0
        val attempts = mutableListOf<Attempt>()
        for (threads in candidateThreadCounts(options.cpuThreads)) {
            if (isCancelled()) throw Cancelled()
            attempts += Attempt(threads, triad(options, threads, optimised))
        }
        // The verified attempt with the highest median, or the highest
        // unverified one when none verified: the Swift core's `best(of:)`.
        val verified = attempts.filter { it.figure.verified }
        val best = (verified.ifEmpty { attempts }).maxBy { it.figure.median }
        val section = mapOf(
            "arrayBytes" to options.cpuArrayBytes,
            "attempts" to attempts.map { mapOf("threads" to it.threads, "triad" to it.figure.toJson()) },
            "compiledWithOptimisation" to optimised,
            "threads" to best.threads,
            "triad" to best.figure.toJson(),
        )
        return section to optimised
    }

    private fun triad(options: Options, threads: Int, optimised: Boolean): Figure {
        val seconds = DoubleArray(options.cpuTimedIterations)
        val verifiedOut = IntArray(1)
        val status = NativeBridge.cpuTriad(
            options.cpuArrayBytes / 4,
            threads,
            options.cpuWarmupIterations,
            options.cpuTimedIterations,
            seconds,
            verifiedOut,
        )
        if (status != NativeBridge.OK) throw IllegalStateException("CPU triad failed with code $status")
        val verified = verifiedOut[0] != 0
        return Figure(
            bytesPerIteration = 3 * options.cpuArrayBytes,
            iterationSeconds = seconds,
            verified = verified,
            basis = if (verified && optimised) MEASURED else UNKNOWN,
        )
    }

    private fun deviceInfo(): Map<String, Any?> {
        val chip = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manufacturer = Build.SOC_MANUFACTURER
            val model = Build.SOC_MODEL
            when {
                manufacturer == Build.UNKNOWN && model == Build.UNKNOWN -> Build.UNKNOWN
                manufacturer == Build.UNKNOWN -> model
                model == Build.UNKNOWN -> manufacturer
                else -> "$manufacturer $model"
            }
        } else {
            Build.UNKNOWN
        }
        return mapOf(
            "chip" to chip,
            "identifier" to "${Build.MANUFACTURER} ${Build.MODEL}",
            "logicalCPUs" to NativeBridge.onlineCpus(),
            "osBuild" to Build.ID,
            "osVersion" to Build.VERSION.RELEASE,
            "platform" to if (isEmulator) "Android Emulator" else "Android",
        )
    }

    private fun conditions(): Map<String, Any?> {
        val power = context.getSystemService(PowerManager::class.java)
        val status = power.currentThermalStatus
        // Android has seven levels; the report's four are the Swift core's.
        val (thermalState, statusName) = when (status) {
            PowerManager.THERMAL_STATUS_NONE -> "nominal" to "NONE"
            PowerManager.THERMAL_STATUS_LIGHT -> "fair" to "LIGHT"
            PowerManager.THERMAL_STATUS_MODERATE -> "fair" to "MODERATE"
            PowerManager.THERMAL_STATUS_SEVERE -> "serious" to "SEVERE"
            PowerManager.THERMAL_STATUS_CRITICAL -> "critical" to "CRITICAL"
            PowerManager.THERMAL_STATUS_EMERGENCY -> "critical" to "EMERGENCY"
            PowerManager.THERMAL_STATUS_SHUTDOWN -> "critical" to "SHUTDOWN"
            else -> "unrecognised" to "UNKNOWN($status)"
        }

        val battery = batteryIntent()
        val plugged = battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1) ?: -1
        val powerSource = when {
            battery == null || plugged < 0 -> "unknown"
            plugged == 0 -> "battery"
            else -> "external"
        }
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val batteryLevel = if (level >= 0 && scale > 0) level.toDouble() / scale else null

        return mapOf(
            "batteryLevel" to batteryLevel,
            "isLowPowerModeEnabled" to power.isPowerSaveMode,
            "platformThermalStatus" to statusName,
            "powerSource" to powerSource,
            "thermalState" to thermalState,
        )
    }

    /** The sticky battery broadcast, read without registering a receiver. */
    private fun batteryIntent(): Intent? {
        val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(null, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            context.registerReceiver(null, filter)
        }
    }

    companion object {
        /** The Swift core's `Headroom.version`; tool/sync_native.sh checks they match. */
        const val CORE_VERSION = "0.1.0"
        const val SCHEMA_VERSION = 1

        private val MEASURED = mapOf("kind" to "measured")
        private val UNKNOWN = mapOf("kind" to "unknown")

        /**
         * Thread counts an automatic run tries, in order, as the Swift core
         * decides them: the performance cluster alone where the kernel reports
         * one, then every core. Android reports none, so this is one all-core
         * attempt today; the attempt is still recorded.
         */
        fun candidateThreadCounts(requested: Int): List<Int> {
            if (requested > 0) return listOf(requested)
            val all = NativeBridge.onlineCpus()
            val performance = NativeBridge.performanceCpus()
            return if (performance in 1 until all) listOf(performance, all) else listOf(all)
        }

        /** Heuristic: the emulator's build fields name goldfish/ranchu hardware or an SDK phone product. */
        val isEmulator: Boolean by lazy {
            Build.HARDWARE.contains("goldfish") ||
                Build.HARDWARE.contains("ranchu") ||
                Build.PRODUCT.startsWith("sdk") ||
                Build.PRODUCT.contains("emulator") ||
                Build.PRODUCT.contains("simulator") ||
                Build.MODEL.contains("Emulator") ||
                Build.MODEL.contains("Android SDK built for") ||
                Build.FINGERPRINT.startsWith("generic") ||
                Build.FINGERPRINT.startsWith("unknown")
        }

        private fun iso8601Seconds(date: Date): String =
            SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }.format(date)

        /**
         * org.json with keys sorted at every level, the layout the Swift core
         * writes. Null map values are written as JSON null (the report's `gpu`
         * and `cpu` sections, an unbounded interval's `high`); optional
         * fields that are absent are simply not put in the map.
         */
        private fun toJson(value: Any?): Any? = when (value) {
            null -> JSONObject.NULL
            is Map<*, *> -> JSONObject().also { json ->
                val sorted = TreeMap<String, Any?>()
                value.forEach { (key, element) -> sorted[key as String] = element }
                sorted.forEach { (key, element) -> json.put(key, toJson(element)) }
            }
            is Iterable<*> -> JSONArray().also { json -> value.forEach { json.put(toJson(it)) } }
            else -> value
        }
    }
}
