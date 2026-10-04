import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/headroom.dart';

import 'fixtures.dart';

/// The Swift core's `StreamAccountingTests`.
void main() {
  test('kernels touch the right number of arrays', () {
    const arrayBytes = 128 << 20;
    expect(StreamKernel.copy.bytesPerIteration(arrayBytes), 2 * arrayBytes);
    expect(StreamKernel.scale.bytesPerIteration(arrayBytes), 2 * arrayBytes);
    expect(StreamKernel.add.bytesPerIteration(arrayBytes), 3 * arrayBytes);
    expect(StreamKernel.triad.bytesPerIteration(arrayBytes), 3 * arrayBytes);
  });

  test('gigabytes per second are decimal', () {
    // 3 × 128 MiB in 6.7 ms is just over 60 GB/s.
    final bytes = StreamKernel.triad.bytesPerIteration(128 << 20);
    final rate = BandwidthFigure.gigabytesPerSecond(bytes: bytes, seconds: 0.0067);
    expect((rate - 60.097).abs(), lessThan(0.001));
  });

  test('figure summarises iterations', () {
    final figure = Fixtures.figure(gbps: const [58, 61, 59, 60, 62]);
    expect((figure.bestGBps.value - 62).abs(), lessThan(1e-9));
    expect((figure.medianGBps.value - 60).abs(), lessThan(1e-9));
    expect(figure.medianCI95GBps.low, lessThanOrEqualTo(60));
    expect(figure.medianCI95GBps.high, greaterThanOrEqualTo(60));
    expect(figure.medianGBps.basis, Basis.measured);
    expect(figure.iterationGBps.length, 5);
  });

  test('unverified figure is not measured', () {
    final figure = Fixtures.figure(gbps: const [60, 60], verified: false);
    expect(figure.medianGBps.basis, Basis.unknown);
    expect(figure.medianCI95GBps.basis, Basis.unknown);
  });

  test('GPU array sizes must be whole threadgroups', () {
    const base = ProbeOptions();
    expect(() => base.validate(), returnsNormally);
    expect(() => base.copyWith(gpuArrayBytes: 4096).validate(), returnsNormally);
    expect(
      () => base.copyWith(gpuArrayBytes: 4096 + 16).validate(),
      throwsArgumentError,
    );
    expect(() => base.copyWith(gpuArrayBytes: 0).validate(), throwsArgumentError);
  });

  test('CPU array sizes must be whole floats', () {
    const base = ProbeOptions();
    expect(
      () => base.copyWith(cpuArrayBytes: 4 << 20).validate(),
      returnsNormally,
    );
    expect(
      () => base.copyWith(cpuArrayBytes: (4 << 20) + 2).validate(),
      throwsArgumentError,
    );
    expect(
      () => base.copyWith(cpuTimedIterations: 0).validate(),
      throwsArgumentError,
    );
    expect(() => base.copyWith(cpuThreads: -1).validate(), throwsArgumentError);
  });

  /// The CPU figure is the best thread count's; an unverified run never wins
  /// over a verified one however fast it claims to be.
  test('best CPU attempt is the highest verified median', () {
    final slow = CpuAttempt(
      threads: 8,
      triad: Fixtures.figure(arrayBytes: 64 << 20, gbps: const [44, 45, 46]),
    );
    final fast = CpuAttempt(
      threads: 4,
      triad: Fixtures.figure(arrayBytes: 64 << 20, gbps: const [51, 52, 53]),
    );
    final wrong = CpuAttempt(
      threads: 2,
      triad: Fixtures.figure(
        arrayBytes: 64 << 20,
        gbps: const [90, 90, 90],
        verified: false,
      ),
    );
    expect(CpuBandwidth.bestOf([slow, fast, wrong]).threads, 4);
    expect(CpuBandwidth.bestOf([wrong]).triad.medianGBps.basis, Basis.unknown);
    expect(() => CpuBandwidth.bestOf([]), throwsArgumentError);
  });
}
