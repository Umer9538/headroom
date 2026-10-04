import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/headroom.dart';

import 'fixtures.dart';

/// The Swift core's `MemoryFitTests`, same numbers.
void main() {
  /// 1.0 GB of weights, no KV geometry: required = 1.1 GB + 150 MB = 1.25 GB.
  final model = ModelSpec.fromGgufBytes(name: '1 GB', ggufBytes: 1000000000);

  test('requirement follows the stated assumptions', () {
    expect(
      MemoryFit.requiredBytesFor(model: model, contextTokens: 4096),
      1250000000,
    );
    const tinyLlama = ModelSpec.tinyLlama1_1BQ4_0;
    final expected = (635990016.0 * 1.1).round() + 1024 * 22528 + 150000000;
    expect(
      MemoryFit.requiredBytesFor(model: tinyLlama, contextTokens: 1024),
      expected,
    );
  });

  test('fits with room', () {
    final fit = MemoryFit.compute(
      model: model,
      contextTokens: 0,
      available: const Quantity(2000000000, basis: Basis.measured),
    );
    expect(fit.verdict, const FitsVerdict(marginMB: 750));
    expect(fit.basis, Basis.measured);
  });

  test('tight when the margin is inside the slack', () {
    // Margin 50 MB is under 10% of the 1.25 GB requirement.
    final fit = MemoryFit.compute(
      model: model,
      contextTokens: 0,
      available: const Quantity(1300000000, basis: Basis.measured),
    );
    expect(fit.verdict, const TightVerdict(marginMB: 50));
  });

  test('does not fit reports the shortfall', () {
    final fit = MemoryFit.compute(
      model: model,
      contextTokens: 0,
      available: const Quantity(1000000000, basis: Basis.measured),
    );
    expect(fit.verdict, const DoesNotFitVerdict(shortfallMB: 250));
    expect(fit.verdict.signedMarginMB, -250);
  });

  test('verdict inherits the basis of available memory', () {
    final fit = MemoryFit.compute(
      model: model,
      contextTokens: 0,
      available: const Quantity(8000000000, basis: Basis.unknown),
    );
    expect(fit.basis, Basis.unknown);
    final report = Fixtures.report(
      availableBytes: const Quantity(8000000000, basis: Basis.unknown),
    );
    final estimate = report.estimate(
      model,
      contextTokens: 0,
      calibration: const Calibration(bandwidth: [], sustained: []),
    );
    expect(estimate.fit.basis, Basis.unknown);
    expect(
      estimate.notes.any(
        (note) => note.contains('Available memory is a fallback'),
      ),
      isTrue,
    );
  });
}
