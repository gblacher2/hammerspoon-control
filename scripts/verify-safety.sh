#!/bin/bash
set -euo pipefail

echo "============================================================"
echo "Hammerspoon Control Safety & Fixture Verification Script"
echo "============================================================"

TMP_DIR=$(mktemp -d /tmp/hammerspoon-control-safety-verify.XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "[1/8] Setting up isolated fixture root at $TMP_DIR..."
mkdir -p "$TMP_DIR/.hammerspoon"

KNOWN_BASELINE_PATH="/Users/gabrielblacher/.hammerspoon/init.lua"
KNOWN_BASELINE_SHA=$(shasum -a 256 "$KNOWN_BASELINE_PATH" | awk '{print $1}')
echo "Known live baseline SHA: $KNOWN_BASELINE_SHA"

cp "$KNOWN_BASELINE_PATH" "$TMP_DIR/.hammerspoon/init.lua"

echo "[2/8] Running swift test suite against isolated environment..."
export HAMMERSPOON_CONTROL_CONFIG_DIR="$TMP_DIR/.hammerspoon"
cd "/Users/gabrielblacher/GitHub & Coding Projects/hammerspoon-control"

xcodebuild -project HammerspoonControl.xcodeproj -scheme HammerspoonControlTests -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/HammerspoonControlDerivedData CODE_SIGNING_ALLOWED=NO test > "$TMP_DIR/test_output.log" 2>&1

if grep -q "\*\* TEST SUCCEEDED \*\*" "$TMP_DIR/test_output.log"; then
    echo "✔ Automated tests succeeded."
else
    echo "❌ Automated tests failed. Log output:"
    cat "$TMP_DIR/test_output.log"
    exit 1
fi

echo "[3/8] Verifying hs.configdir API regression (zero hs.configDir)..."
CONFIG_DIR_WRONG_CASE=$(rg -n 'hs\.configDir' HammerspoonControl/ --glob '!_briefs/**' || true)
if [ -n "$CONFIG_DIR_WRONG_CASE" ]; then
    echo "❌ Defect found! hs.configDir found in codebase:"
    echo "$CONFIG_DIR_WRONG_CASE"
    exit 1
fi

CONFIG_DIR_CORRECT_CASE=$(grep -c 'hs\.configdir' HammerspoonControl/Services/IntegrationService.swift)
if [ "$CONFIG_DIR_CORRECT_CASE" -ge 1 ]; then
    echo "✔ hs.configdir correctly used in IntegrationService.swift."
else
    echo "❌ hs.configdir missing in IntegrationService.swift."
    exit 1
fi

echo "[4/8] Verifying changed-source refusal execution..."
if grep -q "testInstallRefusesIfFileChangesRightBeforeInstallAndLeavesInitUntouched" "$TMP_DIR/test_output.log"; then
    echo "✔ Executed changed-source refusal test verified in test suite."
else
    echo "❌ Changed-source refusal test did not execute."
    exit 1
fi

echo "[5/8] Verifying JSON defaults & schema..."
DEFAULT_JSON="HammerspoonControl/Resources/settings.json"
python3 -m json.tool "$DEFAULT_JSON" > /dev/null
echo "✔ settings.json lint passed."

echo "[6/8] Verifying managed markers in runtime..."
BOOTSTRAP_MARKERS=$(grep -c "BEGIN Hammerspoon Control" HammerspoonControl/Services/IntegrationService.swift)
if [ "$BOOTSTRAP_MARKERS" -ge 1 ]; then
    echo "✔ IntegrationService contains managed bootstrap markers."
else
    echo "❌ Managed bootstrap markers missing in IntegrationService."
    exit 1
fi

echo "[7/8] Verifying no prohibited networking/analytics or shell-runner strings..."
FORBIDDEN_HITS=$(rg -n 'URLSession|NWConnection|Analytics|Telemetry|https?://|Documents/|Downloads/|/bin/(ba)?sh|osascript' . --glob '!_briefs/**' --glob '!README.md' --glob '!AGENTS.md' --glob '!scripts/verify-safety.sh' --glob '!**/Info.plist' || true)

if [ -n "$FORBIDDEN_HITS" ]; then
    echo "❌ Found forbidden references:"
    echo "$FORBIDDEN_HITS"
    exit 1
else
    echo "✔ No forbidden network, analytics, or shell-runner references found."
fi

echo "[8/9] Verifying failure injection and sentinel contract tests in test suite..."
if grep -q "testFailureInjectionAtWriteStagesLeavesInitLuaRecoverableAndStateNotInstalled" "$TMP_DIR/test_output.log" && \
   grep -q "testFailureInjectionAtUpdateStagesPreservesPreviousValidState" "$TMP_DIR/test_output.log" && \
   grep -q "testInactiveToHealthyTransition" "$TMP_DIR/test_output.log" && \
   grep -q "testRunHsReloadAssertsExactExecutableAndArguments" "$TMP_DIR/test_output.log"; then
    echo "✔ Failure-injection, sentinel query, and exact command assertions verified."
else
    echo "❌ Missing failure-injection or sentinel contract test executions."
    exit 1
fi

echo "[9/9] Verifying absence of live home directory writes during safety tests..."
LIVE_INIT_SHA=$(shasum -a 256 "$KNOWN_BASELINE_PATH" | awk '{print $1}')
if [ "$LIVE_INIT_SHA" == "$KNOWN_BASELINE_SHA" ]; then
    echo "✔ Live ~/.hammerspoon/init.lua remained 100% untouched."
else
    echo "❌ Live ~/.hammerspoon/init.lua was modified during tests!"
    exit 1
fi

echo "============================================================"
echo "✔ ALL SAFETY & FIXTURE CHECKS PASSED SUCCESSFULLY."
echo "============================================================"
