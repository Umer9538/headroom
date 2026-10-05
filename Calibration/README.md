# Calibration

Every calibrated constant Headroom uses is computed at run time from the rows
in [`Sources/Headroom/Resources/calibration.json`](../Sources/Headroom/Resources/calibration.json).
This file shows where each row comes from and does the arithmetic by hand, so
the JSON can be checked line by line. `CalibrationTests` recomputes the derived
columns from the inputs and fails if the two disagree, and recomputes the A16
rows from their raw records in [`runs/a16/`](runs/a16/).

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

Decode rates are the mean of the five committed SISO repeats: in
`pocketroofline/results/` for the A15 and the M1, and in the PocketRoofline
app capture committed here for the A16:

| SoC | Record | Repeats (tok/s) | Mean | × 0.635990016 GB |
|---|---|---|---|---|
| A15 Bionic (iPhone 13) | `iphone13-a15-ios26.6.1-23G83-…-siso.json` | 42.597, 42.439, 42.575, 43.202, 43.193 | 214.006 / 5 = **42.8012** | **27.221 GB/s** |
| Apple M1 (MacBook Pro 2020) | `m1-macos27-26A5421a-…-siso.json` | 59.729, 62.786, 59.816, 60.7, 62.477 | 305.508 / 5 = **61.1016** | **38.860 GB/s** |
| A16 Bionic (iPhone 15 Plus) | [`runs/a16/pocketroofline-iPhone15,5-1791162656.json`](runs/a16/pocketroofline-iPhone15,5-1791162656.json) | 66.069, 64.916, 65.095, 64.774, 64.969 | 325.8238 / 5 = **65.1648** | **41.444 GB/s** |

The A15 and M1 figures reproduce the 27.2 and 38.9 GB/s PocketRoofline
publishes. The A16's repeats are recorded as full doubles: they are shown here
to three decimals, the sum is of the recorded values (325.82378540…), and the
row stores the mean to four decimals. The prediction document's result first
said 65.17, from rounding twice; it carries a same-day correction to 65.16.

Conditions differ and are carried in each row's `source`: the A15 session was
a warm start (thermal state `fair`, never `nominal`), radios off, unplugged;
the M1 was measured with `llama-bench` (its `tg128` test decodes from an empty
context) on mains power; the A16 was captured by the PocketRoofline app
(matrix v1, llama.cpp-Metal `95ef7fc`, the same GGUF) with its UI live on
screen, from a warm start (thermal `fair`), on battery (60%) in airplane mode.

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

### A16 Bionic: filled 2026-10-05

Four consecutive probes from the Headroom demo app on the iPhone 15 Plus
(iPhone15,5) the decode rate was measured on, iOS 27.0 (24A437), between
01:05:26 and 01:05:38 UTC, straight before the PocketRoofline app run: battery
(60%), airplane mode, Low Power Mode off, thermal state `fair` (a warm start,
not `nominal`), the app's UI on screen. The full reports are in
[`runs/a16/`](runs/a16/).

| Probe | Triad median | 95% CI of the median | Best |
|---|---|---|---|
| `headroom-iPhone15,5-1791162326` | 45.888 | 45.597 – 46.133 | 46.351 |
| `headroom-iPhone15,5-1791162333` | 45.312 | 44.331 – 45.425 | 45.498 |
| `headroom-iPhone15,5-1791162335` | 45.049 | 43.654 – 45.332 | 45.859 |
| `headroom-iPhone15,5-1791162338` | 45.321 | 45.050 – 45.767 | 45.996 |

    ceilingGBps(A16) = median(45.888, 45.312, 45.049, 45.321)
                     = (45.3117 + 45.3215) / 2 = 45.3166, stored as 45.317

The ceiling is the median of all four probes. The pre-registered prediction
used only `…333`, the middle of the first three, as its rule said
([`predictions/2026-10-05-iphone15plus-a16.md`](predictions/2026-10-05-iphone15plus-a16.md)).
The three pilot probes in [`runs/pilot/`](runs/pilot/) are not used: they were
taken while charging, at thermal state `serious`.

### A15 Bionic: null

The row stays `null` until the demo app has been run on the iPhone 13 that
produced the decode figures. With it null the A15 contributes nothing to the
efficiency range and the basis reports `n = 2` (the M1 and the A16). To fill
it:

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

    η(M1)  = 38.860 / 56.000 = 0.6939
    η(A16) = 41.444 / 45.317 = 0.9145

