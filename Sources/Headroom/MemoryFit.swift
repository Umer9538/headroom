/// Whether a model's working set fits in the memory the OS will let this
/// process have.
public struct MemoryFit: Sendable, Hashable {
    public enum Verdict: Sendable, Hashable {
        case fits(marginMB: Double)
        /// Fits, but the margin is inside the requirement's own uncertainty.
        case tight(marginMB: Double)
        case doesNotFit(shortfallMB: Double)
    }

    public let verdict: Verdict
    public let requiredBytes: Int
    public let availableBytes: Int
    /// The basis of `availableBytes`, which the verdict inherits.
    public let basis: Basis

    // The three constants below are stated assumptions about llama.cpp-style
    // runtimes, not measurements. Tune them if yours differs.

    /// Runtimes allocate a little over the weight bytes: alignment padding,
    /// dequantisation scratch, compute-graph buffers.
    public static let weightOverheadFactor = 1.1
    /// Engine code, Metal pipelines, tokenizer tables. Decimal megabytes.
    public static let runtimeFixedBytes = 150_000_000
    /// A margin smaller than this share of the requirement is within the slack
    /// the overhead factor itself represents.
    public static let tightMarginFraction = 0.1

    public static func requiredBytes(for model: ModelSpec, contextTokens: Int) -> Int {
        Int((Double(model.tensorBytes) * weightOverheadFactor).rounded())
            + model.kvBytes(contextTokens: contextTokens)
            + runtimeFixedBytes
    }

    init(model: ModelSpec, contextTokens: Int, available: Quantity<UInt64>) {
        let required = Self.requiredBytes(for: model, contextTokens: contextTokens)
        let availableBytes = Int(clamping: available.value)
        let margin = availableBytes - required
        let marginMB = Double(margin) / 1e6
        if margin < 0 {
            verdict = .doesNotFit(shortfallMB: -marginMB)
        } else if Double(margin) < Double(required) * Self.tightMarginFraction {
            verdict = .tight(marginMB: marginMB)
        } else {
            verdict = .fits(marginMB: marginMB)
        }
        requiredBytes = required
        self.availableBytes = availableBytes
        basis = available.basis
    }
}

extension MemoryFit: Codable {
    private enum CodingKeys: String, CodingKey {
        case verdict
        case marginMB
        case requiredBytes
        case availableBytes
        case basis
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let marginMB = try container.decode(Double.self, forKey: .marginMB)
        switch try container.decode(String.self, forKey: .verdict) {
        case "fits": verdict = .fits(marginMB: marginMB)
        case "tight": verdict = .tight(marginMB: marginMB)
        case "doesNotFit": verdict = .doesNotFit(shortfallMB: -marginMB)
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .verdict, in: container, debugDescription: "unrecognised verdict '\(other)'"
            )
        }
        requiredBytes = try container.decode(Int.self, forKey: .requiredBytes)
        availableBytes = try container.decode(Int.self, forKey: .availableBytes)
        basis = try container.decode(Basis.self, forKey: .basis)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // One signed figure: positive is headroom, negative is shortfall.
        switch verdict {
        case let .fits(marginMB):
            try container.encode("fits", forKey: .verdict)
            try container.encode(marginMB, forKey: .marginMB)
        case let .tight(marginMB):
            try container.encode("tight", forKey: .verdict)
            try container.encode(marginMB, forKey: .marginMB)
        case let .doesNotFit(shortfallMB):
            try container.encode("doesNotFit", forKey: .verdict)
            try container.encode(-shortfallMB, forKey: .marginMB)
        }
        try container.encode(requiredBytes, forKey: .requiredBytes)
        try container.encode(availableBytes, forKey: .availableBytes)
        try container.encode(basis, forKey: .basis)
    }
}
