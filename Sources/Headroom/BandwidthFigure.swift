/// One kernel's bandwidth over its timed iterations.
public struct BandwidthFigure: Sendable, Hashable, Codable {
    public let kernel: StreamKernel
    public let bytesPerIteration: Int
    /// Seconds per timed iteration: GPU timestamps for Metal, wall clock for the CPU.
    public let iterationSeconds: [Double]
    /// Whether the kernel's output was read back and matched the expected arithmetic.
    public let verified: Bool
    public let bestGBps: Quantity<Double>
    public let medianGBps: Quantity<Double>
    /// 95% bootstrap confidence interval of the median across iterations.
    public let medianCI95GBps: Interval

    /// Decimal gigabytes per second, the unit bandwidth is quoted in everywhere here.
    public static func gigabytesPerSecond(bytes: Int, seconds: Double) -> Double {
        Double(bytes) / seconds / 1e9
    }

    public var iterationGBps: [Double] {
        iterationSeconds.map { Self.gigabytesPerSecond(bytes: bytesPerIteration, seconds: $0) }
    }

    init(
        kernel: StreamKernel,
        bytesPerIteration: Int,
        iterationSeconds: [Double],
        verified: Bool,
        basis: Basis
    ) {
        precondition(!iterationSeconds.isEmpty, "a figure needs at least one timed iteration")
        self.kernel = kernel
        self.bytesPerIteration = bytesPerIteration
        self.iterationSeconds = iterationSeconds
        self.verified = verified
        let rates = iterationSeconds.map { Self.gigabytesPerSecond(bytes: bytesPerIteration, seconds: $0) }
        bestGBps = Quantity(rates.max()!, basis: basis)
        medianGBps = Quantity(Statistics.median(rates), basis: basis)
        let interval = Statistics.bootstrapMedianInterval(rates)
        medianCI95GBps = Interval(low: interval.lowerBound, high: interval.upperBound, basis: basis)
    }
}

/// Metal STREAM results. The triad median is the ceiling estimates divide by.
public struct GPUBandwidth: Sendable, Hashable, Codable {
    public let deviceName: String
    public let arrayBytes: Int
    public let copy: BandwidthFigure
    public let scale: BandwidthFigure
    public let add: BandwidthFigure
    public let triad: BandwidthFigure
}

/// STREAM triad on the CPU. A ceiling for CPU inference backends only;
/// estimates do not use it.
public struct CPUBandwidth: Sendable, Hashable, Codable {
    /// One thread count's run.
    public struct Attempt: Sendable, Hashable, Codable {
        public let threads: Int
        public let triad: BandwidthFigure
    }

    /// The thread count behind `triad`: the attempt with the highest median.
    public let threads: Int
    public let arrayBytes: Int
    /// False in unoptimised builds, where the vector loop spills to the stack
    /// and the figure is reported with basis `.unknown`.
    public let compiledWithOptimisation: Bool
    public let triad: BandwidthFigure
    /// Every thread count tried, `threads` included, so the choice can be audited.
    public let attempts: [Attempt]

    /// The verified attempt with the highest median, or the highest unverified
    /// one when none verified (its basis is already `.unknown`).
    static func best(of attempts: [Attempt]) -> Attempt {
        precondition(!attempts.isEmpty, "at least one thread count must have run")
        let verified = attempts.filter(\.triad.verified)
        return (verified.isEmpty ? attempts : verified).max { $0.triad.medianGBps.value < $1.triad.medianGBps.value }!
    }

    init(threads: Int, arrayBytes: Int, compiledWithOptimisation: Bool, triad: BandwidthFigure, attempts: [Attempt]) {
        self.threads = threads
        self.arrayBytes = arrayBytes
        self.compiledWithOptimisation = compiledWithOptimisation
        self.triad = triad
        self.attempts = attempts
    }

    /// Records written before thread counts were tried in turn (the committed
    /// `Calibration/runs/`) carry one run; that run is their only attempt.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threads = try container.decode(Int.self, forKey: .threads)
        arrayBytes = try container.decode(Int.self, forKey: .arrayBytes)
        compiledWithOptimisation = try container.decode(Bool.self, forKey: .compiledWithOptimisation)
        triad = try container.decode(BandwidthFigure.self, forKey: .triad)
        attempts = try container.decodeIfPresent([Attempt].self, forKey: .attempts)
            ?? [Attempt(threads: threads, triad: triad)]
    }
}