With two rows the range is [0.6939, 0.9145] and the basis is
`calibrated(devices: 2)`. The two devices disagree by a factor of
0.9145 / 0.6939 = 1.318, and the estimator takes the range, not a mean: with
two devices there is nothing yet to say which value a third will follow. η is
not split by platform for the same reason; with one device of each kind, a
per-platform η would just be each device's own value. Compared with the
one-device calibration, every prediction keeps its lower bound and its upper
bound rises by 31.8%.

The A16 row exists because the M1-only η under-predicted the A16 by 32%
([`predictions/2026-10-05-iphone15plus-a16.md`](predictions/2026-10-05-iphone15plus-a16.md)).
Adding it widens the interval to the spread seen so far; it does not validate
the method. When the A15 row is filled the range becomes [min, max] over three
devices with `devices: 3`.

## 4. Sustained factor

    factor = sustainedTokPerSec / peakTokPerSec

| SoC | Runtime | Peak | Sustained | Factor | Source |
|---|---|---|---|---|---|
| A15 Bionic | llama.cpp-Metal | 42.8012 (SISO mean) | 30.933 (5th consecutive 1024-token generation, SILO) | 30.933 / 42.8012 = **0.7227** | PocketRoofline `…-siso.json`, `…-silo.json` |
| A18 Pro (iPhone 16 Pro) | MLX | 40.49 (first run) | 23.67 (20th run) | 23.67 / 40.49 = **0.5846** | arXiv:2603.23640 (Qwen 2.5 1.5B) |
| A16 Bionic (iPhone 15 Plus) | llama.cpp-Metal | 65.1648 (SISO mean) | 27.1645 (5th consecutive 1024-token generation, SILO, run straight after LISO) | 27.1645 / 65.1648 = **0.4169** | [`runs/a16/pocketroofline-iPhone15,5-1791162656.json`](runs/a16/pocketroofline-iPhone15,5-1791162656.json) |

The A16's sustained rate is the recorded 27.16451626… to four decimals.

The factor used is the range [0.4169, 0.7227] with basis
`calibrated(devices: 3)`. The three rows come from different runtimes, models
and protocols, and the estimator's notes say so. Rows carry `platform: iOS`;
no macOS row exists because the only macOS record (the M1 on mains power)
held flat, which says nothing about a fanless Mac on battery, so on macOS the
sustained estimate is `nil` rather than an assumed 1.0.

The A16 row is the least understood. In that capture the regimes ran SISO,
then LISO (2048 in / 128 out), then SILO (128 in / 1024 out). Decode fell from
59.17 tok/s on the last LISO repeat to 29.69 tok/s on the first SILO repeat,
seconds later, while prefill rose from 429 to 465 tok/s; the five SILO repeats
then ran 29.69, 30.89, 31.73, 28.00 and 27.16 tok/s. A plain thermal slowdown
would have pulled prefill down too, so the halving may be a step in memory or
power state rather than throttling. It is not yet explained, and a SILO-first
cold run is owed. The row is included anyway: it lowers the bottom of the
range from 0.5846 to 0.4169, so every sustained lower bound falls by 29%, and a
range that is too wide is the safer error.

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

    n = 1, as published:  peak = [52.948 × 0.6939, 55.260 × 0.6939] × 1e9 / 638,873,600 = [57.5, 60.0] tok/s
    n = 2, today:         peak = [52.948 × 0.6939, 55.260 × 0.9145] × 1e9 / 638,873,600 = [57.5, 79.1] tok/s

Both are in-sample: the M1 is a calibration device.

Worked example, the iPhone 15 Plus probe the pre-registered rule selected
(`runs/a16/headroom-iPhone15,5-1791162333.json`: triad median 45.312 GB/s,
CI 44.331 – 45.425), same model and context:

    n = 1, pre-registered:  peak = [44.331 × 0.6939, 45.425 × 0.6939] × 1e9 / 638,873,600 = [48.15, 49.34] tok/s
    n = 2, in-sample:       peak = [44.331 × 0.6939, 45.425 × 0.9145] × 1e9 / 638,873,600 = [48.15, 65.02] tok/s

Measured: 65.16 tok/s. The first line is the out-of-sample prediction, which
missed by 32.1% above its upper bound; `EstimatorTests` reproduces it from the
committed records. The second is in-sample, since the top of η is this
phone's own value, and it still stops 0.2% short: η is computed from weight
bytes alone (section 1) while the estimate also charges 128 tokens of KV cache,
0.45% of the bytes per token, and this probe's CI reaches only 0.24% above the
calibrated 45.317 GB/s.
