## 0.1.0

First release.

- `Headroom.probe()` runs the Headroom Swift package's probe on iOS (Metal
  STREAM ceiling, C STREAM triad, memory, thermal, power, device) and the
  same C triad with Android's memory, thermal, battery and device facts on
  Android, returning a typed `ProbeReport` with a basis on every figure.
- `ProbeReport.estimate()` is a Dart port of the package's estimator and
  memory-fit maths, driven by a copy of its `calibration.json`; predictions
  on Android carry basis `unknown` until an Android calibration exists.
- `ModelSpec.tinyLlama1_1BQ4_0` and `ModelSpec.qwen2_5_0_5BInstructQ4_K_M`,
  the two presets verified from GGUF headers.
- `tool/sync_native.sh` keeps the native sources identical to the package.
