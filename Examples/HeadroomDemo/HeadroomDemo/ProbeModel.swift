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
                outcome = .finished(try await probe.value)
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

    /// Puts the report on the pasteboard so a phone's result can be pasted
    /// into `calibration.json`.
    func copyJSON() {
        guard case let .finished(report) = phase, let data = try? report.jsonData() else { return }
        UIPasteboard.general.string = String(decoding: data, as: UTF8.self)
    }
}
