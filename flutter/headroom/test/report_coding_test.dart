import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/headroom.dart';

import 'fixtures.dart';

/// The Swift core's `ReportCodingTests`, plus the committed M1 run.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(Calibration.load);

  test('report round-trips through JSON', () {
    final report = Fixtures.report();
    final decoded = ProbeReport.fromJsonString(report.toJsonString());
    expect(decoded, report);
    expect(decoded.cpu!.attempts.length, 1);
  });

  /// ISO 8601 has whole seconds; a report must not change identity by being
  /// saved.
  test('capture time survives the JSON round trip', () {
    final report = Fixtures.report(
      capturedAt: DateTime.fromMillisecondsSinceEpoch(
        1790000000 * 1000 + 731,
        isUtc: true,
      ),
    );
    expect(
      report.capturedAt,
      DateTime.fromMillisecondsSinceEpoch(1790000000 * 1000, isUtc: true),
    );
    final json = report.toJson();
    expect(json['capturedAt'], '2026-09-21T14:13:20Z');
    expect(ProbeReport.fromJson(json), report);
  });

  test('report without GPU section round-trips', () {
    final report = Fixtures.report(triadGBps: null);
    final json = report.toJson();
    expect(json.containsKey('gpu'), isFalse);
    final decoded = ProbeReport.fromJson(json);
    expect(decoded, report);
    expect(decoded.gpu, isNull);
  });

  test('estimate round-trips including unknown intervals', () {
    final report = Fixtures.report(triadGBps: null);
    final estimate = report.estimate(
      ModelSpec.tinyLlama1_1BQ4_0,
      contextTokens: 1024,
    );
    final text = const JsonEncoder.withIndent('  ').convert(estimate.toJson());
    final decoded = Estimate.fromJson(jsonDecode(text) as Map<String, Object?>);
    expect(decoded, estimate);
    expect(decoded.peak, Interval.unknown);
    expect(text, contains('"high": null'));
  });

  test('the report printer sorts keys at every level', () {
    final text = Fixtures.report().toJsonString();
    final keys = [
      for (final line in text.split('\n'))
        if (line.startsWith('  "')) line.substring(3, line.indexOf('"', 3)),
    ];
    expect(keys, List.of(keys)..sort());
    expect(text, contains('"schemaVersion": 1'));
    expect(text.indexOf('"bestGBps"'), lessThan(text.indexOf('"bytesPerIteration"')));
  });

  test('basis encodes its kind and device count', () {
    final object = const Basis.calibrated(devices: 2).toJson();
    expect(object['kind'], 'calibrated');
    expect(object['devices'], 2);
    for (final basis in [
      Basis.measured,
      const Basis.calibrated(devices: 5),
      Basis.unknown,
    ]) {
      expect(Basis.fromJson(basis.toJson()), basis);
    }
    expect(() => Basis.fromJson({'kind': 'guessed'}), throwsFormatException);
  });

  test('memory fit encodes a signed margin', () {
    final model = ModelSpec.fromGgufBytes(name: '1 GB', ggufBytes: 1000000000);
    final fit = MemoryFit.compute(
      model: model,
      contextTokens: 0,
      available: const Quantity(1000000000, basis: Basis.measured),
    );
    final json = fit.toJson();
    expect(json['marginMB'], -250);
    expect(json['verdict'], 'doesNotFit');
    expect(MemoryFit.fromJson(json), fit);
  });

  /// The record the M1 ceiling was derived from must stay readable, whatever
  /// the report gains later: it predates `attempts`.
  group('committed M1 run', () {
    late ProbeReport report;
    setUpAll(() {
      report = ProbeReport.fromJsonString(Fixtures.m1Run1Json());
    });

    test('decodes with the Swift core\'s figures intact', () {
      expect(report.schemaVersion, 1);
      expect(report.device.identifier, 'MacBookPro17,1');
      expect(report.device.chip, 'Apple M1');
      expect(report.device.platform, HeadroomPlatform.macOS);
      expect(report.capturedAt, DateTime.utc(2026, 10, 3, 19, 50, 17));
      expect(report.ceilingGBps?.value, 56.33319137456001);
      expect(report.ceilingGBps?.basis, Basis.measured);
      expect(report.gpu?.triad.medianCI95GBps.low, 55.8748375568939);
      expect(report.gpu?.triad.medianCI95GBps.high, 57.936752123452266);
      expect(report.memory.availableBytes.basis, Basis.unknown);
      expect(report.warnings, isEmpty);
      final cpu = report.cpu!;
      expect(cpu.attempts, [CpuAttempt(threads: cpu.threads, triad: cpu.triad)]);
    });

    test('re-encodes to the same report', () {
      final text = report.toJsonString();
      expect(ProbeReport.fromJsonString(text), report);
      expect(text, contains('"capturedAt": "2026-10-03T19:50:17Z"'));
    });

    test('estimates as the Swift README describes for macOS', () {
      final estimate = report.estimate(
        ModelSpec.tinyLlama1_1BQ4_0,
        contextTokens: 128,
      );
      expect(estimate.bytesPerToken, 638873600);
      expect(estimate.peak.basis, const Basis.calibrated(devices: 1));
      expect(estimate.sustained, isNull);
      expect(estimate.fit.basis, Basis.unknown);
      // η = 38.860 / 56.000 over the run's CI of 55.87–57.94 GB/s.
      final eta = 38.860 / 56.000;
      expect(
        estimate.peak.low,
        closeTo(55.8748375568939 * eta * 1e9 / 638873600, 1e-9),
      );
      expect(
        estimate.peak.high,
        closeTo(57.936752123452266 * eta * 1e9 / 638873600, 1e-9),
      );
      expect(estimate.peak.low, inInclusiveRange(60, 62));
      expect(estimate.peak.high, inInclusiveRange(62, 64));
    });
  });
}
