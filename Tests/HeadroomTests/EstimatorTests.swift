import Testing
@testable import Headroom

/// The arithmetic PocketRoofline published, reproduced from its committed
/// decode figures, and the prediction formula built on top of it.
@Suite struct EstimatorTests {
    @Test func a15AchievedBandwidthReproduces() {
        let decode = Fixtures.mean(Fixtures.a15DecodeRepeats)
        #expect(abs(decode - 42.8012) < 1e-9)
        let achieved = Calibration.achievedGBps(decodeTokPerSec: decode, bytesPerToken: Fixtures.tensorBytes)
        #expect(abs(achieved - 27.2) < 0.05)
        #expect(abs(achieved - 27.221) < 0.001)
    }

    @Test func m1AchievedBandwidthReproduces() {
        let decode = Fixtures.mean(Fixtures.m1DecodeRepeats)
        #expect(abs(decode - 61.1016) < 1e-9)
        let achieved = Calibration.achievedGBps(decodeTokPerSec: decode, bytesPerToken: Fixtures.tensorBytes)
        #expect(abs(achieved - 38.9) < 0.05)
        #expect(abs(achieved - 38.860) < 0.001)
    }

    @Test func kvCacheBytesFollowTheFormula() {
        let model = ModelSpec.tinyLlama1_1BQ4_0
        // 2 (K and V) × 22 layers × 4 KV heads × 64 head dim × 2 bytes (f16)
        #expect(model.kv?.bytesPerToken == 22_528)
        #expect(model.kvBytes(contextTokens: 2048) == 46_137_344)
        #expect(model.bytesPerToken(contextTokens: 0) == model.tensorBytes)
        #expect(model.bytesPerToken(contextTokens: 256) == 635_990_016 + 256 * 22_528)
    }

    @Test func fileSizeOnlyModelsHaveNoKVTerm() {
        let model = ModelSpec(name: "2.2 GB", ggufBytes: 2_200_000_000)
        #expect(model.kv == nil)
        #expect(model.bytesPerToken(contextTokens: 4096) == 2_200_000_000)
    }

    /// With one calibrated device and a ceiling identical to the one it was
    /// calibrated on, the prediction must give back the decode rate it came from.
    @Test func peakReproducesTheCalibrationDecodeRate() {
        let decode = Fixtures.mean(Fixtures.m1DecodeRepeats)
        let calibration = Calibration(
            bandwidth: [Fixtures.bandwidthRow(soc: "Apple M1", decode: decode, ceilingGBps: 60)],
            sustained: []
        )
        let report = Fixtures.report(platform: .macOS, triadGBps: [60, 60, 60])
        let estimate = report.estimate(.tinyLlama1_1BQ4_0, contextTokens: 0, calibration: calibration)

        #expect(abs(estimate.peak.low - decode) < 1e-6)
        #expect(abs(estimate.peak.high - decode) < 1e-6)
        #expect(estimate.peak.basis == .calibrated(devices: 1))
        #expect(abs(estimate.efficiency.low - 38.86 / 60) < 0.001)
        #expect(estimate.sustained == nil, "no phone data applies to macOS")
    }

    @Test func peakIntervalSpansCeilingCIAndEfficiencyRange() {
        let calibration = Calibration(
            bandwidth: [
                Fixtures.bandwidthRow(soc: "A", decode: 40, ceilingGBps: 50),  // η = 0.5088
                Fixtures.bandwidthRow(soc: "B", decode: 60, ceilingGBps: 60),  // η = 0.6360
            ],
            sustained: [Fixtures.sustainedRow(soc: "A", peak: 40, sustained: 30)]
        )
        let report = Fixtures.report(platform: .iOS, triadGBps: [50, 52, 54, 56, 58])
        let estimate = report.estimate(.tinyLlama1_1BQ4_0, contextTokens: 0, calibration: calibration)
        let ceiling = report.gpu!.triad.medianCI95GBps

        let bytes = Double(Fixtures.tensorBytes)
        #expect(abs(estimate.peak.low - ceiling.low * estimate.efficiency.low * 1e9 / bytes) < 1e-6)
        #expect(abs(estimate.peak.high - ceiling.high * estimate.efficiency.high * 1e9 / bytes) < 1e-6)
        #expect(estimate.peak.low < estimate.peak.high)
        #expect(estimate.efficiency.basis == .calibrated(devices: 2))
        #expect(estimate.sustainedFactor?.basis == .calibrated(devices: 1))
        #expect(estimate.sustained?.low == estimate.peak.low * 0.75)
        #expect(estimate.sustained?.high == estimate.peak.high * 0.75)
    }

    @Test func noCeilingMeansUnknownNotZero() {
        let report = Fixtures.report(triadGBps: nil)
        let estimate = report.estimate(.tinyLlama1_1BQ4_0, contextTokens: 512)
        #expect(estimate.peak == .unknown)
        #expect(estimate.peak.basis == .unknown)
        #expect(estimate.ceilingGBps == nil)
        #expect(estimate.sustained.map { $0 == .unknown } ?? true)
        #expect(estimate.notes.contains { $0.contains("GPU probe did not run") })
    }

    @Test func unverifiedCeilingCannotProduceAMeasuredBasedPrediction() {
        let unverified = Fixtures.figure(gbps: [60, 60, 60], verified: false)
        let gpu = GPUBandwidth(deviceName: "x", arrayBytes: 128 << 20, copy: unverified, scale: unverified, add: unverified, triad: unverified)
        let base = Fixtures.report()
        let report = ProbeReport(
            capturedAt: base.capturedAt, durationSeconds: 1, device: base.device,
            conditions: base.conditions, memory: base.memory, gpu: gpu, cpu: nil, warnings: []
        )
        #expect(report.estimate(.tinyLlama1_1BQ4_0, contextTokens: 0).peak.basis == .unknown)
    }

    @Test func basisCombinationIsTheWeakestInput() {
        #expect(Basis.measured.combined(with: .measured) == .measured)
        #expect(Basis.measured.combined(with: .calibrated(devices: 3)) == .calibrated(devices: 3))
        #expect(Basis.calibrated(devices: 1).combined(with: .calibrated(devices: 2)) == .calibrated(devices: 1))
        #expect(Basis.calibrated(devices: 2).combined(with: .unknown) == .unknown)
    }

    @Test func intervalArithmetic() {
        let a = Interval(low: 2, high: 4, basis: .measured)
        let b = Interval(low: 0.5, high: 0.75, basis: .calibrated(devices: 2))
        let product = a.multiplied(by: b)
        #expect(product.low == 1 && product.high == 3)
        #expect(product.basis == .calibrated(devices: 2))
        #expect(a.divided(by: 2).high == 2)
        #expect(a.multiplied(by: Interval.unknown) == .unknown)
        #expect(Interval.unknown.divided(by: 7) == .unknown)
        #expect(!Interval.unknown.isKnown)
    }
}
