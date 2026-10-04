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
