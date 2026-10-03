import Foundation

/// The committed measurements every calibrated constant is derived from.
///
/// Nothing in here is typed in as a constant: efficiencies and sustained
/// factors are computed from the rows at run time, and `Calibration/README.md`
/// walks through the arithmetic.
public struct Calibration: Sendable, Hashable, Codable {
    /// One device's achieved decode bandwidth and, once probed, its measured ceiling.
    public struct BandwidthRow: Sendable, Hashable, Codable {
        public let soc: String
        public let device: String
        /// Mean single-stream decode rate over the committed repeats.
        public let decodeTokPerSec: Double
        /// Weight bytes of the model that was decoded.
        public let tensorBytes: Int
        /// `decodeTokPerSec × tensorBytes / 1e9`, stored for readability and
        /// checked against the inputs by the test suite.
        public let achievedGBps: Double
        /// The Headroom triad median on the same device; null until it has been probed.
        public let ceilingGBps: Double?
        public let source: String
        public let ceilingSource: String?

        public var recomputedAchievedGBps: Double {
            Calibration.achievedGBps(decodeTokPerSec: decodeTokPerSec, bytesPerToken: tensorBytes)
        }

        /// η: the share of the measured ceiling that decode actually used.
        public var efficiency: Double? {
            ceilingGBps.map { achievedGBps / $0 }
        }
    }

    /// One device's throughput at the start of a session and after sustained generation.
    public struct SustainedRow: Sendable, Hashable, Codable {
        public let soc: String
        public let platform: Platform
        public let runtime: String
        public let peakTokPerSec: Double
        public let sustainedTokPerSec: Double
        public let protocolNote: String
        public let source: String

        public var factor: Double {
            sustainedTokPerSec / peakTokPerSec
        }

        private enum CodingKeys: String, CodingKey {
            case soc, platform, runtime, peakTokPerSec, sustainedTokPerSec
            case protocolNote = "protocol"
            case source
        }
    }

    public let schemaVersion: Int
    public let bandwidth: [BandwidthRow]
    public let sustained: [SustainedRow]

    public init(schemaVersion: Int = 1, bandwidth: [BandwidthRow], sustained: [SustainedRow]) {
        self.schemaVersion = schemaVersion
        self.bandwidth = bandwidth
        self.sustained = sustained
    }

    public init(contentsOf url: URL) throws {
        self = try JSONDecoder().decode(Calibration.self, from: Data(contentsOf: url))
    }

    /// The rows shipped in this package's `Resources/calibration.json`.
    public static let shipped: Calibration = {
        // The resource is part of this package and CalibrationTests decode it,
        // so a failure here is a packaging bug rather than a runtime condition.
        guard let url = Bundle.module.url(forResource: "calibration", withExtension: "json") else {
            preconditionFailure("Headroom's resource bundle is missing calibration.json; the package was not built with its resources")
        }
        do {
            return try Calibration(contentsOf: url)
        } catch {
            preconditionFailure("Headroom's calibration.json does not decode: \(error)")
        }
    }()

    /// Single-stream decode reads every weight once per token, so the decode
    /// rate converts directly into the bandwidth the memory system delivered.
    /// This is PocketRoofline's `achieved_bandwidth`, unchanged.
    public static func achievedGBps(decodeTokPerSec: Double, bytesPerToken: Int) -> Double {
        decodeTokPerSec * Double(bytesPerToken) / 1e9
    }

    /// η over every device with a measured ceiling, as the range they span.
    /// The basis says how many devices that is.
    public var efficiency: Interval {
        let efficiencies = bandwidth.compactMap(\.efficiency)
        guard let low = efficiencies.min(), let high = efficiencies.max() else {
            return .unknown
        }
        return Interval(low: low, high: high, basis: .calibrated(devices: efficiencies.count))
    }

    /// The peak-to-sustained ratio measured on `platform`, or nil when no row
    /// describes it. Throttling has only been measured on phones, so this is
    /// nil on macOS rather than an assumed 1.0.
    public func sustainedFactor(platform: Platform) -> Interval? {
        let factors = sustained.filter { $0.platform == platform }.map(\.factor)
        guard let low = factors.min(), let high = factors.max() else {
            return nil
        }
        return Interval(low: low, high: high, basis: .calibrated(devices: factors.count))
    }
}
