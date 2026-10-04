package com.umer9538.headroom

/**
 * The little statistics the probe needs, a line-for-line port of the Swift
 * core's `Statistics.swift` so a report from Android carries figures computed
 * the same way as one from iOS. The Dart side recomputes them from the raw
 * iteration times in its integration test and expects equality.
 */
internal object Statistics {
    fun median(values: DoubleArray): Double {
        require(values.isNotEmpty()) { "median of nothing" }
        val sorted = values.sortedArray()
        val middle = sorted.size / 2
        return if (sorted.size % 2 == 0) (sorted[middle - 1] + sorted[middle]) / 2 else sorted[middle]
    }

    /**
     * Percentile-bootstrap confidence interval of the median: resample with
     * replacement, take each resample's median, and read off the central
     * [confidence] share of them. Seeded, so the same samples give the same
     * interval everywhere.
     */
    fun bootstrapMedianInterval(
        values: DoubleArray,
        confidence: Double = 0.95,
        resamples: Int = 2000,
        seed: Long = 0x48454144524F4F4DL, // "HEADROOM"
    ): Pair<Double, Double> {
        require(values.isNotEmpty()) { "interval of nothing" }
        require(confidence > 0 && confidence < 1) { "confidence is a fraction" }
        if (values.size == 1) return values[0] to values[0]

        val generator = SplitMix64(seed)
        val resample = DoubleArray(values.size)
        val medians = DoubleArray(resamples)
        for (i in 0 until resamples) {
            for (index in resample.indices) {
                resample[index] = values[generator.nextIndex(values.size)]
            }
            medians[i] = median(resample)
        }
        medians.sort()
        val lower = (resamples * (1 - confidence) / 2).toInt()
        val upper = minOf(resamples - 1, (resamples * (1 + confidence) / 2).toInt())
        return medians[lower] to medians[upper]
    }
}

/** Vigna's SplitMix64: tiny, well mixed, and the same everywhere. */
internal class SplitMix64(private var state: Long) {
    fun next(): Long {
        state += 0x9E3779B97F4A7C15uL.toLong()
        var z = state
        z = (z xor (z ushr 30)) * 0xBF58476D1CE4E5B9uL.toLong()
        z = (z xor (z ushr 27)) * 0x94D049BB133111EBuL.toLong()
        return z xor (z ushr 31)
    }

    /**
     * A uniform index in `0 until upperBound`, exactly as Swift's
     * `Int.random(in: 0..<upperBound, using:)` derives one on a 64-bit
     * platform: the high word of the full-width product of one draw and the
     * bound, rejecting the few draws that would bias the result.
     */
    fun nextIndex(upperBound: Int): Int {
        require(upperBound in 1 until 0x40000000) { "upperBound must be in 1 until 2^30" }
        val n = upperBound.toLong()
        var product = multiplyFullWidth(next(), n)
        if (unsignedLessThan(product.second, n)) {
            // (2^64 - n) mod n, computed without overflowing: 2^64 ≡ 4 × (2^62 mod n).
            val threshold = ((1L shl 62) % n) * 4 % n
            while (unsignedLessThan(product.second, threshold)) {
                product = multiplyFullWidth(next(), n)
            }
        }
        return product.first.toInt()
    }

    /** `random × n` as (high, low) 64-bit words, with `n < 2^31`. */
    private fun multiplyFullWidth(random: Long, n: Long): Pair<Long, Long> {
        val mask = 0xFFFFFFFFL
        val lo = random and mask
        val hi = random ushr 32
        val p0 = lo * n
        val p1 = hi * n
        val mid = (p0 ushr 32) + (p1 and mask)
        val low = ((mid and mask) shl 32) or (p0 and mask)
        val high = (p1 ushr 32) + (mid ushr 32)
        return high to low
    }

    /** `a < b` as unsigned 64-bit values, for a small non-negative [b]. */
    private fun unsignedLessThan(a: Long, b: Long): Boolean = a >= 0 && a < b
}
