/// The little statistics the probe needs, dependency-free and deterministic.
///
/// This is a line-for-line port of the Swift core's `Statistics.swift`,
/// including the exact way Swift's `Int.random(in:using:)` turns a 64-bit
/// draw into an index (Lemire's nearly divisionless method), so the same
/// samples give the same bootstrap interval here, in the Swift core and in
/// the Android plugin's Kotlin port.
abstract final class Statistics {
  /// The middle value, or the mean of the two middle values.
  static double median(List<double> values) {
    if (values.isEmpty) throw ArgumentError('median of nothing');
    final sorted = List<double>.of(values)..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isEven
        ? (sorted[middle - 1] + sorted[middle]) / 2
        : sorted[middle];
  }

  /// Percentile-bootstrap confidence interval of the median: resample with
  /// replacement, take each resample's median, and read off the central
  /// [confidence] share of them. Seeded, so the same samples give the same
  /// interval everywhere.
  static ({double low, double high}) bootstrapMedianInterval(
    List<double> values, {
    double confidence = 0.95,
    int resamples = 2000,
    int seed = 0x484541_44524F4F4D, // "HEADROOM"
  }) {
    if (values.isEmpty) throw ArgumentError('interval of nothing');
    if (!(confidence > 0 && confidence < 1)) {
      throw ArgumentError('confidence is a fraction');
    }
    if (values.length == 1) return (low: values[0], high: values[0]);

    final generator = SplitMix64(seed);
    final resample = List<double>.filled(values.length, 0);
    final medians = <double>[];
    for (var i = 0; i < resamples; i++) {
      for (var index = 0; index < resample.length; index++) {
        resample[index] = values[generator.nextIndex(values.length)];
      }
      medians.add(median(resample));
    }
    medians.sort();
    final lower = (resamples * (1 - confidence) / 2).toInt();
    final upper = (resamples * (1 + confidence) / 2).toInt();
    return (
      low: medians[lower],
      high: medians[upper < resamples - 1 ? upper : resamples - 1],
    );
  }
}

/// Vigna's SplitMix64: tiny, well mixed, and the same everywhere.
///
/// Arithmetic is on Dart's 64-bit integers, which wrap exactly like Swift's
/// `&+` and `&*`; hexadecimal literals above `2^63` are two's complement.
final class SplitMix64 {
  /// Starts the sequence at [seed].
  SplitMix64(int seed) : _state = seed;

  int _state;

  static const int _mask32 = 0xFFFFFFFF;

  /// The next 64-bit output, as the bit pattern of a Dart `int`.
  int next() {
    _state += 0x9E3779B97F4A7C15;
    var z = _state;
    z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9;
    z = (z ^ (z >>> 27)) * 0x94D049BB133111EB;
    return z ^ (z >>> 31);
  }

  /// A uniform index in `0 ..< upperBound`, exactly as Swift's
  /// `Int.random(in: 0..<upperBound, using:)` derives one on a 64-bit
  /// platform: the high word of the full-width product of one draw and the
  /// bound, rejecting the few draws that would bias the result.
  int nextIndex(int upperBound) {
    if (upperBound <= 0 || upperBound >= 0x80000000) {
      throw ArgumentError('upperBound must be in 1 ..< 2^31');
    }
    var product = _multiplyFullWidth(next(), upperBound);
    if (_unsignedLessThan(product.low, upperBound)) {
      // (2^64 - n) mod n, computed without overflowing: 2^64 ≡ 4 × (2^62 mod n).
      final threshold = ((1 << 62) % upperBound) * 4 % upperBound;
      while (_unsignedLessThan(product.low, threshold)) {
        product = _multiplyFullWidth(next(), upperBound);
      }
    }
    return product.high;
  }

  /// `random × n` as a 128-bit value, with `n < 2^31` so every partial
  /// product fits in a signed 64-bit integer.
  static ({int high, int low}) _multiplyFullWidth(int random, int n) {
    final lo = random & _mask32;
    final hi = random >>> 32;
    final p0 = lo * n;
    final p1 = hi * n;
    final mid = (p0 >>> 32) + (p1 & _mask32);
    final low = ((mid & _mask32) << 32) | (p0 & _mask32);
    final high = (p1 >>> 32) + (mid >>> 32);
    return (high: high, low: low);
  }

  /// `a < b` as unsigned 64-bit values, for a small non-negative [b].
  static bool _unsignedLessThan(int a, int b) => a >= 0 && a < b;
}
