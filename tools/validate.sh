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
cmake --build build 2>&1 | grep -E "error:" && fail "macOS build" || true
[ "${PIPESTATUS[0]}" = 0 ] || fail "macOS build"

step "iOS compile (Standalone + AUv3, unsigned)"
cmake -B build-ios -G Xcode -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 > /dev/null || fail "iOS configure"
PROJ=$(ls -d build-ios/*.xcodeproj | head -1)
TARGET=$(basename "$PROJ" .xcodeproj)
for SCHEME in "${TARGET}_Standalone" "${TARGET}_AUv3"; do
    xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Release \
        -destination "generic/platform=iOS" build \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -quiet 2>&1 \
        | grep -E "error:" && fail "iOS $SCHEME" || true
done

step "auval ($TYPE $CODE Enke)"
killall -9 AudioComponentRegistrar 2>/dev/null
auval -v "$TYPE" "$CODE" Enke 2>&1 | tail -2 | grep -q "SUCCEEDED" || fail "auval"
echo "AU VALIDATION SUCCEEDED"

step "pluginval (strictness 8)"
[ -x "$PV" ] || { echo "pluginval not installed — skipping (brew install --cask pluginval)"; exit 0; }
shopt -s nullglob
for PLUGIN in build/*_artefacts/Release/VST3/*.vst3; do
    "$PV" --strictness-level 8 --validate-in-process --skip-gui-tests \
        --timeout-ms 120000 "$PLUGIN" > /tmp/pv.log 2>&1 || { tail -20 /tmp/pv.log; fail "pluginval $PLUGIN"; }
    echo "PASS $(basename "$PLUGIN")"
done
if [ -n "$PRODUCT" ] && [ -d "$HOME/Library/Audio/Plug-Ins/Components/$PRODUCT.component" ]; then
    "$PV" --strictness-level 8 --validate-in-process --skip-gui-tests \
        --timeout-ms 120000 "$HOME/Library/Audio/Plug-Ins/Components/$PRODUCT.component" > /tmp/pv.log 2>&1 \
        || { tail -20 /tmp/pv.log; fail "pluginval AU"; }
    echo "PASS $PRODUCT.component"
fi

printf '\nAll automatable rungs green. Next: real hosts, real devices (TESTING.md §4).\n'
