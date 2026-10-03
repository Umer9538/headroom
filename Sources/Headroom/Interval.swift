/// A closed range `[low, high]` of a non-negative quantity, with its basis.
///
/// Predictions are intervals rather than points because their inputs are: a
/// measured ceiling has a confidence interval and the calibrated efficiency
/// spans several devices. `Interval.unknown` is `[0, ∞)`, the honest width
/// when nothing is known.
public struct Interval: Sendable, Hashable {
    public let low: Double
    public let high: Double
    public let basis: Basis

    public init(low: Double, high: Double, basis: Basis) {
        precondition(low >= 0 && high >= low, "an Interval needs 0 <= low <= high")
        self.low = low
        self.high = high
        self.basis = basis
    }

    public static let unknown = Interval(low: 0, high: .infinity, basis: .unknown)

    /// False for `.unknown` and for anything derived from it.
    public var isKnown: Bool {
        basis != .unknown && high.isFinite
    }

    /// Product of two non-negative intervals; unknown if either is.
    public func multiplied(by other: Interval) -> Interval {
        guard isKnown, other.isKnown else { return .unknown }
        return Interval(
            low: low * other.low,
            high: high * other.high,
            basis: basis.combined(with: other.basis)
        )
    }

    public func multiplied(by factor: Double) -> Interval {
        precondition(factor >= 0, "scaling by a negative factor would flip the bounds")
        guard isKnown else { return .unknown }
        return Interval(low: low * factor, high: high * factor, basis: basis)
    }

    public func divided(by divisor: Double) -> Interval {
        precondition(divisor > 0, "division needs a positive divisor")
        guard isKnown else { return .unknown }
        return Interval(low: low / divisor, high: high / divisor, basis: basis)
    }
}

extension Interval: Codable {
    private enum CodingKeys: String, CodingKey {
        case low
        case high
        case basis
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            low: try container.decode(Double.self, forKey: .low),
            // JSON has no infinity, so an unbounded interval stores a null high.
            high: try container.decodeIfPresent(Double.self, forKey: .high) ?? .infinity,
            basis: try container.decode(Basis.self, forKey: .basis)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(low, forKey: .low)
        if high.isFinite {
            try container.encode(high, forKey: .high)
        } else {
            try container.encodeNil(forKey: .high)
        }
        try container.encode(basis, forKey: .basis)
    }
}

extension Interval: CustomStringConvertible {
    public var description: String {
        isKnown ? "[\(low), \(high)] (\(basis))" : "unknown"
    }
}
