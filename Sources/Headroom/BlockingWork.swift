import Dispatch
import os

/// Runs blocking work on a Dispatch queue instead of a Swift concurrency
/// thread, so a probe that pins a core for a few hundred milliseconds never
/// holds up the cooperative pool or the main actor.
///
/// Cancelling the calling task raises `isCancelled` for the work to poll
/// between stages; the work decides where it is safe to stop.
enum BlockingWork {
    static func run<T: Sendable>(
        qos: DispatchQoS.QoSClass = .userInitiated,
        _ work: @escaping @Sendable (_ isCancelled: @escaping @Sendable () -> Bool) throws -> T
    ) async throws -> T {
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: qos).async {
                    continuation.resume(with: Result {
                        try work { cancelled.withLock { $0 } }
                    })
                }
            }
        } onCancel: {
            cancelled.withLock { $0 = true }
        }
    }
}
