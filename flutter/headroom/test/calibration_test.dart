import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/headroom.dart';

import 'fixtures.dart';

/// The Swift core's `CalibrationTests`, run against the shipped asset.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Calibration shipped;
  setUpAll(() async {
    shipped = await Calibration.load();
  });

  test('shipped calibration loads from the package asset', () {
    expect(shipped.schemaVersion, 1);
    expect([for (final row in shipped.bandwidth) row.soc], [
      'A15 Bionic',
      'Apple M1',
    ]);
    expect(shipped.sustained.length, 2);
    expect(Calibration.shipped, same(shipped));
  });

  /// The stored achievedGBps is a convenience; the inputs are the record.
  test('stored achieved bandwidth agrees with its inputs', () {
    for (final row in shipped.bandwidth) {
      expect(
        (row.achievedGBps - row.recomputedAchievedGBps).abs(),
        lessThan(0.001),
        reason: row.soc,
      );
      expect(row.tensorBytes, ModelSpec.tinyLlama1_1BQ4_0.tensorBytes);
    }
  });

  test('shipped rows match PocketRoofline', () {
    final a15 = shipped.bandwidth.firstWhere((row) => row.soc == 'A15 Bionic');
    final m1 = shipped.bandwidth.firstWhere((row) => row.soc == 'Apple M1');
    expect(
      (a15.decodeTokPerSec - Fixtures.mean(Fixtures.a15DecodeRepeats)).abs(),
      lessThan(1e-9),
    );
    expect(
      (m1.decodeTokPerSec - Fixtures.mean(Fixtures.m1DecodeRepeats)).abs(),
      lessThan(1e-9),
    );
    expect((a15.achievedGBps - 27.221).abs(), lessThan(0.001));
    expect((m1.achievedGBps - 38.860).abs(), lessThan(0.001));
  });

  /// The A15 stays null until the owner runs the demo on the iPhone 13.
  test('null ceiling rows are excluded from efficiency', () {
    final a15 = shipped.bandwidth.firstWhere((row) => row.soc == 'A15 Bionic');
    expect(a15.ceilingGBps, isNull);
    expect(a15.efficiency, isNull);

    final probed = [
      for (final row in shipped.bandwidth)
        if (row.ceilingGBps != null) row,
    ];
    if (probed.isEmpty) {
      expect(shipped.efficiency, Interval.unknown);
    } else {
      expect(
        shipped.efficiency.basis,
        Basis.calibrated(devices: probed.length),
      );
      for (final row in probed) {
        final efficiency = row.efficiency!;
        expect(
          efficiency > 0 && efficiency < 1,
          isTrue,
          reason: 'decode cannot exceed the ceiling on ${row.soc}',
        );
        expect(shipped.efficiency.low, lessThanOrEqualTo(efficiency));
        expect(efficiency, lessThanOrEqualTo(shipped.efficiency.high));
      }
    }
  });

  test('efficiency is unknown without any probed device', () {
    final calibration = Calibration(
      bandwidth: [
        Fixtures.bandwidthRow(soc: 'A', decode: 40, ceilingGBps: null),
      ],
      sustained: const [],
    );
    expect(calibration.efficiency, Interval.unknown);
    expect(calibration.sustainedFactor(HeadroomPlatform.iOS), isNull);
  });

  test('sustained factors are computed from the rows', () {
    final a15 = shipped.sustained.firstWhere((row) => row.soc == 'A15 Bionic');
    final a18 = shipped.sustained.firstWhere((row) => row.soc == 'A18 Pro');
    expect((a15.factor - 30.933 / 42.8012).abs(), lessThan(1e-9));
    expect((a15.factor - 0.7227).abs(), lessThan(0.0001));
    expect((a18.factor - 23.67 / 40.49).abs(), lessThan(1e-9));
    expect((a18.factor - 0.5846).abs(), lessThan(0.0001));

    final factor = shipped.sustainedFactor(HeadroomPlatform.iOS)!;
    expect((factor.low - 0.5846).abs(), lessThan(0.0001));
    expect((factor.high - 0.7227).abs(), lessThan(0.0001));
    expect(factor.basis, const Basis.calibrated(devices: 2));
    expect(shipped.sustainedFactor(HeadroomPlatform.macOS), isNull);
    expect(shipped.sustainedFactor(HeadroomPlatform.iOSSimulator), isNull);
  });

  test('the Apple efficiency is not offered to Android', () {
    expect(shipped.efficiencyFor(HeadroomPlatform.iOS).isKnown, isTrue);
    expect(shipped.efficiencyFor(HeadroomPlatform.macOS).isKnown, isTrue);
    expect(shipped.efficiencyFor(HeadroomPlatform.android), Interval.unknown);
    expect(
      shipped.efficiencyFor(HeadroomPlatform.androidEmulator),
      Interval.unknown,
    );
    expect(shipped.sustainedFactor(HeadroomPlatform.android), isNull);
  });

  test('rows round-trip through JSON', () {
    final decoded = Calibration.fromJson(shipped.toJson());
    expect(decoded.efficiency, shipped.efficiency);
    expect(
      decoded.sustainedFactor(HeadroomPlatform.iOS),
      shipped.sustainedFactor(HeadroomPlatform.iOS),
    );
    expect(decoded.bandwidth.last.ceilingSource, isNotNull);
    expect(decoded.sustained.first.protocolNote, isNotEmpty);
  });
}
