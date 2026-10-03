# Calibration

Every calibrated constant Headroom uses is computed at run time from the rows
in [`Sources/Headroom/Resources/calibration.json`](../Sources/Headroom/Resources/calibration.json).
This file shows where each row comes from and does the arithmetic by hand, so
the JSON can be checked line by line. `CalibrationTests` recomputes the derived
columns from the inputs and fails if the two disagree.

Units: bytes are decimal (1 GB = 10^9 bytes). Bandwidth is GB/s.

## 1. Achieved decode bandwidth (PocketRoofline)

Single-stream decode reads every weight once per token, so

    achievedGBps = decodeTokPerSec × tensorBytes / 1e9

exactly as `harness/report.py::achieved_bandwidth` in PocketRoofline computes
it. `tensorBytes` for TinyLlama-1.1B Q4_0 is 635,990,016, the sum of all 201
tensors' on-disk sizes read from the GGUF header (file SHA-256
`bd07d1c5…9884`, the one PocketRoofline's records cite). The KV-cache term is
left out here, as it is in PocketRoofline: at the 128-token prompts of the
SISO regime it is under 1% of the weight bytes, and the estimator models it
separately for the context the caller asks about.

Decode rates are the mean of the five committed SISO repeats in
`pocketroofline/results/`:

| SoC | Record | Repeats (tok/s) | Mean | × 0.635990016 GB |
|---|---|---|---|---|
| A15 Bionic (iPhone 13) | `iphone13-a15-ios26.6.1-23G83-…-siso.json` | 42.597, 42.439, 42.575, 43.202, 43.193 | 214.006 / 5 = **42.8012** | **27.221 GB/s** |
| Apple M1 (MacBook Pro 2020) | `m1-macos27-26A5421a-…-siso.json` | 59.729, 62.786, 59.816, 60.7, 62.477 | 305.508 / 5 = **61.1016** | **38.860 GB/s** |

These reproduce the 27.2 and 38.9 GB/s PocketRoofline publishes. Conditions
differ and are carried in each row's `source`: the A15 session was a warm
start (thermal state `fair`, never `nominal`), radios off, unplugged; the M1
was measured with `llama-bench` (its `tg128` test decodes from an empty
context) on mains power.

## 2. Measured ceilings

`ceilingGBps` is the median of the Metal STREAM triad over 10 timed
dispatches of 3 × 128 MB, as `headroom-probe` reports it. It is filled only
from an actual run on the same hardware.

### Apple M1: filled 2026-10-03

Three consecutive runs of `swift run -c release headroom-probe` on the
MacBookPro17,1 the decode rate was measured on (macOS 27.0 build 26A428;
PocketRoofline's decode run was on build 26A5421a), battery power, thermal
state nominal, nothing else running. The full reports are in
[`runs/`](runs/).

| Run | Triad median | 95% CI of the median | Best |
|---|---|---|---|
| run1 | 56.333 | 55.875 – 57.937 | 58.027 |
| run2 | 56.000 | 54.616 – 57.249 | 57.757 |
| run3 | 53.633 | 47.470 – 55.092 | 57.659 |

    ceilingGBps(M1) = median(56.333, 56.000, 53.633) = 56.000

The spread between runs (±2.5%) is larger than any single run's confidence
interval suggests, which is why three runs are recorded rather than one.

### A15 Bionic: null

The row stays `null` until the demo app has been run on the iPhone 13 that
produced the decode figures. With it null the A15 contributes nothing to the
efficiency range and the basis reports `n = 1`. To fill it:

1. Open `Examples/HeadroomDemo/HeadroomDemo.xcodeproj`, run the scheme (it
   builds **Release**) on the iPhone 13, tap **Probe**, then **Copy JSON**.
2. Save the pasted report as `Calibration/runs/a15-iPhone14-5-<iOS version>-<build>-run1.json`
   (repeat for two more runs if possible).
3. Put `gpu.triad.medianGBps.value` (or the median across runs) into the A15
   row's `ceilingGBps`, and describe the run in `ceilingSource`: thermal state,
   power source, build.
4. `swift test` checks that the stored `achievedGBps` still matches its inputs
   and that every efficiency lies in (0, 1).

## 3. Efficiency η

    η = achievedGBps / ceilingGBps        for each row with a ceiling

    η(M1) = 38.860 / 56.000 = 0.6939

With one row the range is the point [0.6939, 0.6939] and the basis is
`calibrated(devices: 1)`. When the A15 row is filled the range becomes
[min, max] over both devices with `devices: 2`, and every prediction widens
accordingly.

## 4. Sustained factor

    factor = sustainedTokPerSec / peakTokPerSec

| SoC | Runtime | Peak | Sustained | Factor | Source |
|---|---|---|---|---|---|
| A15 Bionic | llama.cpp-Metal | 42.8012 (SISO mean) | 30.933 (5th consecutive 1024-token generation, SILO) | 30.933 / 42.8012 = **0.7227** | PocketRoofline `…-siso.json`, `…-silo.json` |
| A18 Pro (iPhone 16 Pro) | MLX | 40.49 (first run) | 23.67 (20th run) | 23.67 / 40.49 = **0.5846** | arXiv:2603.23640 (Qwen 2.5 1.5B) |

The factor used is the range [0.5846, 0.7227] with basis
`calibrated(devices: 2)`. The two rows come from different runtimes, models
and protocols, and the estimator's notes say so. Rows carry `platform: iOS`;
no macOS row exists because the only macOS record (the M1 on mains power)
held flat, which says nothing about a fanless Mac on battery, so on macOS the
sustained estimate is `nil` rather than an assumed 1.0.

## 5. How the estimator uses the rows

    bytesPerToken = tensorBytes + 2 × layers × kvHeads × headDim × contextTokens × 2
    peak          = [ceiling.ci.low × η.min, ceiling.ci.high × η.max] × 1e9 / bytesPerToken
    sustained     = peak × [factor.min, factor.max]          (iOS only)

`ceiling.ci` is the probe's 95% bootstrap interval of the triad median on the
device being estimated, with basis `measured`; η and the factor are
`calibrated`; the products take the weaker basis, so no prediction can ever
carry `measured`.

Worked example, this M1, the run in the README's validation table: triad
median 54.743 GB/s (CI 52.948 – 55.260), TinyLlama at 128 tokens of context
(bytesPerToken = 635,990,016 + 22,528 × 128 = 638,873,600):

    peak = [52.948 × 0.6939, 55.260 × 0.6939] × 1e9 / 638,873,600 = [57.5, 60.0] tok/s
