import Headroom
import Observation
import UIKit

@MainActor
@Observable
final class ProbeModel {
    enum Phase {
        case idle
        case running
        case finished(ProbeReport)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private var task: Task<ProbeReport, any Error>?

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    func start() {
        task?.cancel()
        phase = .running
        let probe = Task { try await Headroom.probe() }
        task = probe
        Task {
            let outcome: Phase
            do {
                let report = try await probe.value
                save(report)
                outcome = .finished(report)
            } catch is CancellationError {
                outcome = .idle
            } catch {
                outcome = .failed(String(describing: error))
            }
            // A probe that was replaced by a newer one must not overwrite its phase.
            if task == probe {
                phase = outcome
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    /// `-HeadroomAutoProbe <n>` on the launch arguments runs n probes in a row,
    /// five seconds apart, so a phone can be measured from a script
    /// (`xcrun devicectl device process launch … -HeadroomAutoProbe 3`).
    func autoProbeIfRequested() async {
        let count = UserDefaults.standard.integer(forKey: "HeadroomAutoProbe")
        guard count > 0 else { return }
        for run in 1...count {
            if run > 1 {
                try? await Task.sleep(for: .seconds(5))
            }
            start()
            _ = try? await task?.value
        }
    }

    /// Every finished probe is written to Documents as well, so a device's
    /// reports can be pulled with `devicectl` or opened in the Files app.
    private func save(_ report: ProbeReport) {
        guard let data = try? report.jsonData(),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return }
        let name = "headroom-\(report.device.identifier)-\(Int(report.capturedAt.timeIntervalSince1970)).json"
        try? data.write(to: documents.appending(path: name), options: .atomic)
    }

    /// Puts the report on the pasteboard so a phone's result can be pasted
    /// into `calibration.json`.
    func copyJSON() {
        guard case let .finished(report) = phase, let data = try? report.jsonData() else { return }
        UIPasteboard.general.string = String(decoding: data, as: UTF8.self)
    }
}
