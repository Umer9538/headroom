import Metal
import Testing
@testable import Headroom

/// Runs the real probe on the test host. Magnitude checks only: an Apple
/// Silicon Mac or iPhone lands in the tens of GB/s, and anything outside
/// 5–200 GB/s means the kernels or the byte accounting are wrong.
@Suite(.serialized) struct ProbeIntegrationTests {
    static let hasMetal = MTLCreateSystemDefaultDevice() != nil

    @Test(.enabled(if: hasMetal)) func gpuProbeMeasuresAPlausibleCeiling() async throws {
        var options = ProbeOptions()
        options.runsCPUProbe = false
        let report = try await Headroom.probe(options: options)
        let gpu = try #require(report.gpu)

        for figure in [gpu.copy, gpu.scale, gpu.add, gpu.triad] {
            #expect(figure.verified, "\(figure.kernel) output did not match")
            #expect(figure.iterationSeconds.count == options.gpuTimedIterations)
            #expect(figure.medianGBps.basis == .measured)
            #expect((5...200).contains(figure.medianGBps.value), "\(figure.kernel): \(figure.medianGBps.value) GB/s")
            #expect(figure.medianCI95GBps.low <= figure.medianGBps.value)
            #expect(figure.medianGBps.value <= figure.medianCI95GBps.high)
            #expect(figure.bestGBps.value >= figure.medianGBps.value)
        }
        #expect(gpu.triad.bytesPerIteration == 3 * options.gpuArrayBytes)
        #expect(report.ceilingGBps == gpu.triad.medianGBps)
        #expect(report.warnings.isEmpty)
    }

    @Test func cpuProbeRunsAndVerifies() async throws {
        var options = ProbeOptions()
        options.runsGPUProbe = false
        let report = try await Headroom.probe(options: options)
        let cpu = try #require(report.cpu)

        #expect(cpu.triad.verified)
        #expect(cpu.threads >= 1)
        #expect(cpu.triad.iterationSeconds.count == options.cpuTimedIterations)
        #expect(cpu.triad.bytesPerIteration == 3 * options.cpuArrayBytes)
        #expect(cpu.attempts.map(\.threads) == CPUTriadProbe.candidateThreadCounts(requested: 0))
        #expect(cpu.attempts.contains { $0.threads == cpu.threads && $0.triad == cpu.triad })
        #expect(cpu.attempts.allSatisfy { $0.triad.verified && $0.triad.medianGBps.value <= cpu.triad.medianGBps.value })
        // Debug test builds compile the C target without optimisation, which the
        // report must say rather than hide.
        #expect(cpu.triad.medianGBps.basis == (cpu.compiledWithOptimisation ? .measured : .unknown))
        if cpu.compiledWithOptimisation {
            #expect((5...200).contains(cpu.triad.medianGBps.value))
        }
    }

    @Test func invalidOptionsAreRejectedBeforeAnythingRuns() async {
        var options = ProbeOptions()
        options.gpuArrayBytes = 4096 + 16
        await #expect(throws: HeadroomError.self) {
            try await Headroom.probe(options: options)
        }
    }

    @Test func cancellationStopsTheProbe() async {
        let task = Task { try await Headroom.probe() }
        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test func reportCarriesConditionsAndMemory() async throws {
        var options = ProbeOptions()
        options.runsGPUProbe = false
        options.runsCPUProbe = false
        let report = try await Headroom.probe(options: options)
        #expect(report.memory.physicalBytes > 0)
        #expect(!report.device.identifier.isEmpty)
        #expect(!report.device.osBuild.isEmpty)
        #expect(report.durationSeconds >= 0)
        #if os(macOS)
        #expect(report.device.platform == .macOS)
        #expect(report.memory.availableBytes.basis == .unknown)
        #endif
    }
}
