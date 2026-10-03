# Headroom

An embeddable, two-second, on-device probe that tells an app how fast an LLM
of a given size will decode on *this* phone, right now, and whether it will
fit — without downloading a model. Swift package for iOS 17+ and macOS 14+.

It answers three questions a shipping app cannot currently ask the OS:

- **How fast?** A single-stream decode estimate in tokens per second, as an
  interval, for any model size.
- **For how long?** A sustained estimate after the phone has throttled.
- **Will it fit?** A memory verdict against the budget the OS will actually
  grant the process.

Every figure says where it came from: `measured` on this device just now,
`calibrated(devices: n)` from committed measurements of other devices, or
`unknown`. The types make it impossible to read an estimate as a measurement.

## Usage

```swift
import Headroom

let report = try await Headroom.probe()          // ~1–2 s, off the main actor, cancellable
report.ceilingGBps                                // Quantity(value: 54.7, basis: .measured)

let estimate = report.estimate(.tinyLlama1_1BQ4_0, contextTokens: 1024)
estimate.peak        // Interval(low: 55.7, high: 58.2, basis: .calibrated(devices: 1))  tok/s
estimate.sustained   // Interval? — nil on macOS; .calibrated(devices: 2) on iPhone
estimate.fit         // .fits(marginMB: 2810), basis .measured on iOS

let json = try report.jsonData()                  // the whole report, for pasting back
```

A model you only know by file size works too: `ModelSpec(name: "2.2 GB model",
ggufBytes: 2_200_000_000)` — the estimate then notes that the KV cache is not
modelled.

## The maths

