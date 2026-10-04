import Foundation

/// Everything one probe observed, serialisable so a device's result can be
/// pasted back into `calibration.json`.
public struct ProbeReport: Sendable, Hashable, Codable {
    public let schemaVersion: Int
    public let headroomVersion: String
    public let capturedAt: Date
    public let durationSeconds: Double
    public let device: DeviceInfo
    public let conditions: Conditions
    public let memory: MemoryInfo
    /// Nil when Metal was unavailable or a buffer could not be allocated; `warnings` says which.
    public let gpu: GPUBandwidth?
    public let cpu: CPUBandwidth?
    public let warnings: [String]

    /// The memory-bandwidth ceiling estimates scale: the Metal triad median.
    public var ceilingGBps: Quantity<Double>? {
        gpu?.triad.medianGBps
    }

    public func jsonData() throws -> Data {
        try Self.jsonEncoder.encode(self)
    }

    public init(jsonData: Data) throws {
        self = try Self.jsonDecoder.decode(ProbeReport.self, from: jsonData)
    }

    init(
        capturedAt: Date,
        durationSeconds: Double,
        device: DeviceInfo,
        conditions: Conditions,
        memory: MemoryInfo,
        gpu: GPUBandwidth?,
        cpu: CPUBandwidth?,
        warnings: [String]
    ) {
        schemaVersion = 1
        headroomVersion = Headroom.version
        // ISO 8601 carries whole seconds, so a report decoded from its own JSON
        // must compare equal: the timestamp is truncated here, not at encoding.
        self.capturedAt = Date(timeIntervalSince1970: capturedAt.timeIntervalSince1970.rounded(.down))
        self.durationSeconds = durationSeconds
        self.device = device
        self.conditions = conditions
        self.memory = memory
        self.gpu = gpu
        self.cpu = cpu
        self.warnings = warnings
    }

    public static var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
