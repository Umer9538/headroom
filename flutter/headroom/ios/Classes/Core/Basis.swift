/// Where a figure comes from.
///
/// Every number Headroom reports carries a basis, so a calibrated estimate can
/// never be read as something measured on this device.
public enum Basis: Sendable, Hashable {
    /// Measured on this device, during this probe.
    case measured

    /// Derived from measurements committed for `devices` other devices in
    /// `calibration.json` (see `Calibration/README.md`), not observed here.
    case calibrated(devices: Int)

    /// Not established. Any value alongside it is a stated fallback.
    case unknown

    /// The basis of a figure derived from this one and `other`.
    ///
    /// A derivation is only as well founded as its least-founded input: anything
    /// touched by an unknown is unknown, and anything touched by a calibrated
    /// constant is calibrated on the smaller device count.
    public func combined(with other: Basis) -> Basis {
        switch (self, other) {
        case (.unknown, _), (_, .unknown):
            return .unknown
        case let (.calibrated(a), .calibrated(b)):
            return .calibrated(devices: min(a, b))
        case (.calibrated, .measured):
            return self
        case (.measured, .calibrated):
            return other
        case (.measured, .measured):
            return .measured
        }
    }
}

extension Basis: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case devices
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "measured":
            self = .measured
        case "calibrated":
            self = .calibrated(devices: try container.decode(Int.self, forKey: .devices))
        case "unknown":
            self = .unknown
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container, debugDescription: "unrecognised basis '\(kind)'"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .measured:
            try container.encode("measured", forKey: .kind)
        case let .calibrated(devices):
            try container.encode("calibrated", forKey: .kind)
            try container.encode(devices, forKey: .devices)
        case .unknown:
            try container.encode("unknown", forKey: .kind)
        }
    }
}

extension Basis: CustomStringConvertible {
    public var description: String {
        switch self {
        case .measured: "measured"
        case let .calibrated(devices): "calibrated (n=\(devices))"
        case .unknown: "unknown"
        }
    }
}
