#!/usr/bin/env bash
#
# Copies the probe layer of the Headroom Swift package into this plugin.
#
# This script is the single source of truth for every native file under
# ios/Classes/CHeadroom, ios/Classes/Core, android/src/main/cpp/CHeadroom and
# for assets/calibration.json. Nothing in those places is edited by hand: when
# the core changes, run this again and commit the result. `--check` verifies
# the copies are identical to the core without writing anything.
#
#   tool/sync_native.sh            # copy
#   tool/sync_native.sh --check    # diff only; exit 1 on drift
#
# The core is found at ../../ relative to the plugin (the repository layout),
# or wherever HEADROOM_CORE points.

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CORE_DIR="${HEADROOM_CORE:-$(cd "$PLUGIN_DIR/../.." && pwd)}"
MODE="${1:-sync}"

if [ ! -f "$CORE_DIR/Package.swift" ] || [ ! -d "$CORE_DIR/Sources/CHeadroom" ]; then
    echo "error: the Headroom Swift package was not found at $CORE_DIR (set HEADROOM_CORE)" >&2
    exit 1
fi

# The probe layer: everything the native side needs to produce a ProbeReport.
PROBE_FILES=(
    Basis Quantity Interval BandwidthFigure ProbeReport Conditions MemoryInfo
    DeviceInfo Headroom HeadroomError ProbeOptions CPUTriadProbe BlockingWork
    Sysctl StreamKernel MetalBandwidthProbe StreamShaders Statistics
)
# The estimator layer is ported to Dart (lib/src/) and is never copied:
# Calibration.swift loads calibration.json through Bundle.module, which a
# CocoaPods target does not have.
ESTIMATOR_FILES=(Estimate MemoryFit Calibration ModelSpec)

C_SOURCES=("$CORE_DIR"/Sources/CHeadroom/*.c)
C_HEADER="$CORE_DIR/Sources/CHeadroom/include/headroom.h"
CALIBRATION="$CORE_DIR/Sources/Headroom/Resources/calibration.json"

drift=0

# place SRC DEST — copies in sync mode, compares in check mode.
place() {
    local src="$1" dest="$2"
    if [ "$MODE" = "--check" ]; then
        if [ ! -f "$dest" ] || ! cmp -s "$src" "$dest"; then
            echo "drift: $dest differs from $src"
            drift=1
        fi
    else
        mkdir -p "$(dirname "$dest")"
        cp "$src" "$dest"
    fi
}

# Every Swift file in the core must be accounted for, so a new file cannot be
# forgotten on either side.
for src in "$CORE_DIR"/Sources/Headroom/*.swift; do
    name="$(basename "$src" .swift)"
    listed=0
    for known in "${PROBE_FILES[@]}" "${ESTIMATOR_FILES[@]}"; do
        [ "$known" = "$name" ] && listed=1
    done
    if [ "$listed" = 0 ]; then
        echo "error: $name.swift is new in the core; add it to PROBE_FILES or ESTIMATOR_FILES" >&2
        exit 1
    fi
done

# 1. The C core, for both platforms.
for dest in "$PLUGIN_DIR/ios/Classes/CHeadroom" "$PLUGIN_DIR/android/src/main/cpp/CHeadroom"; do
    if [ "$MODE" != "--check" ]; then
        rm -rf "$dest"
    fi
    place "$C_HEADER" "$dest/include/headroom.h"
    for src in "${C_SOURCES[@]}"; do
        place "$src" "$dest/$(basename "$src")"
    done
done

# A module map so the core's `import CHeadroom` resolves inside the pod.
MODULEMAP="$PLUGIN_DIR/ios/Classes/CHeadroom/module.modulemap"
MODULEMAP_CONTENT='module CHeadroom {
    header "include/headroom.h"
    export *
}'
if [ "$MODE" = "--check" ]; then
    if [ ! -f "$MODULEMAP" ] || [ "$(cat "$MODULEMAP")" != "$MODULEMAP_CONTENT" ]; then
        echo "drift: $MODULEMAP"
        drift=1
    fi
else
    printf '%s\n' "$MODULEMAP_CONTENT" > "$MODULEMAP"
fi

# 2. The Swift probe layer.
CORE_DEST="$PLUGIN_DIR/ios/Classes/Core"
if [ "$MODE" != "--check" ]; then
    rm -rf "$CORE_DEST"
fi
for name in "${PROBE_FILES[@]}"; do
    src="$CORE_DIR/Sources/Headroom/$name.swift"
    if [ ! -f "$src" ]; then
        echo "error: $src is missing; update PROBE_FILES" >&2
        exit 1
    fi
    if grep -q "Bundle.module" "$src"; then
        echo "error: $name.swift references Bundle.module and cannot be copied into the pod" >&2
        exit 1
    fi
    place "$src" "$CORE_DEST/$name.swift"
done
if [ "$MODE" = "--check" ]; then
    for copied in "$CORE_DEST"/*.swift; do
        name="$(basename "$copied" .swift)"
        listed=0
        for known in "${PROBE_FILES[@]}"; do
            [ "$known" = "$name" ] && listed=1
        done
        if [ "$listed" = 0 ]; then
            echo "drift: $copied is not in PROBE_FILES"
            drift=1
        fi
    done
fi

# 3. The calibration rows the Dart estimator reads.
place "$CALIBRATION" "$PLUGIN_DIR/assets/calibration.json"

# 4. The Android side reports the core version by hand; keep it in step.
swift_version="$(sed -n 's/.*public static let version = "\([^"]*\)".*/\1/p' "$CORE_DIR/Sources/Headroom/Headroom.swift")"
kotlin_version="$(sed -n 's/.*const val CORE_VERSION = "\([^"]*\)".*/\1/p' "$PLUGIN_DIR/android/src/main/kotlin/com/umer9538/headroom/ProbeRunner.kt")"
if [ "$swift_version" != "$kotlin_version" ]; then
    echo "error: Headroom.version is $swift_version in the core but CORE_VERSION is $kotlin_version in ProbeRunner.kt" >&2
    exit 1
fi

if [ "$MODE" = "--check" ]; then
    if [ "$drift" = 0 ]; then
        echo "in sync with $CORE_DIR"
    fi
    exit "$drift"
fi
echo "synced from $CORE_DIR:"
echo "  ${#C_SOURCES[@]} C sources + header -> ios/Classes/CHeadroom, android/src/main/cpp/CHeadroom"
echo "  ${#PROBE_FILES[@]} Swift files -> ios/Classes/Core"
echo "  calibration.json -> assets/"
