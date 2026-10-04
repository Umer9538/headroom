package com.umer9538.headroom

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The `headroom/probe` channel on Android.
 *
 * `probe` takes the Dart `ProbeOptions` as a map and answers with the report
 * as a JSON string; `cancel` stops a running probe at its next stage boundary
 * (before the CPU triad, or between its attempts), after which the pending
 * `probe` call fails with code `cancelled`. The probe runs on its own thread,
 * never on the platform thread; results are posted back to it.
 */
class HeadroomPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var runner: ProbeRunner
    private val executor = Executors.newSingleThreadExecutor { task -> Thread(task, "headroom-probe") }
    private val mainThread = Handler(Looper.getMainLooper())
    private val running = AtomicBoolean(false)

    @Volatile
    private var cancelRequested = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        runner = ProbeRunner(binding.applicationContext)
        channel = MethodChannel(binding.binaryMessenger, "headroom/probe")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "probe" -> probe(call, result)
            "cancel" -> {
                cancelRequested = true
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun probe(call: MethodCall, result: Result) {
        val options = try {
            options(call)
        } catch (error: ProbeRunner.InvalidOptions) {
            result.error("invalidOptions", error.message, null)
            return
        }
        if (!running.compareAndSet(false, true)) {
            result.error("busy", "a probe is already running", null)
            return
        }
        cancelRequested = false
        executor.execute {
            val outcome: Outcome = try {
                Outcome.Report(runner.run(options) { cancelRequested })
            } catch (cancelled: ProbeRunner.Cancelled) {
                Outcome.Failure("cancelled", cancelled.message ?: "the probe was cancelled")
            } catch (invalid: ProbeRunner.InvalidOptions) {
                Outcome.Failure("invalidOptions", invalid.message ?: "invalid probe options")
            } catch (error: Throwable) {
                Outcome.Failure("probeFailed", error.toString())
            }
            // Cleared before the reply is posted, so the next probe the Dart
            // side sends after this reply is never refused as busy.
            running.set(false)
            mainThread.post {
                when (outcome) {
                    is Outcome.Report -> result.success(outcome.json)
                    is Outcome.Failure -> result.error(outcome.code, outcome.message, null)
                }
            }
        }
    }

    private sealed class Outcome {
        class Report(val json: String) : Outcome()

        class Failure(val code: String, val message: String) : Outcome()
    }

    /** The Dart `ProbeOptions.toChannelArguments()` map; absent keys keep the defaults. */
    private fun options(call: MethodCall): ProbeRunner.Options {
        val defaults = ProbeRunner.Options()
        fun long(key: String, default: Long): Long = when (val value = call.argument<Any>(key)) {
            null -> default
            is Number -> value.toLong()
            else -> throw ProbeRunner.InvalidOptions("probe option '$key' must be an integer")
        }
        fun int(key: String, default: Int): Int = when (val value = call.argument<Any>(key)) {
            null -> default
            is Number -> value.toInt()
            else -> throw ProbeRunner.InvalidOptions("probe option '$key' must be an integer")
        }
        fun bool(key: String, default: Boolean): Boolean = when (val value = call.argument<Any>(key)) {
            null -> default
            is Boolean -> value
            else -> throw ProbeRunner.InvalidOptions("probe option '$key' must be a boolean")
        }
        return ProbeRunner.Options(
            gpuArrayBytes = long("gpuArrayBytes", defaults.gpuArrayBytes),
            gpuWarmupIterations = int("gpuWarmupIterations", defaults.gpuWarmupIterations),
            gpuTimedIterations = int("gpuTimedIterations", defaults.gpuTimedIterations),
            cpuArrayBytes = long("cpuArrayBytes", defaults.cpuArrayBytes),
            cpuThreads = int("cpuThreads", defaults.cpuThreads),
            cpuWarmupIterations = int("cpuWarmupIterations", defaults.cpuWarmupIterations),
            cpuTimedIterations = int("cpuTimedIterations", defaults.cpuTimedIterations),
            runsGPUProbe = bool("runsGPUProbe", defaults.runsGPUProbe),
            runsCPUProbe = bool("runsCPUProbe", defaults.runsCPUProbe),
        ).also { it.validate() }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }
}
