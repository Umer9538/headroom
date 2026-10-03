import Headroom
import SwiftUI

struct EstimateTable: View {
    let report: ProbeReport

    /// One verified model and three size classes known only by file size.
    private static let models: [ModelSpec] = [
        .tinyLlama1_1BQ4_0,
        ModelSpec(name: "1.1 GB model", ggufBytes: 1_100_000_000),
        ModelSpec(name: "2.2 GB model", ggufBytes: 2_200_000_000),
        ModelSpec(name: "4.4 GB model", ggufBytes: 4_400_000_000),
    ]
    private static let contextTokens = 1024

    private var estimates: [Estimate] {
        Self.models.map { report.estimate($0, contextTokens: Self.contextTokens) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Decode estimate at \(Self.contextTokens) tokens of context")
                .font(.subheadline.weight(.semibold))

            ForEach(estimates, id: \.model) { estimate in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(estimate.model.name).font(.subheadline)
                        Spacer()
                        FitTag(fit: estimate.fit)
                    }
                    row("peak", interval: estimate.peak)
                    if let sustained = estimate.sustained {
                        row("sustained", interval: sustained)
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }

            ForEach(Array(Set(estimates.flatMap(\.notes))).sorted(), id: \.self) { note in
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ title: String, interval: Interval) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(interval.isKnown ? String(format: "%.0f–%.0f tok/s", interval.low, interval.high) : "unknown")
                .monospacedDigit()
            BasisTag(basis: interval.basis)
        }
        .font(.subheadline)
    }
}

struct FitTag: View {
    let fit: MemoryFit

    var body: some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .foregroundStyle(fit.basis == .unknown ? .orange : color)
    }

    private var text: String {
        let verdict = switch fit.verdict {
        case let .fits(marginMB): String(format: "fits, %.0f MB spare", marginMB)
        case let .tight(marginMB): String(format: "tight, %.0f MB spare", marginMB)
        case let .doesNotFit(shortfallMB): String(format: "%.0f MB short", shortfallMB)
        }
        return fit.basis == .unknown ? "\(verdict) (unknown)" : verdict
    }

    private var color: Color {
        switch fit.verdict {
        case .fits: .green
        case .tight: .orange
        case .doesNotFit: .red
        }
    }
}
