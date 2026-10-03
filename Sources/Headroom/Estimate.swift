/// What a model of a given size should do on the probed device.
public struct Estimate: Sendable, Hashable, Codable {
    public let model: ModelSpec
    public let contextTokens: Int
    public let bytesPerToken: Int
    /// The measured ceiling the prediction scales, as its 95% interval; nil
    /// when the GPU probe did not run.
    public let ceilingGBps: Interval?
    /// η: the share of the ceiling llama.cpp's decode loop achieved on the
    /// calibration devices.
    public let efficiency: Interval
    /// Single-stream decode throughput at the start of a session, tokens per second.
    public let peak: Interval
    /// Peak-to-sustained ratio measured on phones after minutes of generation;
    /// nil where no calibrated phone data applies.
    public let sustainedFactor: Interval?
    /// Decode throughput once the device has throttled.
    public let sustained: Interval?
    public let fit: MemoryFit
    /// Caveats to surface alongside the numbers.
    public let notes: [String]
}

extension ProbeReport {
    /// Predicts decode throughput and memory fit for `model` with
    /// `contextTokens` already in the KV cache.
    ///
    /// `peak = ceiling × η / bytesPerToken`, as an interval spanning the
    /// ceiling's confidence interval and the calibrated efficiency range;
    /// `sustained = peak × sustainedFactor`.
    public func estimate(
        _ model: ModelSpec,
        contextTokens: Int,
        calibration: Calibration = .shipped
    ) -> Estimate {
        precondition(contextTokens >= 0, "context cannot be negative")
        var notes: [String] = []
        let bytesPerToken = model.bytesPerToken(contextTokens: contextTokens)
        let efficiency = calibration.efficiency
        if !efficiency.isKnown {
            notes.append("No calibration device has a measured ceiling, so efficiency is unknown.")
        }

        let ceiling = gpu?.triad.medianCI95GBps
        let peak: Interval
        if let ceiling {
            // GB/s × η → GB/s of weights; × 1e9 / bytes per token → tokens per second.
            peak = ceiling.multiplied(by: efficiency).multiplied(by: 1e9).divided(by: Double(bytesPerToken))
        } else {
            peak = .unknown
            notes.append("The GPU probe did not run, so throughput is unknown.")
        }

        let sustainedFactor = calibration.sustainedFactor(platform: device.platform)
        if sustainedFactor != nil {
            let rows = calibration.sustained.filter { $0.platform == device.platform }
            let runtimes = Set(rows.map(\.runtime)).sorted().joined(separator: ", ")
            notes.append("Sustained factor comes from \(rows.count) phone(s) on \(runtimes); it is a throttling range, not this device's.")
        } else {
            notes.append("No sustained factor applies: throttling has only been calibrated on iPhones.")
        }

        if model.kv == nil {
            notes.append("\(model.name) has no layer geometry, so the KV cache is not modelled: bytes per token are weights only.")
        }
        if memory.availableBytes.basis != .measured {
            notes.append("Available memory is a fallback: this platform exposes no per-process budget, so the fit verdict is unknown.")
        }

        return Estimate(
            model: model,
            contextTokens: contextTokens,
            bytesPerToken: bytesPerToken,
            ceilingGBps: ceiling,
            efficiency: efficiency,
            peak: peak,
            sustainedFactor: sustainedFactor,
            sustained: sustainedFactor.map { peak.multiplied(by: $0) },
            fit: MemoryFit(model: model, contextTokens: contextTokens, available: memory.availableBytes),
            notes: notes
        )
    }
}
