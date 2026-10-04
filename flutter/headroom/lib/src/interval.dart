import 'basis.dart';
import 'json_support.dart';

/// A closed range `[low, high]` of a non-negative quantity, with its basis.
///
/// Predictions are intervals rather than points because their inputs are: a
/// measured ceiling has a confidence interval and the calibrated efficiency
/// spans several devices. [Interval.unknown] is `[0, ∞)`, the honest width
/// when nothing is known.
final class Interval {
  /// Creates `[low, high]`; throws [ArgumentError] unless `0 <= low <= high`.
  Interval({required this.low, required this.high, required this.basis}) {
    if (!(low >= 0 && high >= low)) {
      throw ArgumentError('an Interval needs 0 <= low <= high, got [$low, $high]');
    }
  }

  const Interval._unchecked({
    required this.low,
    required this.high,
    required this.basis,
  });

  /// The degenerate interval `[value, value]`.
  factory Interval.point(double value, {required Basis basis}) =>
      Interval(low: value, high: value, basis: basis);

  /// Decodes the Swift core's form, where an unbounded `high` is stored as
  /// `null` because JSON has no infinity.
  factory Interval.fromJson(Map<String, Object?> json) {
    final high = json['high'];
    return Interval(
      low: jsonDouble(json['low']),
      high: high == null ? double.infinity : jsonDouble(high),
      basis: Basis.fromJson(jsonMap(json['basis'])),
    );
  }

  /// `[0, ∞)` with basis [Basis.unknown].
  static const Interval unknown = Interval._unchecked(
    low: 0,
    high: double.infinity,
    basis: Basis.unknown,
  );

  /// Lower bound, inclusive.
  final double low;

  /// Upper bound, inclusive; infinite for [unknown].
  final double high;

  /// Where the bounds come from.
  final Basis basis;

  /// False for [unknown] and for anything derived from it.
  bool get isKnown => basis != Basis.unknown && high.isFinite;

  /// Product of two non-negative intervals; unknown if either is.
  Interval multipliedBy(Interval other) {
    if (!isKnown || !other.isKnown) return unknown;
    return Interval(
      low: low * other.low,
      high: high * other.high,
      basis: basis.combinedWith(other.basis),
    );
  }

  /// The interval scaled by a non-negative [factor].
  Interval scaledBy(double factor) {
    if (factor < 0) {
      throw ArgumentError('scaling by a negative factor would flip the bounds');
    }
    if (!isKnown) return unknown;
    return Interval(low: low * factor, high: high * factor, basis: basis);
  }

  /// The interval divided by a positive [divisor].
  Interval dividedBy(double divisor) {
    if (!(divisor > 0)) throw ArgumentError('division needs a positive divisor');
    if (!isKnown) return unknown;
    return Interval(low: low / divisor, high: high / divisor, basis: basis);
  }

  /// The object form the Swift core reads and writes (`high` is `null` when
  /// infinite).
  Map<String, Object?> toJson() => {
    'basis': basis.toJson(),
    'high': high.isFinite ? high : null,
    'low': low,
  };

  @override
  bool operator ==(Object other) =>
      other is Interval &&
      other.low == low &&
      other.high == high &&
      other.basis == basis;

  @override
  int get hashCode => Object.hash(low, high, basis);

  @override
  String toString() => isKnown ? '[$low, $high] ($basis)' : 'unknown';
}
