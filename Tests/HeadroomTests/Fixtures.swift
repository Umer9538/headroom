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
