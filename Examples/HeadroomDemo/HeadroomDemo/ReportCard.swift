import Headroom
import SwiftUI

struct ReportCard: View {
    let report: ProbeReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(report.device.identifier) · \(report.device.platform.rawValue) \(report.device.osVersion) (\(report.device.osBuild))")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)

            if let gpu = report.gpu {
                ceilingRow(title: "GPU ceiling (Metal triad)", figure: gpu.triad)
            } else {
                labelled("GPU ceiling", "not measured", basis: .unknown)
            }
            if let cpu = report.cpu {
                ceilingRow(title: "CPU triad, \(cpu.threads) threads", figure: cpu.triad)
            }

            Divider()

            labelled("Thermal", report.conditions.thermalState.rawValue, basis: .measured)
            labelled("Power", powerDescription, basis: .measured)
            labelled("Memory", String(format: "%.2f GB physical", Double(report.memory.physicalBytes) / 1e9), basis: .measured)
            labelled(
                "Available",
                String(format: "%.2f GB", Double(report.memory.availableBytes.value) / 1e9),
                basis: report.memory.availableBytes.basis
            )

            ForEach(report.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var powerDescription: String {
        var text = report.conditions.powerSource.rawValue
        if let level = report.conditions.batteryLevel {
            text += String(format: ", %.0f%%", level * 100)
        }
        if report.conditions.isLowPowerModeEnabled {
            text += ", low power mode"
        }
        return text
    }

    private func ceilingRow(title: String, figure: BandwidthFigure) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold))
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%.1f GB/s", figure.medianGBps.value))
                    .font(.title2.monospacedDigit().weight(.semibold))
                Text(String(format: "95%% CI %.1f–%.1f, best %.1f", figure.medianCI95GBps.low, figure.medianCI95GBps.high, figure.bestGBps.value))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            BasisTag(basis: figure.medianGBps.basis)
        }
    }

    private func labelled(_ title: String, _ value: String, basis: Basis) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
            BasisTag(basis: basis)
        }
        .font(.subheadline)
    }
}

/// The basis is never implied; it is printed next to every figure.
struct BasisTag: View {
    let basis: Basis

    var body: some View {
        Text(basis.description)
            .font(.caption2.monospaced())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch basis {
        case .measured: .green
        case .calibrated: .blue
        case .unknown: .orange
        }
    }
}