Single-stream decode is memory-bound: each token reads every weight once plus
the KV cache for every token already in context.

    bytesPerToken  = tensorBytes + 2 × layers × kvHeads × headDim × contextTokens × 2   (f16 KV, llama.cpp's default)
    achievedGBps   = decodeTokPerSec × bytesPerToken / 1e9                              (PocketRoofline's placement)
    η              = achievedGBps / measuredCeilingGBps                                 (per calibration device)
    peak tok/s     = measuredCeilingGBps × η / bytesPerToken      as an interval over the ceiling's 95% CI and min…max η
    sustained      = peak × sustainedFactor                        as an interval over the measured phones

The ceiling is Headroom's own measurement: a STREAM triad on the GPU through
Metal, timed by the command buffer's GPU timestamps and verified by reading
the output back. PocketRoofline had to use *published* peak bandwidth (and for
the A15 the published figures disagree); the probe replaces that with a number
measured on the device in hand.

## Calibration

η and the sustained factor are computed at run time from
[`calibration.json`](Sources/Headroom/Resources/calibration.json). Nothing is
typed in as a constant; [`Calibration/README.md`](Calibration/README.md) does
the arithmetic row by row.

| SoC | Decode (tok/s) | Achieved GB/s | Measured ceiling GB/s | η | Source |
|---|---|---|---|---|---|
| A15 Bionic (iPhone 13) | 42.8012 | 27.221 | **pending** (null) | — | PocketRoofline SISO, warm start, unplugged |
| Apple M1 (MacBook Pro 2020) | 61.1016 | 38.860 | 56.000 (median of 3 runs: 56.333, 56.000, 53.633) | 0.6939 | PocketRoofline SISO (llama-bench tg128); ceiling from `headroom-probe` on the same machine, [`Calibration/runs/`](Calibration/runs/) |

Efficiency basis today: `calibrated(devices: 1)`. The A15 row is filled only
by running the demo app on the iPhone 13 that produced the decode figure.

| Sustained factor | Peak → sustained | Factor | Source |
|---|---|---|---|
| A15 Bionic, llama.cpp-Metal | 42.80 → 30.93 after 5 × 1024-token generations | 0.7227 | PocketRoofline SILO |
| A18 Pro (iPhone 16 Pro), MLX | 40.49 → 23.67 over 20 runs | 0.5846 | arXiv:2603.23640 |

Basis `calibrated(devices: 2)`, two runtimes, two models — it is a throttling
range, not a prediction of any particular phone's curve. Applied on iOS only.

## Validation

Real rows only. Predictions are at the context the measured regime used.

| Device | Conditions | Ceiling (triad median, 95% CI) | CPU triad | Model, context | Predicted tok/s | Measured tok/s | Error |
|---|---|---|---|---|---|---|---|
| MacBook Pro (M1, 2020), macOS 27.0 (26A428), 2026-10-03T20:14Z | battery power, thermal nominal, low power off | 54.7 GB/s (52.9 – 55.3) | 51.5 GB/s (4 threads; 46.7 with 8) | TinyLlama-1.1B Q4_0, 128 tokens | 57.5 – 60.0 | 61.10 (SISO, llama-bench tg128) | measured is 1.8% above the upper bound; midpoint −3.8% |
| same run | | | | TinyLlama-1.1B Q4_0, 1024 tokens | 55.7 – 58.2 | 64.55 (SILO, llama-bench tg1024) | measured is 10.9% above the upper bound; midpoint −11.7% |
| iPhone 13 (A15), iOS 26.6.1 | | pending | pending | TinyLlama-1.1B Q4_0 | pending | 42.80 (SISO) / 30.93 sustained | pending |

Two honest caveats on the M1 row. First, it is a consistency check, not an
independent validation: with `n = 1` the efficiency was calibrated on this same
machine, so the prediction can only drift from the measurement by the
ceiling's run-to-run variation and by the KV term. This run's ceiling was
54.7 GB/s against the 56.0 calibrated (−2.2%), which accounts for the
128-token miss; the next two runs of the same session measured 55.4 and
57.2 GB/s and predicted 58.3 – 62.9 and 57.1 – 62.9 tok/s at 128 tokens, both
bracketing 61.10. The row is the session's first run, not its best. The first
independent test is the iPhone 13. Second, the SILO under-prediction is real
and not understood: `llama-bench` measured decode faster over 1024 tokens
than over 128, while the model charges the larger context for its KV reads,
so the two move in opposite directions. A fixed per-run cost being amortised
over the longer generation would explain it, but that has not been measured.
The full CLI output for this row is in the section below.

## Probe design

- **GPU** (`MetalBandwidthProbe`): STREAM copy / scale / add / triad over
  three 128 MB `.storageModePrivate` buffers, float4 per thread, shader source
  compiled at run time. One warm-up and ten timed dispatches per kernel,
  timed by `MTLCommandBuffer.gpuStartTime/gpuEndTime`. After each kernel's
  batch, three windows of its output are blitted back and checked against the
  exact expected value (1, 3, 4, 15). Byte accounting is STREAM's: copy and
  scale move 2 × array bytes per iteration, add and triad 3 ×. Reports best,
  median and a seeded 95% bootstrap interval of the median.
- **CPU** (`CHeadroom`, plain C): triad `a[i] = b[i] + q·c[i]` over three
  64 MB float32 arrays split into one static slice per pthread, one warm-up
  and seven timed iterations, every element verified afterwards. The loop is
  written with NEON intrinsics because at `-Os`, Xcode's default for release
  C, clang declines to auto-vectorise it (a scalar triad reads 28 GB/s on one
  M1 core instead of 52). Two thread counts are tried where they differ, the
  performance cluster alone and every core, and the higher median is the
  figure; every attempt is in the report. On an M1 the all-core run is about
  10% lower because each iteration waits for its slowest (efficiency-core)
  slice. The C target carries no compiler flags of its own (a package with
  unsafe flags cannot be a dependency); it reports `compiledWithOptimisation`,
  and a debug build's CPU figure is marked `unknown`.
- **Context**: thermal state, low power mode, power source, physical memory,
  `os_proc_available_memory` on iOS (a fallback marked `unknown` on macOS,
  which has no per-process budget, and in the simulator), hardware
  identifier, OS version and build.
- **Budget**: a probe never allocates past the budget the OS reports, because
  iOS enforces it by killing the process rather than failing the call. If the
  three arrays would not fit, that probe is skipped and the warning says so.
  In the simulator a warning says the figures are the host Mac's.
- **Concurrency**: `Headroom.probe` never runs on the main actor; blocking
  work goes to a Dispatch queue so the cooperative pool stays free, and
  cancelling the task stops the probe at the next kernel boundary.

### `headroom-probe` on this M1

```
$ swift run -c release headroom-probe
MacBookPro17,1 (Apple M1), macOS 27.0 (26A428), thermal nominal, power battery, low power mode off
GPU (Apple M1) STREAM, 3 × 128 MB:
  copy   median 56.4 GB/s (95% CI 49.4–57.6, best 59.0) — measured
  scale  median 57.9 GB/s (95% CI 57.6–59.0, best 60.3) — measured
  add    median 51.6 GB/s (95% CI 49.2–55.8, best 57.5) — measured
  triad  median 54.7 GB/s (95% CI 52.9–55.3, best 55.9) — measured
CPU triad, 4 threads, 3 × 64 MB: median 51.5 GB/s (95% CI 49.8–54.1, best 55.7) — measured
  tried 4 threads 51.5, 8 threads 46.7 GB/s; kept the higher median
Memory: 17.18 GB physical, 3.32 GB available (unknown)

TinyLlama-1.1B Q4_0: 0.636 GB of weights, KV 22528 bytes/token
  context   bytes/token   peak decode          sustained
  128       638873600     57.5–60.0 tok/s      n/a
  256       641757184     57.3–59.8 tok/s      n/a
  1024      659058688     55.7–58.2 tok/s      n/a
  2048      682127360     53.9–56.2 tok/s      n/a
  basis: peak calibrated (n=1); efficiency η = 0.6939–0.6939 (calibrated (n=1))
  note: No sustained factor applies: throttling has only been calibrated on iPhones.
  note: Available memory is a fallback: this platform exposes no per-process budget, so the fit verdict is unknown.

PocketRoofline measured on an M1 MacBook Pro, same model and quantisation (llama-bench, tg128 / tg1024):
  61.10 tok/s SISO, 64.55 tok/s SILO — compare with the 128–1024 rows above.
```

(Preceded by the full report as JSON; captured 2026-10-03T20:14:00Z in
0.54 s with the shaders already cached — a device's first run also compiles
them and takes longer.)

## Memory fit

`required = tensorBytes × 1.1 + kvBytes(context) + 150 MB`, compared with the
available budget. The 1.1 (runtime overhead over the weights) and 150 MB
(engine, pipelines, tokenizer) are stated assumptions, as is the rule that a
margin under 10% of the requirement is `tight`. The verdict carries the basis
of the available-memory figure: `measured` on iOS, `unknown` elsewhere.

## Model presets

Both presets were read from GGUF headers with a stdlib-only reader; the
fields and file hashes are in `ModelSpec.swift`.

| Preset | Tensor bytes | Layers | KV heads | Head dim | Parameters |
|---|---|---|---|---|---|
| `tinyLlama1_1BQ4_0` | 635,990,016 | 22 | 4 | 64 | 1,100,048,384 |
| `qwen2_5_0_5BInstructQ4_K_M` | 391,859,712 | 24 | 2 | 64 | 494,032,768 |

One correction to the source records: PocketRoofline's run files label
TinyLlama's attention `MHA`; the file's `head_count_kv` is 4 against
`head_count` 32, so the KV cache is grouped-query sized and is modelled that
way here.

## Limitations

- **GPU path only.** The ceiling and the estimate describe a Metal backend
  such as llama.cpp-Metal or MLX. The CPU triad is reported as a ceiling for
  CPU backends and is not used in the estimate; it is the better of two
  thread counts, not a statement about any particular backend's threading.
- **No ANE claims.** Apple publishes no bandwidth or throughput for the
  Neural Engine and exposes no counters; nothing here estimates Core ML on it.
- **Calibrated on n = 1 device today**, the M1, which is also the only
  validation device so far. The A15 row and the first independent validation
  are pending the iPhone 13 run.
- **The thermal factor is from two phones on two runtimes** and two models,
  presented as a range. It is not a model of any particular device's curve.
- **Model geometry must be verified.** A `ModelSpec` built from file size
  alone omits the KV cache; the estimate says so.
- **Debug builds** compile the C target without optimisation, which spills
  the vector loop to the stack (8 GB/s on one M1 core); the CPU figure is
  then marked `unknown`. The demo scheme runs Release for this reason.

## What was searched, and not found (2026-10-04)

The question was whether an SDK already answers "will it be fast, will it
throttle, will it fit" from a run-time measurement of the device.

- Apple's Foundation Models `availability` reports a model as available and
  can still fail at use; it does not measure or estimate throughput.
- TokForge's "Can my phone run it" is a chipset lookup inside a consumer app,
  not something an app can embed.
- Cactus ships a benchmark CLI that runs a model; it is not a probe without one.
- DeviceMark is a leaderboard: quality, speed and memory for verified
  on-device model ports, measured on a fixed phone under one protocol. It is
  not a run-time API.

None of these were found to combine a device measurement with a
basis-labelled estimate, which is what this package does. If something else
already does, this section is updated first.

## Building and testing

```
swift build && swift test                              # macOS; includes a live GPU/CPU probe
swift run -c release headroom-probe                     # the CLI above
cd Examples/HeadroomDemo
xcodebuild -project HeadroomDemo.xcodeproj -scheme HeadroomDemo \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project HeadroomDemo.xcodeproj -scheme HeadroomDemo \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The demo (`com.umer9538.headroomdemo`, iPhone, iOS 17+) has one **Probe**
button, a report card, an estimate table for four model sizes, and **Copy
JSON** for pasting a phone's result back into the calibration. Its
`.xcodeproj` is generated from `project.yml` and committed, so it opens
without XcodeGen; after editing `project.yml`, run `xcodegen generate` and
commit the result. The scheme runs **Release** so the C triad is optimised on
the phone (see Limitations).

## Layout

```
Sources/CHeadroom/            C: pthread STREAM triad, available-memory query
Sources/Headroom/             Swift 6: probe, report, estimator, calibration loader
Sources/Headroom/Resources/   calibration.json
Executables/headroom-probe/   macOS CLI
Examples/HeadroomDemo/        SwiftUI demo (XcodeGen project.yml)
Calibration/                  derivation of every constant, and the raw ceiling runs
Tests/HeadroomTests/          estimator, accounting, statistics, calibration, fit, coding, live probe
```

Built on the measurements in [PocketRoofline](https://github.com/Umer9538/pocketroofline).
MIT licensed.
