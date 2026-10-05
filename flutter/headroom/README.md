# headroom

A two-second, on-device probe that tells your Flutter app how fast an LLM of
a given size will decode on *this* phone, right now, and whether it will fit,
without downloading a model. iOS 17+ and Android 10+ (API 29).

It answers three questions an app cannot ask the OS:

- **How fast?** A single-stream decode estimate in tokens per second, as an
  interval, for any model size.
- **For how long?** A sustained estimate after the phone has throttled.
- **Will it fit?** A memory verdict against the memory the OS reports.

Every figure says where it came from: `measured` on this device just now,
`calibrated (n=…)` from committed measurements of n other devices, or
`unknown`. The types make it impossible to read an estimate as a measurement.

This is the Flutter plugin for the [Headroom Swift
package](https://github.com/Umer9538/headroom); the probe is the package's
own C and Swift code, and the estimator is a Dart port of its maths.

## Usage

```dart
import 'package:headroom/headroom.dart';

final report = await Headroom.probe();            // one to two seconds, off the UI thread
report.ceilingGBps;                               // Quantity(54.7, basis: measured) on iOS; null on Android

final estimate = report.estimate(ModelSpec.tinyLlama1_1BQ4_0, contextTokens: 1024);
estimate.peak;        // Interval [55.7, 76.7] tok/s, basis calibrated (n=2) on iOS; unknown on Android
estimate.sustained;   // Interval? — calibrated (n=2) on an iPhone; null elsewhere
estimate.fit;         // fits (2810 MB spare), basis measured

report.toJsonString();                            // the whole report, for pasting back
```

A model you only know by file size works too:
`ModelSpec.fromGgufBytes(name: '2.2 GB model', ggufBytes: 2200000000)`. The
estimate then notes that the KV cache is not modelled.

`Headroom.cancel()` stops a running probe at its next stage boundary. Flutter's
animation library also exports a type named `Interval`, so a file that uses
both can `import 'package:flutter/material.dart' hide Interval;`.

## What each platform measures

| | iOS | Android |
|---|---|---|
| GPU ceiling | STREAM copy/scale/add/triad through Metal, 3 × 128 MB, GPU-timestamped, output verified; the triad median is the ceiling | none in this version: `gpu` is null and a warning says so |
| CPU triad | the C core's pthread STREAM triad, 3 × 64 MB, NEON, output verified; the performance cluster and all cores are tried and the better median kept, both recorded in `attempts` | the same C core, one all-core attempt (Android has no API for the performance cluster), recorded in `attempts` |
| Available memory | `os_proc_available_memory`, the process's budget, basis `measured` | `ActivityManager.MemoryInfo.availMem`, basis `measured`, plus `lowMemory` and `threshold` |
| Thermal, power | `ProcessInfo.thermalState`, Low Power Mode, `UIDevice` battery | `PowerManager.currentThermalStatus` folded as below, Battery Saver, `BatteryManager` |
| Device | uname identifier, iOS version and build | `Build.MANUFACTURER MODEL`, `Build.SOC_MANUFACTURER SOC_MODEL` (API 31+, else `unknown`), `Build.VERSION.RELEASE`, `Build.ID` |
| Predictions | peak and sustained intervals, basis `calibrated (n=2)` | `unknown`, with the note "no Android calibration yet" |

A probe never allocates past what the OS reports as available: if the three
arrays would not fit, that probe is skipped and the warning says so. In the
iOS Simulator and the Android Emulator a warning says the figures are the
host machine's; simulator memory is reported with basis `unknown`.

Android's seven thermal levels fold into the report's four; the original
name is kept in `conditions.platformThermalStatus`:

| `PowerManager` status | `ThermalState` |
|---|---|
| `NONE` | `nominal` |
| `LIGHT`, `MODERATE` | `fair` |
| `SEVERE` | `serious` |
| `CRITICAL`, `EMERGENCY`, `SHUTDOWN` | `critical` |

## The maths

Single-stream decode is memory-bound: each token reads every weight once plus
the KV cache for every token already in context.

    bytesPerToken  = tensorBytes + 2 × layers × kvHeads × headDim × contextTokens × 2   (f16 KV, llama.cpp's default)
    η              = achievedGBps / measuredCeilingGBps                                 (per calibration device)
    peak tok/s     = measuredCeilingGBps × η / bytesPerToken      as an interval over the ceiling's 95% CI and min…max η
    sustained      = peak × sustainedFactor                        as an interval over the measured phones
    required bytes = tensorBytes × 1.1 + kvBytes(context) + 150 MB    (stated assumptions; a margin under 10% is "tight")

η and the sustained factor are computed at run time from
`assets/calibration.json`, a copy of the Swift package's file. Nothing is
typed in as a constant; the package's `Calibration/README.md` does the
arithmetic row by row.

| SoC | Decode (tok/s) | Achieved GB/s | Measured ceiling GB/s | η | Source |
|---|---|---|---|---|---|
| A15 Bionic (iPhone 13) | 42.8012 | 27.221 | pending (null) | — | PocketRoofline SISO, warm start, unplugged |
| Apple M1 (MacBook Pro 2020) | 61.1016 | 38.860 | 56.000 (median of 3 runs) | 0.6939 | PocketRoofline SISO; ceiling from `headroom-probe` on the same machine |
| A16 Bionic (iPhone 15 Plus) | 65.1648 | 41.444 | 45.317 (median of 4 probes) | 0.9145 | PocketRoofline app SISO, warm start, live UI on screen, battery, airplane mode; ceiling from the Headroom demo on the same phone |

η is the range 0.6939–0.9145, basis `calibrated (n=2)`: decode used 69% of
the measured ceiling on the M1 and 91% on the A16, and the estimator keeps
the whole range, so every upper bound is 1.32 × what the M1 alone gave. The
A16 joined after the Swift package's first out-of-sample test: a prediction
for that phone, made from the M1 alone, missed by 32%. The package's README
has the result.

| Sustained factor | Peak → sustained | Factor | Source |
|---|---|---|---|
| A15 Bionic, llama.cpp-Metal | 42.80 → 30.93 after 5 × 1024-token generations | 0.7227 | PocketRoofline SILO |
| A18 Pro (iPhone 16 Pro), MLX | 40.49 → 23.67 over 20 runs | 0.5846 | arXiv:2603.23640 |
| A16 Bionic (iPhone 15 Plus), llama.cpp-Metal | 65.16 → 27.16 on the 5th 1024-token generation, run straight after LISO | 0.4169 | PocketRoofline app SILO; the step into it is unexplained |

The sustained range is 0.4169–0.7227, basis `calibrated (n=3)`. The A16
factor comes from a halving of decode speed, not yet explained, at the
boundary between two benchmark regimes; it is included because it widens
the range.

Every calibration device is an Apple SoC with a Metal-measured ceiling, which
is why Android gets no η: a prediction there would be a borrowed constant,
and the plugin says `unknown` instead.

## Example

`example/` has one **Probe** button, a report card (ceilings with their 95%
intervals and basis tags, thermal state, power, memory), an estimate table
for four model sizes at 1024 tokens of context, and **Copy JSON** for pasting
a phone's result back into the calibration. `example/integration_test/`
runs the real probe on whatever device it is pointed at and checks that every
figure recomputed in Dart from the raw iteration times equals what the native
side reported.

## The native side

`tool/sync_native.sh` is the single source of truth for every native file:
it copies the C core into `ios/Classes/CHeadroom/` and
`android/src/main/cpp/CHeadroom/`, the Swift probe layer into
`ios/Classes/Core/`, and `calibration.json` into `assets/`. Nothing in those
places is edited by hand. When the Swift package changes, run it again and
commit the result; `tool/sync_native.sh --check` reports drift.

The estimator layer of the Swift package (`Estimate`, `MemoryFit`,
`Calibration`, `ModelSpec`) is not copied: it is ported to Dart under
`lib/src/`, and the unit tests reproduce the package's test fixtures number
for number. The bootstrap interval uses the same seeded SplitMix64 stream and
the same index derivation as Swift, and a test proves it by recomputing the
committed M1 run's intervals bit for bit.

- **iOS** is a CocoaPods pod (`ios/headroom.podspec`): Swift 6 language
  mode, the C files at `-O3` in every configuration, and a module map so the
  core's `import CHeadroom` resolves unchanged. The native side exposes only
  the probe, on the `headroom/probe` method channel.
- **Android** builds the same C core with CMake (`-O3`, NEON on arm64) and a
  small JNI wrapper; the Kotlin side reads memory, thermal, battery and device
  facts and writes the same report JSON, with a Kotlin port of the statistics.

Because the C kernel is optimised in every configuration here, a debug
`flutter run` still measures a CPU ceiling; the Swift package marks debug
CPU figures `unknown` because a package cannot carry per-target flags.

## Limitations

- **GPU path only, iOS only.** The ceiling and the estimate describe a Metal
  backend such as llama.cpp-Metal or MLX. The CPU triad is a ceiling for CPU
  backends and is not used in the estimate.
- **No Android calibration.** Android reports a CPU ceiling, memory and
  conditions, but no throughput prediction: there is no GPU probe and no
  Android row in the calibration.
- **Calibrated on n = 2 devices**, an M1 Mac and an A16 iPhone, whose η differ
  by a factor of 1.32; every interval carries that spread. The Swift
  package's one out-of-sample test so far, on the A16 before it joined the
  calibration, missed by 32%. The A15 row is pending the iPhone 13 run.
- **The thermal factor is from three phones on two runtimes**, presented as a
  range, not a curve for any particular device. Its lowest value, the A16's,
  is not yet explained.
- **Model geometry must be verified.** A spec built from file size alone
  omits the KV cache; the estimate says so. Only two presets ship, both read
  from GGUF headers with their file hashes in `ModelSpec`.
- **Available memory on Android is system-wide** (`availMem`), not a
  per-process budget like iOS's.
- **Simulator and emulator figures are the host's**, and the report says so.
  In the iOS Simulator the GPU probe is skipped: the simulator's command-buffer
  timestamps do not bracket the GPU work (128 MB dispatches report tens of
  microseconds, thousands of GB/s), so there is no honest figure to report.
  Probe a device.

The Swift package's README lists what was searched for and not found before
this was built.

## Status

- Unit tests (`flutter test`): 69, including the Swift fixture numbers, the
  A16 rows recomputed from their raw records, and the bit-for-bit statistics
  check against the committed M1 run and the four iPhone 15 Plus probes taken
  with the Swift package's demo app.
- End to end: run on the iOS Simulator and the Android Emulator through
  `example/integration_test/probe_test.dart`; those figures are the host
  machine's. No physical phone has been probed through the plugin yet.

## License

MIT. Built on the measurements in
[PocketRoofline](https://github.com/Umer9538/pocketroofline).
