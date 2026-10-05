import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/headroom.dart';

import 'fixtures.dart';

/// The arithmetic PocketRoofline published, reproduced from its committed
/// decode figures, and the prediction formula built on top of it. Each test
/// is the Swift core's `EstimatorTests` with the same numbers.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(Calibration.load);

  test('A15 achieved bandwidth reproduces', () {
    final decode = Fixtures.mean(Fixtures.a15DecodeRepeats);
    expect((decode - 42.8012).abs(), lessThan(1e-9));
    final achieved = Calibration.achievedGBps(
      decodeTokPerSec: decode,
      bytesPerToken: Fixtures.tensorBytes,
    );
    expect((achieved - 27.2).abs(), lessThan(0.05));
    expect((achieved - 27.221).abs(), lessThan(0.001));
  });

  test('M1 achieved bandwidth reproduces', () {
    final decode = Fixtures.mean(Fixtures.m1DecodeRepeats);
    expect((decode - 61.1016).abs(), lessThan(1e-9));
    final achieved = Calibration.achievedGBps(
      decodeTokPerSec: decode,
      bytesPerToken: Fixtures.tensorBytes,
    );
    expect((achieved - 38.9).abs(), lessThan(0.05));
    expect((achieved - 38.860).abs(), lessThan(0.001));
  });

  test('A16 achieved bandwidth reproduces', () {
    final decode = Fixtures.mean(Fixtures.a16DecodeRates('SISO'));
    expect((decode - 65.1648).abs(), lessThan(0.5e-4));
    final achieved = Calibration.achievedGBps(
      decodeTokPerSec: decode,
      bytesPerToken: Fixtures.tensorBytes,
    );
    expect((achieved - 41.444).abs(), lessThan(0.5e-3));
  });

  group('the iPhone 15 Plus', () {
    // The calibration as it stood when the prediction was pre-registered:
    // the shipped rows without the A16's.
    Calibration before() {
      final shipped = Calibration.shipped!;
      return Calibration(
        bandwidth: [
          for (final row in shipped.bandwidth)
            if (row.soc != 'A16 Bionic') row,
        ],
        sustained: [
          for (final row in shipped.sustained)
            if (row.soc != 'A16 Bionic') row,
        ],
      );
    }

    // The probe the pre-registered rule selects: of the first three, the
    // one whose GPU triad median is the middle value.
    ProbeReport preRegisteredReport() {
      final firstThree = Fixtures.a16Probes().take(3).toList();
      final middle = Fixtures.ceilingGBps(firstThree);
      return firstThree.firstWhere(
        (report) => report.gpu!.triad.medianGBps.value == middle,
      );
    }

    double hundredths(double value) => (value * 100).round() / 100;

    /// Calibration/predictions/2026-10-05-iphone15plus-a16.md in the Swift
    /// core, reproduced from the committed records: the n = 1 prediction
    /// and the measured rates it missed.
    test('the pre-registered prediction reproduces, and missed', () {
      final report = preRegisteredReport();
      expect(report.capturedAt, DateTime.utc(2026, 10, 5, 1, 5, 33));
      expect(before().efficiency.basis, const Basis.calibrated(devices: 1));

      final peak = report
          .estimate(
            ModelSpec.tinyLlama1_1BQ4_0,
            contextTokens: 128,
            calibration: before(),
          )
          .peak;
      expect(hundredths(peak.low), 48.15);
      expect(hundredths(peak.high), 49.34);

      final measured = Fixtures.mean(Fixtures.a16DecodeRates('SISO'));
      expect(measured, greaterThan(peak.high));
      expect(((measured / peak.high - 1) * 1000).round() / 10, 32.1);

      final sustained = report
          .estimate(
            ModelSpec.tinyLlama1_1BQ4_0,
            contextTokens: 1024,
            calibration: before(),
          )
          .sustained!;
      expect(hundredths(sustained.low), 27.29);
      expect(hundredths(sustained.high), 34.57);
      expect(Fixtures.a16DecodeRates('SILO').last, lessThan(sustained.low));
    });

    /// Adding the A16 leaves every lower bound where the M1 alone put it and
    /// raises every upper bound by η(A16) / η(M1). On the A16's own probe the
    /// new estimate is in-sample.
    test('the A16 widens every interval by the efficiency ratio', () {
      final report = preRegisteredReport();
      final after = Calibration.shipped!;
      final ratio = after.efficiency.high / before().efficiency.high;
      expect(after.efficiency.low, before().efficiency.low);
      expect(ratio, inExclusiveRange(1.3, 1.35));

      for (final context in [0, 128, 1024, 2048]) {
        final old = report
            .estimate(
              ModelSpec.tinyLlama1_1BQ4_0,
              contextTokens: context,
              calibration: before(),
            )
            .peak;
        final updated = report
            .estimate(ModelSpec.tinyLlama1_1BQ4_0, contextTokens: context)
            .peak;
        expect(updated.low, old.low);
        expect((updated.high / old.high - ratio).abs(), lessThan(1e-12));
        expect(updated.basis, const Basis.calibrated(devices: 2));
      }
    });
  });

  test('KV cache bytes follow the formula', () {
    const model = ModelSpec.tinyLlama1_1BQ4_0;
    // 2 (K and V) × 22 layers × 4 KV heads × 64 head dim × 2 bytes (f16)
    expect(model.kv?.bytesPerToken, 22528);
    expect(model.kvBytes(contextTokens: 2048), 46137344);
    expect(model.bytesPerToken(contextTokens: 0), model.tensorBytes);
    expect(model.bytesPerToken(contextTokens: 256), 635990016 + 256 * 22528);
  });

  test('file-size-only models have no KV term', () {
    final model = ModelSpec.fromGgufBytes(
      name: '2.2 GB',
      ggufBytes: 2200000000,
    );
    expect(model.kv, isNull);
    expect(model.bytesPerToken(contextTokens: 4096), 2200000000);
  });

  /// With one calibrated device and a ceiling identical to the one it was
  /// calibrated on, the prediction must give back the decode rate it came
  /// from.
  test('peak reproduces the calibration decode rate', () {
    final decode = Fixtures.mean(Fixtures.m1DecodeRepeats);
    final calibration = Calibration(
      bandwidth: [
        Fixtures.bandwidthRow(soc: 'Apple M1', decode: decode, ceilingGBps: 60),
      ],
      sustained: const [],
    );
    final report = Fixtures.report(
      platform: HeadroomPlatform.macOS,
      triadGBps: const [60, 60, 60],
    );
    final estimate = report.estimate(
      ModelSpec.tinyLlama1_1BQ4_0,
      contextTokens: 0,
      calibration: calibration,
    );

    expect((estimate.peak.low - decode).abs(), lessThan(1e-6));
    expect((estimate.peak.high - decode).abs(), lessThan(1e-6));
    expect(estimate.peak.basis, const Basis.calibrated(devices: 1));
    expect((estimate.efficiency.low - 38.86 / 60).abs(), lessThan(0.001));
    expect(estimate.sustained, isNull, reason: 'no phone data applies to macOS');
  });

  test('peak interval spans ceiling CI and efficiency range', () {
    final calibration = Calibration(
      bandwidth: [
        Fixtures.bandwidthRow(soc: 'A', decode: 40, ceilingGBps: 50), // η = 0.5088
        Fixtures.bandwidthRow(soc: 'B', decode: 60, ceilingGBps: 60), // η = 0.6360
      ],
      sustained: [Fixtures.sustainedRow(soc: 'A', peak: 40, sustained: 30)],
    );
    final report = Fixtures.report(
      platform: HeadroomPlatform.iOS,
      triadGBps: const [50, 52, 54, 56, 58],
    );
    final estimate = report.estimate(
      ModelSpec.tinyLlama1_1BQ4_0,
      contextTokens: 0,
      calibration: calibration,
    );
    final ceiling = report.gpu!.triad.medianCI95GBps;

    const bytes = Fixtures.tensorBytes;
    expect(
      (estimate.peak.low - ceiling.low * estimate.efficiency.low * 1e9 / bytes)
          .abs(),
      lessThan(1e-6),
    );
    expect(
      (estimate.peak.high -
              ceiling.high * estimate.efficiency.high * 1e9 / bytes)
          .abs(),
      lessThan(1e-6),
    );
    expect(estimate.peak.low, lessThan(estimate.peak.high));
    expect(estimate.efficiency.basis, const Basis.calibrated(devices: 2));
    expect(
      estimate.sustainedFactor?.basis,
      const Basis.calibrated(devices: 1),
    );
    expect(estimate.sustained?.low, estimate.peak.low * 0.75);
    expect(estimate.sustained?.high, estimate.peak.high * 0.75);
    expect(estimate.peak.basis, const Basis.calibrated(devices: 2));
    expect(estimate.sustained?.basis, const Basis.calibrated(devices: 1));
  });

  test('no ceiling means unknown, not zero', () {
    final report = Fixtures.report(triadGBps: null);
    final estimate = report.estimate(
      ModelSpec.tinyLlama1_1BQ4_0,
      contextTokens: 512,
    );
    expect(estimate.peak, Interval.unknown);
    expect(estimate.peak.basis, Basis.unknown);
    expect(estimate.ceilingGBps, isNull);
    expect(
      estimate.sustained == null || estimate.sustained == Interval.unknown,
      isTrue,
    );
    expect(
      estimate.notes.any((note) => note.contains('GPU probe did not run')),
      isTrue,
    );
  });

  test('unverified ceiling cannot produce a measured-based prediction', () {
    final unverified = Fixtures.figure(gbps: const [60, 60, 60], verified: false);
    final gpu = GpuBandwidth(
      deviceName: 'x',
      arrayBytes: 128 << 20,
      copy: unverified,
      scale: unverified,
      add: unverified,
      triad: unverified,
    );
    final report = Fixtures.report(gpuOverride: gpu);
    expect(
      report
          .estimate(ModelSpec.tinyLlama1_1BQ4_0, contextTokens: 0)
          .peak
          .basis,
      Basis.unknown,
    );
  });

  test('basis combination is the weakest input', () {
    expect(Basis.measured.combinedWith(Basis.measured), Basis.measured);
    expect(
      Basis.measured.combinedWith(const Basis.calibrated(devices: 3)),
      const Basis.calibrated(devices: 3),
    );
    expect(
      const Basis.calibrated(
        devices: 1,
      ).combinedWith(const Basis.calibrated(devices: 2)),
      const Basis.calibrated(devices: 1),
    );
    expect(
      const Basis.calibrated(devices: 2).combinedWith(Basis.unknown),
      Basis.unknown,
    );
  });

  test('interval arithmetic', () {
    final a = Interval(low: 2, high: 4, basis: Basis.measured);
    final b = Interval(
      low: 0.5,
      high: 0.75,
      basis: const Basis.calibrated(devices: 2),
    );
    final product = a.multipliedBy(b);
    expect(product.low, 1);
    expect(product.high, 3);
    expect(product.basis, const Basis.calibrated(devices: 2));
    expect(a.dividedBy(2).high, 2);
    expect(a.multipliedBy(Interval.unknown), Interval.unknown);
    expect(Interval.unknown.dividedBy(7), Interval.unknown);
    expect(Interval.unknown.isKnown, isFalse);
    expect(() => Interval(low: 3, high: 2, basis: Basis.measured), throwsArgumentError);
    expect(() => a.scaledBy(-1), throwsArgumentError);
    expect(() => a.dividedBy(0), throwsArgumentError);
  });

  group('Android', () {
    test('predictions are unknown and say there is no calibration yet', () {
      final report = Fixtures.report(
        platform: HeadroomPlatform.android,
        triadGBps: null,
      );
      final estimate = report.estimate(
        ModelSpec.tinyLlama1_1BQ4_0,
        contextTokens: 1024,
      );
      expect(estimate.efficiency, Interval.unknown);
      expect(estimate.peak, Interval.unknown);
      expect(estimate.sustained, isNull);
      expect(
        estimate.notes.any((note) => note.contains('no Android calibration yet')),
        isTrue,
      );
      expect(estimate.fit.basis, Basis.measured);
    });

    test('the Apple efficiency is never applied, even with a ceiling', () {
      // A report that somehow carried a GPU section on Android must still
      // not borrow η from the Apple rows.
      final report = Fixtures.report(
        platform: HeadroomPlatform.androidEmulator,
        triadGBps: const [60, 60, 60],
      );
      final estimate = report.estimate(
        ModelSpec.tinyLlama1_1BQ4_0,
        contextTokens: 0,
      );
      expect(estimate.efficiency, Interval.unknown);
      expect(estimate.peak, Interval.unknown);
    });
  });

  test('negative context is rejected', () {
    expect(
      () => Fixtures.report().estimate(
        ModelSpec.tinyLlama1_1BQ4_0,
        contextTokens: -1,
      ),
      throwsArgumentError,
    );
  });
}
