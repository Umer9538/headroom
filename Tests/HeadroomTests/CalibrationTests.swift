import Testing
@testable import Headroom

@Suite struct CalibrationTests {
    @Test func shippedCalibrationLoads() {
        let calibration = Calibration.shipped
        #expect(calibration.schemaVersion == 1)
        #expect(calibration.bandwidth.map(\.soc) == ["A15 Bionic", "Apple M1", "A16 Bionic"])
        #expect(calibration.sustained.map(\.soc) == ["A15 Bionic", "A18 Pro", "A16 Bionic"])
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

        // The A16 row is the PocketRoofline app's capture, committed here; its
        // repeats are full doubles, so the row stores the mean to four decimals
        // and the bandwidth to three.
        let a16 = try #require(rows.first { $0.soc == "A16 Bionic" })
        let decode = Fixtures.mean(try Fixtures.a16Capture().decodeRates("SISO"))
        #expect(abs(a16.decodeTokPerSec - decode) < 0.5e-4)
        let achieved = Calibration.achievedGBps(decodeTokPerSec: decode, bytesPerToken: Fixtures.tensorBytes)
        #expect(abs(a16.achievedGBps - achieved) < 0.5e-3)
    }

    /// n = 2: the M1 and the A16 are the devices with a measured ceiling, each
    /// ceiling is the median of its committed probe runs, and η spans exactly
    /// their two values, the M1's at the bottom and the A16's at the top.
    @Test func efficiencySpansTheM1AndTheA16() throws {
        let calibration = Calibration.shipped
        let probed = calibration.bandwidth.filter { $0.ceilingGBps != nil }
        #expect(probed.map(\.soc) == ["Apple M1", "A16 Bionic"])
        let m1 = try #require(probed.first { $0.soc == "Apple M1" })
        let a16 = try #require(probed.first { $0.soc == "A16 Bionic" })

        let m1Runs = try Fixtures.m1Runs()
        let a16Probes = try Fixtures.a16Probes()
        #expect(m1Runs.count == 3)
        #expect(a16Probes.count == 4)
        #expect(abs(try #require(m1.ceilingGBps) - (try Fixtures.ceilingGBps(of: m1Runs))) < 0.5e-3)
        #expect(abs(try #require(a16.ceilingGBps) - (try Fixtures.ceilingGBps(of: a16Probes))) < 0.5e-3)

        let m1Efficiency = try #require(m1.efficiency)
        let a16Efficiency = try #require(a16.efficiency)
        #expect(m1Efficiency < a16Efficiency)
        #expect(calibration.efficiency == Interval(low: m1Efficiency, high: a16Efficiency, basis: .calibrated(devices: 2)))

        // The same η recomputed from the records alone, not the stored columns.
        let a16Decode = Fixtures.mean(try Fixtures.a16Capture().decodeRates("SISO"))
        let a16FromRecords = Calibration.achievedGBps(decodeTokPerSec: a16Decode, bytesPerToken: Fixtures.tensorBytes)
            / (try Fixtures.ceilingGBps(of: a16Probes))
        let m1FromRecords = Calibration.achievedGBps(decodeTokPerSec: Fixtures.mean(Fixtures.m1DecodeRepeats), bytesPerToken: Fixtures.tensorBytes)
            / (try Fixtures.ceilingGBps(of: m1Runs))
        #expect(abs(a16Efficiency - a16FromRecords) < 1e-4)
        #expect(abs(m1Efficiency - m1FromRecords) < 1e-4)
        // The figures Calibration/README.md and the README quote.
        #expect(abs(m1Efficiency - 0.6939) < 0.0001)
        #expect(abs(a16Efficiency - 0.9145) < 0.0001)
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

        // The A16's from its record: the last SILO repeat over the SISO mean.
        let a16 = try #require(calibration.sustained.first { $0.soc == "A16 Bionic" })
        let capture = try Fixtures.a16Capture()
        let siso = try capture.decodeRates("SISO")
        let lastSILO = try #require(try capture.decodeRates("SILO").last)
        #expect(a16.peakTokPerSec == calibration.bandwidth.first { $0.soc == "A16 Bionic" }?.decodeTokPerSec)
        #expect(abs(a16.sustainedTokPerSec - lastSILO) < 0.5e-4)
        #expect(abs(a16.factor - lastSILO / Fixtures.mean(siso)) < 1e-5)
        #expect(abs(a16.factor - 0.4169) < 0.0001)

        // Three phones; the A16 is the lowest factor and widens the range.
        let factor = try #require(calibration.sustainedFactor(platform: .iOS))
        #expect(factor.low == a16.factor)
        #expect(factor.high == a15.factor)
        #expect(factor.basis == .calibrated(devices: 3))
        #expect(calibration.sustainedFactor(platform: .macOS) == nil)
        #expect(calibration.sustainedFactor(platform: .iOSSimulator) == nil)
    }
}
