import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/headroom.dart';
import 'package:integration_test/integration_test.dart';

/// Runs the real probe on the device or simulator the test is launched on.
///
/// Magnitude checks only: a phone or an Apple silicon host lands in the tens
/// of GB/s, and anything outside 5–200 GB/s means the kernels or the byte
/// accounting are wrong. The full report is printed so the numbers can be
/// read off the run. Simulator and emulator figures are the host's.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the probe runs end to end', (tester) async {
    final report = await Headroom.probe();
    // ignore: avoid_print
    print('HEADROOM REPORT\n${report.toJsonString()}');

    expect(report.schemaVersion, 1);
    expect(report.headroomVersion, isNotEmpty);
    expect(report.durationSeconds, greaterThan(0));
    expect(report.memory.physicalBytes, greaterThan(0));
    expect(report.device.identifier, isNotEmpty);
    expect(report.device.osVersion, isNotEmpty);
    expect(report.device.osBuild, isNotEmpty);
    expect(report.device.logicalCPUs, greaterThanOrEqualTo(1));

    final platform = report.device.platform;
    final figures = <BandwidthFigure>[];
    if (platform.isApple && platform.isSimulator) {
      // The simulator's command-buffer timestamps do not bracket GPU work, so
      // the core skips the GPU probe there instead of reporting nonsense.
      expect(report.gpu, isNull);
      expect(report.warnings.any((w) => w.contains('GPU probe skipped')), isTrue);
      expect(report.warnings.any((w) => w.contains('Simulator')), isTrue);
      expect(report.memory.availableBytes.basis, Basis.unknown);
    } else if (platform.isApple) {
      final gpu = report.gpu;
      expect(gpu, isNotNull, reason: report.warnings.join('; '));
      for (final figure in gpu!.figures) {
        expect(figure.verified, isTrue, reason: '${figure.kernel.name} output');
        expect(figure.iterationSeconds.length, 10);
        expect(figure.medianGBps.basis, Basis.measured);
        expect(
          figure.medianGBps.value,
          inInclusiveRange(5, 200),
          reason: '${figure.kernel.name}: ${figure.medianGBps.value} GB/s',
        );
        expect(figure.medianCI95GBps.low, lessThanOrEqualTo(figure.medianGBps.value));
        expect(figure.medianGBps.value, lessThanOrEqualTo(figure.medianCI95GBps.high));
        expect(figure.bestGBps.value, greaterThanOrEqualTo(figure.medianGBps.value));
      }
      expect(gpu.triad.bytesPerIteration, 3 * (128 << 20));
      expect(report.ceilingGBps, gpu.triad.medianGBps);
      figures.addAll(gpu.figures);
      expect(report.memory.availableBytes.basis, Basis.measured);
    } else {
      expect(report.gpu, isNull);
      expect(report.warnings.any((w) => w.contains('GPU probe')), isTrue);
      expect(report.memory.availableBytes.basis, Basis.measured);
      expect(report.memory.lowMemory, isNotNull);
      expect(report.memory.lowMemoryThresholdBytes, isNotNull);
      expect(report.conditions.platformThermalStatus, isNotNull);
      expect(report.device.chip, isNotNull);
      if (platform.isSimulator) {
        expect(report.warnings.any((w) => w.contains('Emulator')), isTrue);
      }
    }

    final cpu = report.cpu;
    expect(cpu, isNotNull, reason: report.warnings.join('; '));
    expect(cpu!.triad.verified, isTrue);
    expect(cpu.threads, greaterThanOrEqualTo(1));
    expect(cpu.triad.iterationSeconds.length, 7);
    expect(cpu.triad.bytesPerIteration, 3 * (64 << 20));
    expect(cpu.attempts, isNotEmpty);
    expect(
      cpu.attempts.any((a) => a.threads == cpu.threads && a.triad == cpu.triad),
      isTrue,
    );
    for (final attempt in cpu.attempts) {
      expect(attempt.triad.verified, isTrue);
      expect(
        attempt.triad.medianGBps.value,
        lessThanOrEqualTo(cpu.triad.medianGBps.value),
      );
    }
    expect(
      cpu.triad.medianGBps.basis,
      cpu.compiledWithOptimisation ? Basis.measured : Basis.unknown,
    );
    if (cpu.compiledWithOptimisation) {
      expect(cpu.triad.medianGBps.value, inInclusiveRange(5, 200));
    }
    figures.add(cpu.triad);
    figures.addAll([for (final attempt in cpu.attempts) attempt.triad]);

    // Cross-language statistics: every figure recomputed in Dart from the raw
    // iteration times must equal what the native side (Swift or Kotlin)
    // computed, double for double.
    for (final figure in figures) {
      final recomputed = BandwidthFigure.fromIterations(
        kernel: figure.kernel,
        bytesPerIteration: figure.bytesPerIteration,
        iterationSeconds: figure.iterationSeconds,
        verified: figure.verified,
        basis: figure.medianGBps.basis,
      );
      expect(recomputed, figure, reason: '${figure.kernel.name} statistics');
    }

    final estimate = report.estimate(
      ModelSpec.tinyLlama1_1BQ4_0,
      contextTokens: 1024,
    );
    // ignore: avoid_print
    print(
      'HEADROOM ESTIMATE TinyLlama-1.1B Q4_0 @1024: peak ${estimate.peak}, '
      'sustained ${estimate.sustained}, fit ${estimate.fit}, '
      'notes ${estimate.notes}',
    );
    if (platform.isApple && platform.isSimulator) {
      // No GPU ceiling in the simulator, so there is nothing to predict from.
      expect(estimate.peak, Interval.unknown);
      expect(estimate.sustained?.isKnown ?? false, isFalse);
    } else if (platform.isApple) {
      expect(estimate.peak.isKnown, isTrue);
      // η spans two devices (the M1 and the A16).
      expect(estimate.efficiency.basis, const Basis.calibrated(devices: 2));
      expect(estimate.peak.basis, const Basis.calibrated(devices: 2));
      expect(estimate.peak.low, greaterThan(0));
      expect(estimate.peak.low, lessThanOrEqualTo(estimate.peak.high));
      if (platform == HeadroomPlatform.iOS) {
        // The sustained factor spans three phones; the product with the peak
        // takes the smaller count, η's two.
        expect(estimate.sustainedFactor?.basis, const Basis.calibrated(devices: 3));
        expect(estimate.sustained?.basis, const Basis.calibrated(devices: 2));
      } else {
        expect(estimate.sustained, isNull);
      }
    } else {
      expect(estimate.peak, Interval.unknown);
      expect(estimate.efficiency, Interval.unknown);
      expect(estimate.sustained, isNull);
      expect(
        estimate.notes.any((n) => n.contains('no Android calibration yet')),
        isTrue,
      );
    }
    expect(estimate.fit.requiredBytes, greaterThan(0));
  });

  testWidgets('a probe can be cancelled and the next one still runs', (
    tester,
  ) async {
    final pending = Headroom.probe();
    // Listen before cancelling, or the error lands with nobody waiting.
    final outcome = expectLater(pending, throwsA(isA<ProbeCancelledException>()));
    await Headroom.cancel();
    await outcome;
    expect(Headroom.isProbing, isFalse);

    final report = await Headroom.probe(
      options: const ProbeOptions(runsGPUProbe: false, cpuTimedIterations: 2),
    );
    expect(report.gpu, isNull);
    expect(report.cpu?.triad.iterationSeconds.length, 2);
  });
}
