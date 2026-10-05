import Foundation
@testable import Headroom

/// Hand-built reports and calibrations, so estimator tests do not need a GPU.
enum Fixtures {
    static let tensorBytes = 635_990_016

    /// The committed SISO decode repeats from PocketRoofline `results/`.
    static let a15DecodeRepeats = [42.597, 42.439, 42.575, 43.202, 43.193]
    static let m1DecodeRepeats = [59.729, 62.786, 59.816, 60.7, 62.477]

    static func mean(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(values.count)
    }

    // MARK: Committed records

    struct MissingRecord: Error, CustomStringConvertible {
        let description: String
    }

    /// The repository's `Calibration/runs/`, where the raw records are committed.
    static let runs = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Calibration/runs")

    /// The parts of a PocketRoofline app capture the calibration reads.
    struct PocketRooflineCapture: Decodable {
        struct Regime: Decodable {
            struct Repeat: Decodable {
                let decodeTokensPerSec: Double
            }

            let label: String
            let repeats: [Repeat]
        }

        let regimes: [Regime]

        /// Decode rates of every repeat of `label` (SISO, LISO, SILO), in run order.
        func decodeRates(_ label: String) throws -> [Double] {
            guard let regime = regimes.first(where: { $0.label == label }) else {
                throw MissingRecord(description: "no \(label) regime in the capture")
            }
            return regime.repeats.map(\.decodeTokensPerSec)
        }
    }

    /// The iPhone 15 Plus capture the A16 decode and sustained rows come from.
    static func a16Capture() throws -> PocketRooflineCapture {
        let url = runs.appendingPathComponent("a16/pocketroofline-iPhone15,5-1791162656.json")
        return try JSONDecoder().decode(PocketRooflineCapture.self, from: Data(contentsOf: url))
    }

    /// Probe reports committed in `Calibration/runs/<subdirectory>` whose file
    /// names start with `prefix`, in file-name (capture) order.
    static func committedReports(in subdirectory: String, prefix: String) throws -> [ProbeReport] {
        let directory = subdirectory.isEmpty ? runs : runs.appendingPathComponent(subdirectory)
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { try ProbeReport(jsonData: Data(contentsOf: $0)) }
    }

    /// The four iPhone 15 Plus probes the A16 ceiling comes from.
    static func a16Probes() throws -> [ProbeReport] {
        try committedReports(in: "a16", prefix: "headroom-")
    }

    /// The three M1 runs the M1 ceiling comes from.
    static func m1Runs() throws -> [ProbeReport] {
        try committedReports(in: "", prefix: "m1-")
    }

    /// The median of the reports' GPU triad medians: how a ceiling row is derived.
    static func ceilingGBps(of reports: [ProbeReport]) throws -> Double {
        let medians = try reports.map { report in
            guard let gpu = report.gpu else {
                throw MissingRecord(description: "a committed report has no GPU section")
            }
            return gpu.triad.medianGBps.value
        }
        return Statistics.median(medians)
    }

    static func figure(
        kernel: StreamKernel = .triad,
        arrayBytes: Int = 128 << 20,
        gbps: [Double],
        verified: Bool = true
    ) -> BandwidthFigure {
        let bytes = kernel.bytesPerIteration(arrayBytes: arrayBytes)
        return BandwidthFigure(
            kernel: kernel,
            bytesPerIteration: bytes,
            iterationSeconds: gbps.map { Double(bytes) / ($0 * 1e9) },
            verified: verified,
            basis: verified ? .measured : .unknown
        )
    }

    static func gpu(triadGBps: [Double]) -> GPUBandwidth {
        GPUBandwidth(
            deviceName: "Fixture GPU",
            arrayBytes: 128 << 20,
            copy: figure(kernel: .copy, gbps: triadGBps),
            scale: figure(kernel: .scale, gbps: triadGBps),
            add: figure(kernel: .add, gbps: triadGBps),
            triad: figure(kernel: .triad, gbps: triadGBps)
        )
    }

    static func cpu(threads: Int = 6, gbps: [Double] = [30, 31, 32]) -> CPUBandwidth {
        let triad = figure(arrayBytes: 64 << 20, gbps: gbps)
        return CPUBandwidth(
            threads: threads, arrayBytes: 64 << 20, compiledWithOptimisation: true,
            triad: triad, attempts: [CPUBandwidth.Attempt(threads: threads, triad: triad)]
        )
    }

    static func report(
        platform: Platform = .iOS,
        capturedAt: Date = Date(timeIntervalSince1970: 1_790_000_000),
        triadGBps: [Double]? = [60, 60, 60],
        availableBytes: Quantity<UInt64> = Quantity(2_000_000_000, basis: .measured)
    ) -> ProbeReport {
        ProbeReport(
            capturedAt: capturedAt,
            durationSeconds: 1.25,
            device: DeviceInfo(
                identifier: "iPhone14,5", chip: nil, platform: platform,
                osVersion: "26.6.1", osBuild: "23G83", logicalCPUs: 6
            ),
            conditions: Conditions(
                thermalState: .fair, isLowPowerModeEnabled: false,
                powerSource: .battery, batteryLevel: 0.5
            ),
            memory: MemoryInfo(physicalBytes: 4_000_000_000, availableBytes: availableBytes),
            gpu: triadGBps.map(gpu(triadGBps:)),
            cpu: cpu(),
            warnings: []
        )
    }

    static func bandwidthRow(soc: String, decode: Double, ceilingGBps: Double?) -> Calibration.BandwidthRow {
        Calibration.BandwidthRow(
            soc: soc, device: soc, decodeTokPerSec: decode, tensorBytes: tensorBytes,
            achievedGBps: Calibration.achievedGBps(decodeTokPerSec: decode, bytesPerToken: tensorBytes),
            ceilingGBps: ceilingGBps, source: "fixture", ceilingSource: ceilingGBps.map { _ in "fixture" }
        )
    }

    static func sustainedRow(soc: String, platform: Platform = .iOS, peak: Double, sustained: Double) -> Calibration.SustainedRow {
        Calibration.SustainedRow(
            soc: soc, platform: platform, runtime: "fixture",
            peakTokPerSec: peak, sustainedTokPerSec: sustained,
            protocolNote: "fixture", source: "fixture"
        )
    }
}
