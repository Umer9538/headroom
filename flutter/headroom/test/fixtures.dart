import 'dart:convert';
import 'dart:io';

import 'package:headroom/headroom.dart';

/// Hand-built reports and calibrations, so estimator tests do not need a
/// GPU. The numbers are the Swift core's `Tests/HeadroomTests/Fixtures.swift`.
abstract final class Fixtures {
  static const int tensorBytes = 635990016;

  /// The committed SISO decode repeats from PocketRoofline `results/`.
  static const List<double> a15DecodeRepeats = [
    42.597,
    42.439,
    42.575,
    43.202,
    43.193,
  ];
  static const List<double> m1DecodeRepeats = [
    59.729,
    62.786,
    59.816,
    60.7,
    62.477,
  ];

  static double mean(List<double> values) =>
      values.fold(0.0, (sum, value) => sum + value) / values.length;

  /// The real M1 run the Swift core committed to `Calibration/runs/`.
  static String m1Run1Json() =>
      File('test/fixtures/m1-run1.json').readAsStringSync();

  /// The PocketRoofline app capture on the iPhone 15 Plus that the A16
  /// decode and sustained rows come from, copied unchanged from the Swift
  /// core's `Calibration/runs/a16/`.
  static Map<String, Object?> a16Capture() => jsonDecode(
    File('test/fixtures/a16-pocketroofline-1791162656.json').readAsStringSync(),
  ) as Map<String, Object?>;

  /// Decode rates of every repeat of [label] (SISO, LISO, SILO) in the A16
  /// capture, in run order.
  static List<double> a16DecodeRates(String label) {
    final regimes = (a16Capture()['regimes']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final regime = regimes.firstWhere((regime) => regime['label'] == label);
    return [
      for (final repeat
          in (regime['repeats']! as List<Object?>).cast<Map<String, Object?>>())
        (repeat['decodeTokensPerSec']! as num).toDouble(),
    ];
  }

  /// The four Headroom demo probes on the same iPhone that the A16 ceiling
  /// comes from, copied unchanged from `Calibration/runs/a16/`, in capture
  /// order.
  static List<ProbeReport> a16Probes() {
    final files =
        Directory('test/fixtures')
            .listSync()
            .whereType<File>()
            .where(
              (file) => file.uri.pathSegments.last.startsWith('a16-probe-'),
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    return [
      for (final file in files)
        ProbeReport.fromJsonString(file.readAsStringSync()),
    ];
  }

  /// The median of the reports' GPU triad medians: how a ceiling row is
  /// derived.
  static double ceilingGBps(List<ProbeReport> reports) => Statistics.median([
    for (final report in reports) report.gpu!.triad.medianGBps.value,
  ]);

  static BandwidthFigure figure({
    StreamKernel kernel = StreamKernel.triad,
    int arrayBytes = 128 << 20,
    required List<double> gbps,
    bool verified = true,
  }) {
    final bytes = kernel.bytesPerIteration(arrayBytes);
    return BandwidthFigure.fromIterations(
      kernel: kernel,
      bytesPerIteration: bytes,
      iterationSeconds: [for (final rate in gbps) bytes / (rate * 1e9)],
      verified: verified,
      basis: verified ? Basis.measured : Basis.unknown,
    );
  }

  static GpuBandwidth gpu({required List<double> triadGBps}) => GpuBandwidth(
    deviceName: 'Fixture GPU',
    arrayBytes: 128 << 20,
    copy: figure(kernel: StreamKernel.copy, gbps: triadGBps),
    scale: figure(kernel: StreamKernel.scale, gbps: triadGBps),
    add: figure(kernel: StreamKernel.add, gbps: triadGBps),
    triad: figure(kernel: StreamKernel.triad, gbps: triadGBps),
  );

  static CpuBandwidth cpu({
    int threads = 6,
    List<double> gbps = const [30, 31, 32],
  }) {
    final triad = figure(arrayBytes: 64 << 20, gbps: gbps);
    return CpuBandwidth(
      threads: threads,
      arrayBytes: 64 << 20,
      compiledWithOptimisation: true,
      triad: triad,
      attempts: [CpuAttempt(threads: threads, triad: triad)],
    );
  }

  static ProbeReport report({
    HeadroomPlatform platform = HeadroomPlatform.iOS,
    DateTime? capturedAt,
    List<double>? triadGBps = const [60, 60, 60],
    Quantity<int> availableBytes = const Quantity(
      2000000000,
      basis: Basis.measured,
    ),
    GpuBandwidth? gpuOverride,
  }) => ProbeReport(
    schemaVersion: 1,
    headroomVersion: '0.1.0',
    capturedAt:
        capturedAt ??
        DateTime.fromMillisecondsSinceEpoch(1790000000 * 1000, isUtc: true),
    durationSeconds: 1.25,
    device: DeviceInfo(
      identifier: 'iPhone14,5',
      chip: null,
      platform: platform,
      osVersion: '26.6.1',
      osBuild: '23G83',
      logicalCPUs: 6,
    ),
    conditions: const Conditions(
      thermalState: ThermalState.fair,
      isLowPowerModeEnabled: false,
      powerSource: PowerSource.battery,
      batteryLevel: 0.5,
    ),
    memory: MemoryInfo(
      physicalBytes: 4000000000,
      availableBytes: availableBytes,
    ),
    gpu: gpuOverride ?? (triadGBps == null ? null : gpu(triadGBps: triadGBps)),
    cpu: cpu(),
    warnings: const [],
  );

  static BandwidthRow bandwidthRow({
    required String soc,
    required double decode,
    required double? ceilingGBps,
  }) => BandwidthRow(
    soc: soc,
    device: soc,
    decodeTokPerSec: decode,
    tensorBytes: tensorBytes,
    achievedGBps: Calibration.achievedGBps(
      decodeTokPerSec: decode,
      bytesPerToken: tensorBytes,
    ),
    ceilingGBps: ceilingGBps,
    source: 'fixture',
    ceilingSource: ceilingGBps == null ? null : 'fixture',
  );

  static SustainedRow sustainedRow({
    required String soc,
    HeadroomPlatform platform = HeadroomPlatform.iOS,
    required double peak,
    required double sustained,
  }) => SustainedRow(
    soc: soc,
    platform: platform,
    runtime: 'fixture',
    peakTokPerSec: peak,
    sustainedTokPerSec: sustained,
    protocolNote: 'fixture',
    source: 'fixture',
  );
}
