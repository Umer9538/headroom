import 'json_support.dart';

/// KV-cache geometry, from the GGUF keys named on each field.
final class KvGeometry {
  /// Creates the geometry; [bytesPerValue] is 2 for the f16 cache llama.cpp
  /// uses by default.
  const KvGeometry({
    required this.layers,
    required this.kvHeads,
    required this.headDim,
    this.bytesPerValue = 2,
  });

  /// Decodes the `kv` object of a model spec.
  factory KvGeometry.fromJson(Map<String, Object?> json) => KvGeometry(
    layers: jsonInt(json['layers']),
    kvHeads: jsonInt(json['kvHeads']),
    headDim: jsonInt(json['headDim']),
    bytesPerValue: jsonInt(json['bytesPerValue']),
  );

  /// `<arch>.block_count`
  final int layers;

  /// `<arch>.attention.head_count_kv`
  final int kvHeads;

  /// `<arch>.embedding_length / <arch>.attention.head_count`
  final int headDim;

  /// 2 for the f16 cache llama.cpp uses by default.
  final int bytesPerValue;

  /// Keys and values, every layer, one token.
  int get bytesPerToken => 2 * layers * kvHeads * headDim * bytesPerValue;

  /// The object form the Swift core reads and writes.
  Map<String, Object?> toJson() => {
    'bytesPerValue': bytesPerValue,
    'headDim': headDim,
    'kvHeads': kvHeads,
    'layers': layers,
  };

  @override
  bool operator ==(Object other) =>
      other is KvGeometry &&
      other.layers == layers &&
      other.kvHeads == kvHeads &&
      other.headDim == headDim &&
      other.bytesPerValue == bytesPerValue;

  @override
  int get hashCode => Object.hash(layers, kvHeads, headDim, bytesPerValue);
}

/// What the estimator needs to know about a model: how many bytes a token
/// has to pull through memory.
final class ModelSpec {
  /// Creates a spec; throws [ArgumentError] unless [tensorBytes] is positive.
  /// A null [kv] means the KV cache is not modelled.
  ModelSpec({
    required this.name,
    required this.tensorBytes,
    this.parameters,
    required this.kv,
  }) {
    if (tensorBytes <= 0) throw ArgumentError('a model has weights');
  }

  const ModelSpec._verified({
    required this.name,
    required this.tensorBytes,
    required this.parameters,
    required this.kv,
  });

  /// A model known only by its file size. The whole file is taken as weights
  /// (GGUF metadata is well under 1% of it) and the KV cache is not modelled.
  ModelSpec.fromGgufBytes({required String name, required int ggufBytes})
    : this(name: name, tensorBytes: ggufBytes, parameters: null, kv: null);

  /// Decodes a spec.
  factory ModelSpec.fromJson(Map<String, Object?> json) {
    final parameters = json['parameters'];
    final kv = json['kv'];
    return ModelSpec(
      name: json['name'] as String,
      tensorBytes: jsonInt(json['tensorBytes']),
      parameters: parameters == null ? null : jsonInt(parameters),
      kv: kv == null ? null : KvGeometry.fromJson(jsonMap(kv)),
    );
  }

  /// TinyLlama-1.1B-1T-OpenOrca Q4_0, the model PocketRoofline measured.
  ///
  /// Every field read from the GGUF header of the file with SHA-256
  /// bd07d1c53b833d422272259b17b393270b8f81c937d14332dfa044fe1b349884:
  /// tensor bytes are the sum of every tensor's on-disk size (201 tensors),
  /// `llama.block_count` 22, `llama.attention.head_count_kv` 4,
  /// `llama.embedding_length` 2048 / `llama.attention.head_count` 32 = 64.
  static const ModelSpec tinyLlama1_1BQ4_0 = ModelSpec._verified(
    name: 'TinyLlama-1.1B Q4_0',
    tensorBytes: 635990016,
    parameters: 1100048384,
    kv: KvGeometry(layers: 22, kvHeads: 4, headDim: 64),
  );

  /// Qwen2.5-0.5B-Instruct Q4_K_M, read the same way from the file with SHA-256
  /// 6eb923e7d26e9cea28811e1a8e852009b21242fb157b26149d3b188f3a8c8653:
  /// 290 tensors, `qwen2.block_count` 24, `qwen2.attention.head_count_kv` 2,
  /// `qwen2.embedding_length` 896 / `qwen2.attention.head_count` 14 = 64.
  ///
  /// The name is the Swift core's, quantisation suffix included.
  // ignore: constant_identifier_names
  static const ModelSpec qwen2_5_0_5BInstructQ4_K_M = ModelSpec._verified(
    name: 'Qwen2.5-0.5B-Instruct Q4_K_M',
    tensorBytes: 391859712,
    parameters: 494032768,
    kv: KvGeometry(layers: 24, kvHeads: 2, headDim: 64),
  );

  /// A display name.
  final String name;

  /// Bytes of weights read once per decoded token.
  final int tensorBytes;

  /// Parameter count, when known.
  final int? parameters;

  /// Null when the geometry is not known, in which case the KV cache is not
  /// modelled.
  final KvGeometry? kv;

  /// Bytes of KV cache for [contextTokens] tokens already in context.
  int kvBytes({required int contextTokens}) =>
      (kv?.bytesPerToken ?? 0) * contextTokens;

  /// Single-stream decode reads every weight once per token, plus the cache
  /// for every token already in context.
  int bytesPerToken({required int contextTokens}) =>
      tensorBytes + kvBytes(contextTokens: contextTokens);

  /// The object form the Swift core reads and writes.
  Map<String, Object?> toJson() => {
    if (kv != null) 'kv': kv!.toJson(),
    'name': name,
    if (parameters != null) 'parameters': parameters,
    'tensorBytes': tensorBytes,
  };

  @override
  bool operator ==(Object other) =>
      other is ModelSpec &&
      other.name == name &&
      other.tensorBytes == tensorBytes &&
      other.parameters == parameters &&
      other.kv == kv;

  @override
  int get hashCode => Object.hash(name, tensorBytes, parameters, kv);

  @override
  String toString() => name;
}
