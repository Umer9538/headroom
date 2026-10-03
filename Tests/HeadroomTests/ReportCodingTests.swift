import Foundation
import Testing
@testable import Headroom

@Suite struct ReportCodingTests {
    @Test func reportRoundTripsThroughJSON() throws {
        let report = Fixtures.report()
        let data = try report.jsonData()
        let decoded = try ProbeReport(jsonData: data)
        #expect(decoded == report)
    }

    /// ISO 8601 has whole seconds; a report must not change identity by being saved.
    @Test func captureTimeSurvivesTheJSONRoundTrip() throws {
        let report = Fixtures.report(capturedAt: Date(timeIntervalSince1970: 1_790_000_000.731))
        #expect(report.capturedAt == Date(timeIntervalSince1970: 1_790_000_000))
        let decoded = try ProbeReport(jsonData: try report.jsonData())
        #expect(decoded == report)
    }

    @Test func reportWithoutGPUSectionRoundTrips() throws {
        let report = Fixtures.report(triadGBps: nil)
        let decoded = try ProbeReport(jsonData: try report.jsonData())
        #expect(decoded == report)
        #expect(decoded.gpu == nil)
    }

    @Test func estimateRoundTripsIncludingUnknownIntervals() throws {
        let report = Fixtures.report(triadGBps: nil)
        let estimate = report.estimate(.tinyLlama1_1BQ4_0, contextTokens: 1024)
        let data = try ProbeReport.jsonEncoder.encode(estimate)
        let decoded = try ProbeReport.jsonDecoder.decode(Estimate.self, from: data)
        #expect(decoded == estimate)
        #expect(decoded.peak == .unknown)

        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"high\" : null"))
    }

    /// The records the M1 ceiling was derived from must stay readable by the
    /// library that wrote them, whatever the report gains later.
    @Test func committedCalibrationRunsDecode() throws {
        let runs = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Calibration/runs")
        let files = try FileManager.default.contentsOfDirectory(at: runs, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        #expect(files.count == 3)
        for file in files {
            let report = try ProbeReport(jsonData: try Data(contentsOf: file))
            let cpu = try #require(report.cpu, Comment(rawValue: file.lastPathComponent))
            #expect(report.device.identifier == "MacBookPro17,1")
            #expect(report.gpu?.triad.medianGBps.basis == .measured)
            #expect(cpu.attempts == [CPUBandwidth.Attempt(threads: cpu.threads, triad: cpu.triad)])
        }
    }

    @Test func basisEncodesItsKindAndDeviceCount() throws {
        let data = try JSONEncoder().encode(Basis.calibrated(devices: 2))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["kind"] as? String == "calibrated")
        #expect(object["devices"] as? Int == 2)
        for basis in [Basis.measured, .calibrated(devices: 5), .unknown] {
            let decoded = try JSONDecoder().decode(Basis.self, from: try JSONEncoder().encode(basis))
            #expect(decoded == basis)
        }
    }

    @Test func memoryFitEncodesASignedMargin() throws {
        let model = ModelSpec(name: "1 GB", ggufBytes: 1_000_000_000)
        let fit = MemoryFit(model: model, contextTokens: 0, available: Quantity(1_000_000_000, basis: .measured))
        let data = try JSONEncoder().encode(fit)
        let decoded = try JSONDecoder().decode(MemoryFit.self, from: data)
        #expect(decoded == fit)
        #expect(String(decoding: data, as: UTF8.self).contains("\"marginMB\":-250"))
    }
}
