import 'basis.dart';
import 'json_support.dart';
import 'model_spec.dart';
import 'quantity.dart';

/// Whether a model's working set fits; see [MemoryFit].
sealed class FitVerdict {
  const FitVerdict._();

  /// Headroom in decimal megabytes: positive is spare, negative is short.
  double get signedMarginMB;
}

/// Fits with room to spare.
final class FitsVerdict extends FitVerdict {
  /// Creates the verdict.
  const FitsVerdict({required this.marginMB}) : super._();

  /// Spare memory in decimal megabytes.
  final double marginMB;

  @override
  double get signedMarginMB => marginMB;

  @override
  bool operator ==(Object other) =>
      other is FitsVerdict && other.marginMB == marginMB;

  @override
  int get hashCode => Object.hash('fits', marginMB);

  @override
  String toString() => 'fits (${marginMB.toStringAsFixed(0)} MB spare)';
}

/// Fits, but the margin is inside the requirement's own uncertainty.
final class TightVerdict extends FitVerdict {
  /// Creates the verdict.
  const TightVerdict({required this.marginMB}) : super._();

  /// Spare memory in decimal megabytes.
  final double marginMB;

  @override
  double get signedMarginMB => marginMB;

  @override
  bool operator ==(Object other) =>
      other is TightVerdict && other.marginMB == marginMB;

  @override
  int get hashCode => Object.hash('tight', marginMB);

  @override
  String toString() => 'tight (${marginMB.toStringAsFixed(0)} MB spare)';
}

/// The working set exceeds the available memory.
final class DoesNotFitVerdict extends FitVerdict {
  /// Creates the verdict.
  const DoesNotFitVerdict({required this.shortfallMB}) : super._();

  /// Missing memory in decimal megabytes.
  final double shortfallMB;

  @override
  double get signedMarginMB => -shortfallMB;

  @override
  bool operator ==(Object other) =>
      other is DoesNotFitVerdict && other.shortfallMB == shortfallMB;

  @override
  int get hashCode => Object.hash('doesNotFit', shortfallMB);

  @override
  String toString() =>
      'does not fit (${shortfallMB.toStringAsFixed(0)} MB short)';
}

/// Whether a model's working set fits in the memory the OS will let this
/// process have.
///
/// `required = tensorBytes × 1.1 + kvBytes(context) + 150 MB`. The 1.1
/// ([weightOverheadFactor]) and 150 MB ([runtimeFixedBytes]) are stated
/// assumptions about llama.cpp-style runtimes, as is the rule that a margin
/// under 10% of the requirement ([tightMarginFraction]) is tight. The
/// verdict carries the basis of the available-memory figure.
final class MemoryFit {
  const MemoryFit._({
    required this.verdict,
    required this.requiredBytes,
    required this.availableBytes,
    required this.basis,
  });

  /// Compares [model] at [contextTokens] with [available] memory.
  factory MemoryFit.compute({
    required ModelSpec model,
    required int contextTokens,
    required Quantity<int> available,
  }) {
    final required = requiredBytesFor(
      model: model,
      contextTokens: contextTokens,
    );
    final availableBytes = available.value;
    final margin = availableBytes - required;
    final marginMB = margin / 1e6;
    final FitVerdict verdict;
    if (margin < 0) {
      verdict = DoesNotFitVerdict(shortfallMB: -marginMB);
    } else if (margin < required * tightMarginFraction) {
      verdict = TightVerdict(marginMB: marginMB);
    } else {
      verdict = FitsVerdict(marginMB: marginMB);
    }
    return MemoryFit._(
      verdict: verdict,
      requiredBytes: required,
      availableBytes: availableBytes,
      basis: available.basis,
    );
  }

  /// Decodes the Swift core's form: a verdict name and one signed margin.
  factory MemoryFit.fromJson(Map<String, Object?> json) {
    final marginMB = jsonDouble(json['marginMB']);
    final name = json['verdict'];
    final verdict = switch (name) {
      'fits' => FitsVerdict(marginMB: marginMB),
      'tight' => TightVerdict(marginMB: marginMB),
      'doesNotFit' => DoesNotFitVerdict(shortfallMB: -marginMB),
      _ => throw FormatException("unrecognised verdict '$name'"),
    };
    return MemoryFit._(
      verdict: verdict,
      requiredBytes: jsonInt(json['requiredBytes']),
      availableBytes: jsonInt(json['availableBytes']),
      basis: Basis.fromJson(jsonMap(json['basis'])),
    );
  }

  // The three constants below are stated assumptions about llama.cpp-style
  // runtimes, not measurements.

  /// Runtimes allocate a little over the weight bytes: alignment padding,
  /// dequantisation scratch, compute-graph buffers.
  static const double weightOverheadFactor = 1.1;

  /// Engine code, GPU pipelines, tokenizer tables. Decimal megabytes.
  static const int runtimeFixedBytes = 150000000;

  /// A margin smaller than this share of the requirement is within the slack
  /// the overhead factor itself represents.
  static const double tightMarginFraction = 0.1;

  /// Bytes [model] needs at [contextTokens] under the stated assumptions.
  static int requiredBytesFor({
    required ModelSpec model,
    required int contextTokens,
  }) =>
      (model.tensorBytes * weightOverheadFactor).round() +
      model.kvBytes(contextTokens: contextTokens) +
      runtimeFixedBytes;

  /// Fits, tight or does not fit, with the margin.
  final FitVerdict verdict;

  /// The requirement in bytes.
  final int requiredBytes;

  /// The available memory the requirement was compared with.
  final int availableBytes;

  /// The basis of [availableBytes], which the verdict inherits.
  final Basis basis;

  /// The object form the Swift core reads and writes: one signed margin,
  /// positive for headroom and negative for shortfall.
  Map<String, Object?> toJson() => {
    'availableBytes': availableBytes,
    'basis': basis.toJson(),
    'marginMB': verdict.signedMarginMB,
    'requiredBytes': requiredBytes,
    'verdict': switch (verdict) {
      FitsVerdict() => 'fits',
      TightVerdict() => 'tight',
      DoesNotFitVerdict() => 'doesNotFit',
    },
  };

  @override
  bool operator ==(Object other) =>
      other is MemoryFit &&
      other.verdict == verdict &&
      other.requiredBytes == requiredBytes &&
      other.availableBytes == availableBytes &&
      other.basis == basis;

  @override
  int get hashCode => Object.hash(verdict, requiredBytes, availableBytes, basis);

  @override
  String toString() => '$verdict, basis $basis';
}
