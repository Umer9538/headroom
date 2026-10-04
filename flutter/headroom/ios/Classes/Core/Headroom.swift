import Foundation

public enum Headroom {
    public static let version = "0.1.0"

    /// Measures this device's memory-bandwidth ceilings and records the
    /// conditions they were measured under.
    ///
    /// Takes one to two seconds. The heavy work runs on a Dispatch queue, never
    /// on the caller's actor, and stops at the next kernel boundary if the task
    /// is cancelled. A probe that cannot run (no Metal, allocation failure, not
    /// enough memory budget for its arrays) is reported in `warnings` with its
    /// section nil rather than thrown, so the rest of the report is still usable.
    public static func probe(options: ProbeOptions = ProbeOptions()) async throws -> ProbeReport {
        try options.validate()
        let clock = ContinuousClock()
        let started = clock.now
        let capturedAt = Date()

        let device = DeviceInfo.current()
        let conditions = await Conditions.current()
        let memory = MemoryInfo.current()
        var warnings: [String] = []
        if device.isSimulator {
            warnings.append("Running in the iOS Simulator: the bandwidth figures are the host Mac's, not a phone's.")
        }

        try Task.checkCancellation()
        var gpu: GPUBandwidth?
        if options.runsGPUProbe {
            if device.isSimulator {
                // The simulator's command-buffer timestamps do not bracket the GPU
                // work (128 MB dispatches report tens of microseconds), so any
                // figure would be thousands of GB/s of nonsense labelled measured.
                warnings.append("GPU probe skipped: Metal timestamps in the iOS Simulator do not measure GPU work.")
            } else if let refusal = memory.refusal(allocating: 3 * options.gpuArrayBytes) {
                warnings.append("GPU probe skipped: \(refusal)")
            } else {
                let probe = MetalBandwidthProbe(
                    arrayBytes: options.gpuArrayBytes,
                    warmupIterations: options.gpuWarmupIterations,
                    timedIterations: options.gpuTimedIterations
                )
                do {
                    gpu = try await BlockingWork.run { isCancelled in
                        try probe.run(isCancelled: isCancelled)
                    }
                } catch let cancellation as CancellationError {
                    throw cancellation
                } catch {
                    warnings.append("GPU probe did not run: \(error)")
                }
            }
        }

        try Task.checkCancellation()
        var cpu: CPUBandwidth?
        if options.runsCPUProbe {
            if let refusal = memory.refusal(allocating: 3 * options.cpuArrayBytes) {
                warnings.append("CPU probe skipped: \(refusal)")
            } else {
                let probe = CPUTriadProbe(
                    arrayBytes: options.cpuArrayBytes,
                    threads: options.cpuThreads,
                    warmupIterations: options.cpuWarmupIterations,
                    timedIterations: options.cpuTimedIterations
                )
                do {
                    cpu = try await BlockingWork.run { isCancelled in
                        try probe.run(isCancelled: isCancelled)
                    }
                } catch let cancellation as CancellationError {
                    throw cancellation
                } catch {
                    warnings.append("CPU probe did not run: \(error)")
                }
                if let cpu, !cpu.compiledWithOptimisation {
                    warnings.append("CHeadroom was compiled without optimisation; the CPU triad figure is not a ceiling and carries basis unknown.")
                }
            }
        }

        try Task.checkCancellation()
        let elapsed = clock.now - started
        return ProbeReport(
            capturedAt: capturedAt,
            durationSeconds: Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18,
            device: device,
            conditions: conditions,
            memory: memory,
            gpu: gpu,
            cpu: cpu,
            warnings: warnings
        )
    }
}
