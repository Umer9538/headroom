/// The little statistics the probe needs, dependency-free and deterministic.
enum Statistics {
    static func median(_ values: [Double]) -> Double {
        precondition(!values.isEmpty, "median of nothing")
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// Percentile-bootstrap confidence interval of the median: resample with
    /// replacement, take each resample's median, and read off the central
    /// `confidence` share of them. Seeded, so the same samples give the same
    /// interval on the same toolchain.
    static func bootstrapMedianInterval(
        _ values: [Double],
        confidence: Double = 0.95,
        resamples: Int = 2_000,
        seed: UInt64 = 0x4845_4144_524F_4F4D  // "HEADROOM"
    ) -> ClosedRange<Double> {
        precondition(!values.isEmpty, "interval of nothing")
        precondition(confidence > 0 && confidence < 1, "confidence is a fraction")
        guard values.count > 1 else { return values[0]...values[0] }

        var generator = SplitMix64(seed: seed)
        var resample = [Double](repeating: 0, count: values.count)
        var medians: [Double] = []
        medians.reserveCapacity(resamples)
        for _ in 0..<resamples {
            for index in resample.indices {
                resample[index] = values[Int.random(in: 0..<values.count, using: &generator)]
            }
            medians.append(median(resample))
        }
        medians.sort()
        let lower = Int(Double(resamples) * (1 - confidence) / 2)
        let upper = min(resamples - 1, Int(Double(resamples) * (1 + confidence) / 2))
        return medians[lower]...medians[upper]
    }
}

/// Vigna's SplitMix64: tiny, well mixed, and the same everywhere.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
