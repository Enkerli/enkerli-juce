#!/bin/bash
# The automatable rungs of the testing ladder (TESTING.md), one command:
#   build matrix (macOS + iOS compile) → auval → pluginval.
#
#   tools/validate.sh <project-dir> <aumi|aumu> <PLUGIN_CODE> [ProductName]
#
# Exits non-zero on the first failing rung. Device testing is yours.
set -uo pipefail

DIR="${1:?project dir}"
TYPE="${2:?aumi|aumu}"
CODE="${3:?4-char plugin code}"
PRODUCT="${4:-}"
PV="/Applications/pluginval.app/Contents/MacOS/pluginval"
cd "$DIR"

step() { printf '\n— %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; exit 1; }

step "macOS build (AU/VST3/Standalone)"
cmake -B build -DCMAKE_BUILD_TYPE=Release > /dev/null || fail "cmake configure"
cmake --build build 2>&1 | grep -E "error:|\[ERROR\]" && fail "macOS build" || true
[ "${PIPESTATUS[0]}" = 0 ] || fail "macOS build"
# A "successful" build can still leave a hollow bundle (stale WebUI DEPENDS
# glob, interrupted assembly) — auval would then validate the previously
# INSTALLED component and lie. Assert the fresh VST3 actually has a binary.
shopt -s nullglob
for _b in build/*_artefacts/Release/VST3/*.vst3; do
    find "$_b/Contents/MacOS" -type f -size +0 2>/dev/null | grep -q . \
        || fail "hollow bundle (no binary): $_b"
done
shopt -u nullglob

step "iOS compile (Standalone + AUv3, unsigned)"
cmake -B build-ios -G Xcode -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 > /dev/null || fail "iOS configure"
PROJ=$(ls -d build-ios/*.xcodeproj | head -1)
TARGET=$(basename "$PROJ" .xcodeproj)
for SCHEME in "${TARGET}_Standalone" "${TARGET}_AUv3"; do
    xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Release \
        -destination "generic/platform=iOS" build \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -quiet 2>&1 \
        | grep -E "error:|\[ERROR\]" && fail "iOS $SCHEME" || true
    [ "${PIPESTATUS[0]}" = 0 ] || fail "iOS $SCHEME (xcodebuild exit)"
done

step "auval -strict ($TYPE $CODE Enke)"
killall -9 AudioComponentRegistrar 2>/dev/null
# -strict here (in-process, direct v2 access) gives us the full strict AU
# coverage that pluginval's own auval sub-test would — but fast. pluginval
# drives the AU through the AUAudioUnit bridge (every param set round-trips a
# dispatch/observation queue); for a plugin with hundreds of params + a slow
# constructor that push its auval sub-test past its 2-min budget (Vane hit
# exactly this). Running strict auval natively sidesteps the bridge entirely.
auval -strict -v "$TYPE" "$CODE" Enke 2>&1 | tail -2 | grep -q "SUCCEEDED" || fail "auval"
echo "AU VALIDATION SUCCEEDED"

step "pluginval (strictness 8)"
[ -x "$PV" ] || { echo "pluginval not installed — skipping (brew install --cask pluginval)"; exit 0; }
shopt -s nullglob
for PLUGIN in build/*_artefacts/Release/VST3/*.vst3; do
    "$PV" --strictness-level 8 --validate-in-process --skip-gui-tests \
        --timeout-ms 120000 "$PLUGIN" > /tmp/pv.log 2>&1 || { tail -20 /tmp/pv.log; fail "pluginval $PLUGIN"; }
    echo "PASS $(basename "$PLUGIN")"
done
# NOTE: we deliberately do NOT run pluginval on the installed .component.
# pluginval's AU validation includes an internal `auval -strict` sub-test that
# it drives through the AUAudioUnit bridge. That path is pathologically slow
# for plugins with large parameter trees and/or slow constructors — Vane's ran
# past pluginval's 2-min timeout every time, while the SAME `auval -strict`
# run natively (the rung above) passes in ~30s. The AU is therefore covered by
# native strict auval; pluginval still runs against the VST3 above for its own
# (non-auval) test suite. Re-adding an AU-component pluginval rung just
# reintroduces the bridge-induced timeout — don't.

printf '\nAll automatable rungs green. Next: real hosts, real devices (TESTING.md §4).\n'
