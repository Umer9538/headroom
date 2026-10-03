import Testing
@testable import Headroom

@Suite struct MemoryFitTests {
    /// 1.0 GB of weights, no KV geometry: required = 1.1 GB + 150 MB = 1.25 GB.
    let model = ModelSpec(name: "1 GB", ggufBytes: 1_000_000_000)

    @Test func requirementFollowsTheStatedAssumptions() {
        #expect(MemoryFit.requiredBytes(for: model, contextTokens: 4096) == 1_250_000_000)
        let tinyLlama = ModelSpec.tinyLlama1_1BQ4_0
        let expected = Int((635_990_016.0 * 1.1).rounded()) + 1024 * 22_528 + 150_000_000
        #expect(MemoryFit.requiredBytes(for: tinyLlama, contextTokens: 1024) == expected)
    }

    @Test func fitsWithRoom() {
        let fit = MemoryFit(model: model, contextTokens: 0, available: Quantity(2_000_000_000, basis: .measured))
        #expect(fit.verdict == .fits(marginMB: 750))
        #expect(fit.basis == .measured)
    }

    @Test func tightWhenTheMarginIsInsideTheSlack() {
        // Margin 50 MB is under 10% of the 1.25 GB requirement.
        let fit = MemoryFit(model: model, contextTokens: 0, available: Quantity(1_300_000_000, basis: .measured))
        #expect(fit.verdict == .tight(marginMB: 50))
    }

    @Test func doesNotFitReportsTheShortfall() {
        let fit = MemoryFit(model: model, contextTokens: 0, available: Quantity(1_000_000_000, basis: .measured))
        #expect(fit.verdict == .doesNotFit(shortfallMB: 250))
    }

    /// A probe never allocates past a measured budget; with no budget known it
    /// is not the probe's place to refuse.
    @Test func probesRefuseToExceedAMeasuredBudget() {
        let measured = MemoryInfo(physicalBytes: 4_000_000_000, availableBytes: Quantity(300_000_000, basis: .measured))
        #expect(measured.refusal(allocating: 3 * (128 << 20)) != nil)
        #expect(measured.refusal(allocating: 3 * (64 << 20)) == nil)
        let unknown = MemoryInfo(physicalBytes: 4_000_000_000, availableBytes: Quantity(0, basis: .unknown))
        #expect(unknown.refusal(allocating: 3 * (128 << 20)) == nil)
    }

    @Test func verdictInheritsTheBasisOfAvailableMemory() {
        let fit = MemoryFit(model: model, contextTokens: 0, available: Quantity(8_000_000_000, basis: .unknown))
        #expect(fit.basis == .unknown)
        let report = Fixtures.report(availableBytes: Quantity(8_000_000_000, basis: .unknown))
        let estimate = report.estimate(model, contextTokens: 0, calibration: Calibration(bandwidth: [], sustained: []))
        #expect(estimate.fit.basis == .unknown)
        #expect(estimate.notes.contains { $0.contains("Available memory is a fallback") })
    }
}
