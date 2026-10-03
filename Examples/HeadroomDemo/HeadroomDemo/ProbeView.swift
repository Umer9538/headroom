import Headroom
import SwiftUI

struct ProbeView: View {
    @State private var model = ProbeModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("A two-second probe of this phone's memory bandwidth, and what it means for a model of a given size. Every figure says whether it was measured here or calibrated elsewhere.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Button {
                        if model.isRunning {
                            model.cancel()
                        } else {
                            model.start()
                        }
                    } label: {
                        HStack {
                            if model.isRunning {
                                ProgressView().tint(.white)
                            }
                            Text(model.isRunning ? "Cancel" : "Probe")
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)

                    switch model.phase {
                    case .idle, .running:
                        EmptyView()
                    case let .failed(message):
                        Text(message)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.red)
                    case let .finished(report):
                        ReportCard(report: report)
                        EstimateTable(report: report)
                        Button("Copy JSON", systemImage: "doc.on.doc", action: model.copyJSON)
                            .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .navigationTitle("Headroom")
        }
    }
}

#Preview {
    ProbeView()
}
