import 'interval.dart';
import 'json_support.dart';
import 'memory_fit.dart';
import 'model_spec.dart';

/// What a model of a given size should do on the probed device.
///
/// Built by `ProbeReport.estimate`. Every field carries its basis: the
/// measured ceiling's interval is measured, the efficiency and sustained
/// factor are calibrated, and their products take the weaker basis, so no
/// prediction can ever carry `measured`.
final class Estimate {
  /// Creates an estimate from its parts.
  const Estimate({
    required this.model,
    required this.contextTokens,
    required this.bytesPerToken,
    required this.ceilingGBps,
    required this.efficiency,
    required this.peak,
    required this.sustainedFactor,
    required this.sustained,
    required this.fit,
    required this.notes,
  });

  /// Decodes an estimate.
  factory Estimate.fromJson(Map<String, Object?> json) {
    final ceiling = json['ceilingGBps'];
    final sustainedFactor = json['sustainedFactor'];
    final sustained = json['sustained'];
    return Estimate(
      model: ModelSpec.fromJson(jsonMap(json['model'])),
      contextTokens: jsonInt(json['contextTokens']),
      bytesPerToken: jsonInt(json['bytesPerToken']),
      ceilingGBps: ceiling == null ? null : Interval.fromJson(jsonMap(ceiling)),
      efficiency: Interval.fromJson(jsonMap(json['efficiency'])),
      peak: Interval.fromJson(jsonMap(json['peak'])),
      sustainedFactor: sustainedFactor == null
          ? null
          : Interval.fromJson(jsonMap(sustainedFactor)),
      sustained: sustained == null
          ? null
          : Interval.fromJson(jsonMap(sustained)),
      fit: MemoryFit.fromJson(jsonMap(json['fit'])),
      notes: jsonList(json['notes'], (note) => note as String),
    );
  }

  /// The model estimated.
  final ModelSpec model;

  /// Tokens already in the KV cache.
  final int contextTokens;

  /// Bytes each decoded token pulls through memory.
  final int bytesPerToken;

  /// The measured ceiling the prediction scales, as its 95% interval; null
  /// when the GPU probe did not run.
  final Interval? ceilingGBps;

  /// η: the share of the ceiling llama.cpp's decode loop achieved on the
  /// calibration devices.
  final Interval efficiency;

  /// Single-stream decode throughput at the start of a session, tokens per
  /// second.
  final Interval peak;

  /// Peak-to-sustained ratio measured on phones after minutes of generation;
  /// null where no calibrated phone data applies.
  final Interval? sustainedFactor;

  /// Decode throughput once the device has throttled; null where
  /// [sustainedFactor] is.
  final Interval? sustained;

  /// Whether the working set fits.
  final MemoryFit fit;

  /// Caveats to surface alongside the numbers.
  final List<String> notes;

  /// The object form the Swift core reads and writes; null fields are
  /// omitted.
  Map<String, Object?> toJson() => {
    'bytesPerToken': bytesPerToken,
    if (ceilingGBps != null) 'ceilingGBps': ceilingGBps!.toJson(),
    'contextTokens': contextTokens,
    'efficiency': efficiency.toJson(),
    'fit': fit.toJson(),
    'model': model.toJson(),
    'notes': notes,
    'peak': peak.toJson(),
    if (sustained != null) 'sustained': sustained!.toJson(),
    if (sustainedFactor != null) 'sustainedFactor': sustainedFactor!.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is Estimate &&
      other.model == model &&
      other.contextTokens == contextTokens &&
      other.bytesPerToken == bytesPerToken &&
      other.ceilingGBps == ceilingGBps &&
      other.efficiency == efficiency &&
      other.peak == peak &&
      other.sustainedFactor == sustainedFactor &&
      other.sustained == sustained &&
      other.fit == fit &&
      listEquals(other.notes, notes);

  @override
  int get hashCode => Object.hash(
    model,
    contextTokens,
    bytesPerToken,
    ceilingGBps,
    efficiency,
    peak,
    sustainedFactor,
    sustained,
    fit,
    Object.hashAll(notes),
  );
}
