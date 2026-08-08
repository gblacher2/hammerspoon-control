# Brief: fix-system-wake-gamma-update (2026-08-08)

**Author:** Claude | Codex · **Executor:** Antigravity · **Repo:** `/Users/gabrielblacher/GitHub & Coding Projects/hammerspoon-control`
**Reviewed:** Antigravity 2026-08-08

## Objective
Fix external display warmth failing to deactivate at sunrise after system sleep by adding a `hs.caffeinate.watcher` to immediately re-evaluate display color upon system and screen wake events.

## Context
Analysis of `~/.hammerspoon/hammerspoon-control/status.json` showed that `updateExternalDisplayColor()` last ran at **06:36:28 AM** (right before sunrise at 06:37:16 AM). When the Mac went to sleep or displays turned off overnight, macOS paused Hammerspoon background `hs.timer` execution. Because there was no system wake watcher (`hs.caffeinate.watcher`), `updateExternalDisplayColor()` was never re-triggered upon waking at daytime, leaving the night warmth gamma ramp active in GPU memory.

## In scope
- `HammerspoonControl/Resources/runtime.lua`
- `~/.hammerspoon/hammerspoon-control/runtime.lua`
- `_briefs/2026-08-08-fix-system-wake-gamma-update.md`

## Out of scope
- Swift UI layouts or data models in `HammerspoonControl/Views` or `Models`.
- Command + scroll zoom logic.

## Acceptance criteria
1. `runtime.lua` creates and starts an `hs.caffeinate.watcher` listening for `systemDidWake`, `screensDidWake`, and `screensDidUnlock` events.
2. Any system or display wake event immediately triggers `updateExternalDisplayColor()` — no debounce wrapper; wake events are infrequent and the function is cheap.
3. `_G.hsControlRuntime_old` idempotently stops previous `caffeinateWatcher` instances upon runtime reloads (add a `caffeinateWatcher` stop call to the existing teardown block at lines 10–15 of `runtime.lua`).
4. Clean build, unit tests, `verify-safety.sh`, and prohibited capability checks pass with zero errors.

## Implementation notes
- Place the `hs.caffeinate.watcher` inside the existing `if warmthEnabled then` branch (around line 248), alongside `screenWatcher` and `externalGammaTimer`. Do not add it to the `else` branch.
- `screensDidUnlock` fires on screen-saver unlock, not only on display power-on. This is intentional: it covers the common case where the Mac was left on overnight with the display locked but not sleeping.
- Store the watcher on `hsControl.caffeinateWatcher` so the teardown block can reach it on the next reload.

## Verification
```bash
cd '/Users/gabrielblacher/GitHub & Coding Projects/hammerspoon-control'

# 1. Clean Build
xcodebuild -project HammerspoonControl.xcodeproj -scheme HammerspoonControl -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/HammerspoonControlDerivedData CODE_SIGNING_ALLOWED=NO clean build

# 2. Run Unit Test Suite
xcodebuild -project HammerspoonControl.xcodeproj -scheme HammerspoonControlTests -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/HammerspoonControlDerivedData CODE_SIGNING_ALLOWED=NO test

# 3. Run Safety & Fixture Script
./scripts/verify-safety.sh

# 4. Prohibited Capability & Path Check
rg -n 'URLSession|NWConnection|Analytics|Telemetry|https?://|Documents/|Downloads/|/bin/(ba)?sh|osascript' . --glob '!_briefs/**' --glob '!README.md' --glob '!AGENTS.md' --glob '!scripts/verify-safety.sh' --glob '!**/Info.plist'
```

## Report
The execution report must contain: files changed (paths), the real output of every verification command, deviations from this brief with reasons, and open questions.
