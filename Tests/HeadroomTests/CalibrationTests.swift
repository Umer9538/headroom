import Testing
@testable import Headroom

@Suite struct CalibrationTests {
    @Test func shippedCalibrationLoads() {
        let calibration = Calibration.shipped
        #expect(calibration.schemaVersion == 1)
        #expect(calibration.bandwidth.map(\.soc) == ["A15 Bionic", "Apple M1"])
        #expect(calibration.sustained.count == 2)
    }

    /// The stored achievedGBps is a convenience; the inputs are the record.
    @Test func storedAchievedBandwidthAgreesWithItsInputs() {
        for row in Calibration.shipped.bandwidth {
            #expect(abs(row.achievedGBps - row.recomputedAchievedGBps) < 0.001, "\(row.soc)")
            #expect(row.tensorBytes == ModelSpec.tinyLlama1_1BQ4_0.tensorBytes)
        }
    }

    @Test func shippedRowsMatchPocketRoofline() throws {
        let rows = Calibration.shipped.bandwidth
        let a15 = try #require(rows.first { $0.soc == "A15 Bionic" })
        let m1 = try #require(rows.first { $0.soc == "Apple M1" })
        #expect(abs(a15.decodeTokPerSec - Fixtures.mean(Fixtures.a15DecodeRepeats)) < 1e-9)
        #expect(abs(m1.decodeTokPerSec - Fixtures.mean(Fixtures.m1DecodeRepeats)) < 1e-9)
        #expect(abs(a15.achievedGBps - 27.221) < 0.001)
        #expect(abs(m1.achievedGBps - 38.860) < 0.001)
    }

    /// The A15 stays null until the owner runs the demo on the iPhone 13.
    @Test func nullCeilingRowsAreExcludedFromEfficiency() throws {
        let calibration = Calibration.shipped
        let a15 = try #require(calibration.bandwidth.first { $0.soc == "A15 Bionic" })
        #expect(a15.ceilingGBps == nil)
        #expect(a15.efficiency == nil)

        let probed = calibration.bandwidth.filter { $0.ceilingGBps != nil }
        if probed.isEmpty {
            #expect(calibration.efficiency == .unknown)
        } else {
            #expect(calibration.efficiency.basis == .calibrated(devices: probed.count))
            for row in probed {
                let efficiency = try #require(row.efficiency)
                #expect(efficiency > 0 && efficiency < 1, "decode cannot exceed the ceiling on \(row.soc)")
                #expect(calibration.efficiency.low <= efficiency && efficiency <= calibration.efficiency.high)
            }
        }
    }

    @Test func efficiencyIsUnknownWithoutAnyProbedDevice() {
        let calibration = Calibration(
            bandwidth: [Fixtures.bandwidthRow(soc: "A", decode: 40, ceilingGBps: nil)],
            sustained: []
        )
        #expect(calibration.efficiency == .unknown)
        #expect(calibration.sustainedFactor(platform: .iOS) == nil)
    }

    @Test func sustainedFactorsAreComputedFromTheRows() throws {
        let calibration = Calibration.shipped
        let a15 = try #require(calibration.sustained.first { $0.soc == "A15 Bionic" })
        let a18 = try #require(calibration.sustained.first { $0.soc == "A18 Pro" })
        #expect(abs(a15.factor - 30.933 / 42.8012) < 1e-9)
        #expect(abs(a15.factor - 0.7227) < 0.0001)
        #expect(abs(a18.factor - 23.67 / 40.49) < 1e-9)
        #expect(abs(a18.factor - 0.5846) < 0.0001)

        let factor = try #require(calibration.sustainedFactor(platform: .iOS))
        #expect(abs(factor.low - 0.5846) < 0.0001)
        #expect(abs(factor.high - 0.7227) < 0.0001)
        #expect(factor.basis == .calibrated(devices: 2))
        #expect(calibration.sustainedFactor(platform: .macOS) == nil)
        #expect(calibration.sustainedFactor(platform: .iOSSimulator) == nil)
    }
}
