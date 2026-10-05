import Foundation
import Headroom

// Prints the full report as JSON, then the TinyLlama estimate so the M1
// prediction can be compared with PocketRoofline's measured decode rate.
//
// `headroom-probe --from report.json` skips the probe and estimates from a
// report captured elsewhere, such as a phone's, using this build's calibration.

let arguments = CommandLine.arguments
let report: ProbeReport
if let flag = arguments.firstIndex(of: "--from"), arguments.indices.contains(flag + 1) {
    report = try ProbeReport(jsonData: Data(contentsOf: URL(filePath: arguments[flag + 1])))
    print("Report captured \(report.capturedAt.formatted(.iso8601)), read from \(arguments[flag + 1])")
} else {
    report = try await Headroom.probe()
    print(String(decoding: try report.jsonData(), as: UTF8.self))
}
print()

func gbps(_ figure: BandwidthFigure) -> String {
    let ci = figure.medianCI95GBps
    return String(
        format: "median %.1f GB/s (95%% CI %.1f–%.1f, best %.1f) — %@",
        figure.medianGBps.value, ci.low, ci.high, figure.bestGBps.value,
        "\(figure.medianGBps.basis)"
    )
}

func tokPerSec(_ interval: Interval) -> String {
    interval.isKnown ? String(format: "%.1f–%.1f tok/s", interval.low, interval.high) : "unknown"
}

let device = report.device
print("\(device.identifier)\(device.chip.map { " (\($0))" } ?? ""), \(device.platform.rawValue) \(device.osVersion) (\(device.osBuild)), "
    + "thermal \(report.conditions.thermalState.rawValue), power \(report.conditions.powerSource.rawValue), "
    + "low power mode \(report.conditions.isLowPowerModeEnabled ? "on" : "off")")
if let gpu = report.gpu {
    print("GPU (\(gpu.deviceName)) STREAM, 3 × \(gpu.arrayBytes >> 20) MB:")
    for figure in [gpu.copy, gpu.scale, gpu.add, gpu.triad] {
        print("  \(figure.kernel.rawValue.padding(toLength: 6, withPad: " ", startingAt: 0)) \(gbps(figure))\(figure.verified ? "" : "  (NOT VERIFIED)")")
    }
}
if let cpu = report.cpu {
    print("CPU triad, \(cpu.threads) threads, 3 × \(cpu.arrayBytes >> 20) MB: \(gbps(cpu.triad))")
    if cpu.attempts.count > 1 {
        let tried = cpu.attempts.map { String(format: "%d threads %.1f", $0.threads, $0.triad.medianGBps.value) }
        print("  tried \(tried.joined(separator: ", ")) GB/s; kept the higher median")
    }
}
let memory = report.memory
print(String(format: "Memory: %.2f GB physical, %.2f GB available (%@)",
             Double(memory.physicalBytes) / 1e9, Double(memory.availableBytes.value) / 1e9,
             "\(memory.availableBytes.basis)"))
for warning in report.warnings {
    print("warning: \(warning)")
}

let model = ModelSpec.tinyLlama1_1BQ4_0
print()
print("\(model.name): \(String(format: "%.3f", Double(model.tensorBytes) / 1e9)) GB of weights, KV \(model.kv?.bytesPerToken ?? 0) bytes/token")
print("  context   bytes/token   peak decode          sustained")
for context in [128, 256, 1024, 2048] {
    let estimate = report.estimate(model, contextTokens: context)
    let sustained = estimate.sustained.map(tokPerSec) ?? "n/a"
    print("  \(String(context).padding(toLength: 8, withPad: " ", startingAt: 0))  "
        + "\(String(estimate.bytesPerToken).padding(toLength: 12, withPad: " ", startingAt: 0))  "
        + "\(tokPerSec(estimate.peak).padding(toLength: 20, withPad: " ", startingAt: 0)) \(sustained)")
}
let example = report.estimate(model, contextTokens: 256)
let efficiency = example.efficiency.isKnown
    ? String(format: "%.4f–%.4f (%@)", example.efficiency.low, example.efficiency.high, "\(example.efficiency.basis)")
    : "unknown"
print("  basis: peak \(example.peak.basis); efficiency η = \(efficiency)")
for note in example.notes {
    print("  note: \(note)")
}
// A device whose own measurements are in the calibration gets an in-sample
// estimate: it can show that the arithmetic closes, not that the method predicts.
if let row = Calibration.shipped.bandwidth.first(where: { $0.device.contains("(\(device.identifier))") }) {
    var parts: [String] = []
    if row.ceilingGBps != nil {
        parts.append("η")
    }
    if Calibration.shipped.sustained.contains(where: { $0.soc == row.soc && $0.platform == device.platform }) {
        parts.append("the sustained factor")
    }
    if !parts.isEmpty {
        print("  note: in-sample: \(device.identifier) is a calibration device (\(row.soc)), so "
            + "\(parts.joined(separator: " and ")) \(parts.count == 1 ? "includes" : "include") its own measurements; "
            + "this estimate checks the arithmetic, not the method.")
    }
}
if device.chip == "Apple M1" {
    print()
    print("PocketRoofline measured on an M1 MacBook Pro, same model and quantisation (llama-bench, tg128 / tg1024):")
    print("  61.10 tok/s SISO, 64.55 tok/s SILO — compare with the 128–1024 rows above.")
}
