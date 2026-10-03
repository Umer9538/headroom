import CHeadroom
import Testing
@testable import Headroom

@Suite struct StreamAccountingTests {
    @Test func kernelsTouchTheRightNumberOfArrays() {
        let arrayBytes = 128 << 20
        #expect(StreamKernel.copy.bytesPerIteration(arrayBytes: arrayBytes) == 2 * arrayBytes)
        #expect(StreamKernel.scale.bytesPerIteration(arrayBytes: arrayBytes) == 2 * arrayBytes)
        #expect(StreamKernel.add.bytesPerIteration(arrayBytes: arrayBytes) == 3 * arrayBytes)
        #expect(StreamKernel.triad.bytesPerIteration(arrayBytes: arrayBytes) == 3 * arrayBytes)
    }

    @Test func gigabytesPerSecondAreDecimal() {
        // 3 × 128 MiB in 6.7 ms is just over 60 GB/s.
        let bytes = StreamKernel.triad.bytesPerIteration(arrayBytes: 128 << 20)
        let rate = BandwidthFigure.gigabytesPerSecond(bytes: bytes, seconds: 0.0067)
        #expect(abs(rate - 60.097) < 0.001)
    }

    @Test func figureSummarisesIterations() {
        let figure = Fixtures.figure(gbps: [58, 61, 59, 60, 62])
        #expect(abs(figure.bestGBps.value - 62) < 1e-9)
        #expect(abs(figure.medianGBps.value - 60) < 1e-9)
        #expect(figure.medianCI95GBps.low <= 60 && figure.medianCI95GBps.high >= 60)
        #expect(figure.medianGBps.basis == .measured)
        #expect(figure.iterationGBps.count == 5)
    }

    @Test func unverifiedFigureIsNotMeasured() {
        let figure = Fixtures.figure(gbps: [60, 60], verified: false)
        #expect(figure.medianGBps.basis == .unknown)
        #expect(figure.medianCI95GBps.basis == .unknown)
    }

    @Test func gpuArraySizesMustBeWholeThreadgroups() {
        #expect(MetalBandwidthProbe.isValid(arrayBytes: 128 << 20))
        #expect(MetalBandwidthProbe.isValid(arrayBytes: 4096))
        #expect(!MetalBandwidthProbe.isValid(arrayBytes: 4096 + 16))
        #expect(!MetalBandwidthProbe.isValid(arrayBytes: 0))
    }

    @Test func cpuArraySizesMustBeWholeFloats() {
        var options = ProbeOptions()
        options.cpuArrayBytes = 4 << 20
        #expect(throws: Never.self) { try options.validate() }
        options.cpuArrayBytes = (4 << 20) + 2
        #expect(throws: HeadroomError.self) { try options.validate() }
    }

    /// The CPU figure is the best thread count's; an unverified run never wins
    /// over a verified one however fast it claims to be.
    @Test func bestCPUAttemptIsTheHighestVerifiedMedian() {
        let slow = CPUBandwidth.Attempt(threads: 8, triad: Fixtures.figure(arrayBytes: 64 << 20, gbps: [44, 45, 46]))
        let fast = CPUBandwidth.Attempt(threads: 4, triad: Fixtures.figure(arrayBytes: 64 << 20, gbps: [51, 52, 53]))
        let wrong = CPUBandwidth.Attempt(threads: 2, triad: Fixtures.figure(arrayBytes: 64 << 20, gbps: [90, 90, 90], verified: false))
        #expect(CPUBandwidth.best(of: [slow, fast, wrong]).threads == 4)
        #expect(CPUBandwidth.best(of: [wrong]).triad.medianGBps.basis == .unknown)
    }

    @Test func automaticThreadCountsEndWithEveryCore() {
        #expect(CPUTriadProbe.candidateThreadCounts(requested: 3) == [3])
        let automatic = CPUTriadProbe.candidateThreadCounts(requested: 0)
        #expect(automatic.last == Int(headroom_online_cpus()))
        #expect(Set(automatic).count == automatic.count)
        #expect(automatic.allSatisfy { $0 > 0 })
    }
}
