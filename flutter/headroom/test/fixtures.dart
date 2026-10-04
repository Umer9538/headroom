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
