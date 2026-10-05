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
      'A16 Bionic',
    ]);
    expect([for (final row in shipped.sustained) row.soc], [
      'A15 Bionic',
      'A18 Pro',
      'A16 Bionic',
    ]);
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

    // The A16 row is the PocketRoofline app's capture; its repeats are full
    // doubles, so the row stores the mean to four decimals and the bandwidth
    // to three.
    final a16 = shipped.bandwidth.firstWhere((row) => row.soc == 'A16 Bionic');
    final decode = Fixtures.mean(Fixtures.a16DecodeRates('SISO'));
    expect((a16.decodeTokPerSec - decode).abs(), lessThan(0.5e-4));
    final achieved = Calibration.achievedGBps(
      decodeTokPerSec: decode,
      bytesPerToken: Fixtures.tensorBytes,
    );
    expect((a16.achievedGBps - achieved).abs(), lessThan(0.5e-3));
  });

  /// n = 2: the M1 and the A16 are the devices with a measured ceiling, and
  /// η spans exactly their two values, the M1's at the bottom and the A16's
  /// at the top.
  test('efficiency spans the M1 and the A16', () {
    final probed = [
      for (final row in shipped.bandwidth)
        if (row.ceilingGBps != null) row,
    ];
    expect([for (final row in probed) row.soc], ['Apple M1', 'A16 Bionic']);
    final m1 = probed.firstWhere((row) => row.soc == 'Apple M1');
    final a16 = probed.firstWhere((row) => row.soc == 'A16 Bionic');

    final a16Probes = Fixtures.a16Probes();
    expect(a16Probes.length, 4);
    final a16Ceiling = Fixtures.ceilingGBps(a16Probes);
    expect((a16.ceilingGBps! - a16Ceiling).abs(), lessThan(0.5e-3));

    expect(m1.efficiency!, lessThan(a16.efficiency!));
    expect(
      shipped.efficiency,
      Interval(
        low: m1.efficiency!,
        high: a16.efficiency!,
        basis: const Basis.calibrated(devices: 2),
      ),
    );

    // The A16's η recomputed from the records alone.
    final a16FromRecords =
        Calibration.achievedGBps(
          decodeTokPerSec: Fixtures.mean(Fixtures.a16DecodeRates('SISO')),
          bytesPerToken: Fixtures.tensorBytes,
        ) /
        a16Ceiling;
    expect((a16.efficiency! - a16FromRecords).abs(), lessThan(1e-4));
    // The figures the Swift core's Calibration/README.md quotes.
    expect((m1.efficiency! - 0.6939).abs(), lessThan(0.0001));
    expect((a16.efficiency! - 0.9145).abs(), lessThan(0.0001));
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

    // The A16's from its record: the last SILO repeat over the SISO mean.
    final a16 = shipped.sustained.firstWhere((row) => row.soc == 'A16 Bionic');
    final lastSilo = Fixtures.a16DecodeRates('SILO').last;
    final sisoMean = Fixtures.mean(Fixtures.a16DecodeRates('SISO'));
    expect(
      a16.peakTokPerSec,
      shipped.bandwidth
          .firstWhere((row) => row.soc == 'A16 Bionic')
          .decodeTokPerSec,
    );
    expect((a16.sustainedTokPerSec - lastSilo).abs(), lessThan(0.5e-4));
    expect((a16.factor - lastSilo / sisoMean).abs(), lessThan(1e-5));
    expect((a16.factor - 0.4169).abs(), lessThan(0.0001));

    // Three phones; the A16 is the lowest factor and widens the range.
    final factor = shipped.sustainedFactor(HeadroomPlatform.iOS)!;
    expect(factor.low, a16.factor);
    expect(factor.high, a15.factor);
    expect(factor.basis, const Basis.calibrated(devices: 3));
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
