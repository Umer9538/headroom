import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/headroom.dart';

/// The two presets carry the numbers read from the GGUF headers in the Swift
/// core; nothing else is pinned here, because nothing else was verified.
void main() {
  test('TinyLlama-1.1B Q4_0 preset', () {
    const model = ModelSpec.tinyLlama1_1BQ4_0;
    expect(model.name, 'TinyLlama-1.1B Q4_0');
    expect(model.tensorBytes, 635990016);
    expect(model.parameters, 1100048384);
    expect(model.kv, const KvGeometry(layers: 22, kvHeads: 4, headDim: 64));
    expect(model.kv?.bytesPerValue, 2);
  });

  test('Qwen2.5-0.5B-Instruct Q4_K_M preset', () {
    const model = ModelSpec.qwen2_5_0_5BInstructQ4_K_M;
    expect(model.name, 'Qwen2.5-0.5B-Instruct Q4_K_M');
    expect(model.tensorBytes, 391859712);
    expect(model.parameters, 494032768);
    expect(model.kv, const KvGeometry(layers: 24, kvHeads: 2, headDim: 64));
    expect(model.kv?.bytesPerToken, 2 * 24 * 2 * 64 * 2);
  });

  test('a model has weights', () {
    expect(
      () => ModelSpec(name: 'empty', tensorBytes: 0, kv: null),
      throwsArgumentError,
    );
    expect(
      () => ModelSpec.fromGgufBytes(name: 'empty', ggufBytes: -1),
      throwsArgumentError,
    );
  });

  test('specs round-trip through JSON with and without geometry', () {
    for (final model in [
      ModelSpec.tinyLlama1_1BQ4_0,
      ModelSpec.fromGgufBytes(name: '2.2 GB model', ggufBytes: 2200000000),
    ]) {
      expect(ModelSpec.fromJson(model.toJson()), model);
    }
  });
}
