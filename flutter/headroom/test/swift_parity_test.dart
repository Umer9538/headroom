import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/headroom.dart';

import 'fixtures.dart';

/// The Dart statistics must reproduce the Swift core's figures bit for bit:
/// the committed M1 run holds every kernel's raw iteration times next to the
/// best, median and bootstrap interval Swift computed from them. Recomputing
/// those here from the same inputs and getting the same doubles proves the
/// median, the SplitMix64 stream and the index derivation match.
void main() {
  late ProbeReport report;
  setUpAll(() {
    report = ProbeReport.fromJsonString(Fixtures.m1Run1Json());
  });

  test('every GPU figure recomputes to the Swift values', () {
    final gpu = report.gpu!;
    for (final figure in gpu.figures) {
      final recomputed = BandwidthFigure.fromIterations(
        kernel: figure.kernel,
        bytesPerIteration: figure.bytesPerIteration,
        iterationSeconds: figure.iterationSeconds,
        verified: figure.verified,
        basis: figure.medianGBps.basis,
      );
      expect(recomputed.bestGBps, figure.bestGBps, reason: figure.kernel.name);
      expect(recomputed.medianGBps, figure.medianGBps, reason: figure.kernel.name);
      expect(
        recomputed.medianCI95GBps,
        figure.medianCI95GBps,
        reason: '${figure.kernel.name} bootstrap interval',
      );
      expect(recomputed, figure);
    }
  });

  test('the CPU figure recomputes to the Swift values', () {
    final figure = report.cpu!.triad;
    final recomputed = BandwidthFigure.fromIterations(
      kernel: StreamKernel.triad,
      bytesPerIteration: figure.bytesPerIteration,
      iterationSeconds: figure.iterationSeconds,
      verified: true,
      basis: Basis.measured,
    );
    expect(recomputed, figure);
    expect(recomputed.medianCI95GBps.low, 43.66421006660162);
    expect(recomputed.medianCI95GBps.high, 45.00636064006006);
  });
}
