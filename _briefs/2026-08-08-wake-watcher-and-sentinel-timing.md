# Brief: wake-watcher-and-sentinel-timing (2026-08-08)

**Author:** Antigravity · **Executor:** Antigravity · **Repo:** `/Users/gabrielblacher/GitHub & Coding Projects/hammerspoon-control`

## Objective
Two bugs in one pass:

1. **Wake watcher** — External display warmth fails to deactivate at sunrise after system sleep because `hs.timer` is paused by macOS while the Mac sleeps. Add an `hs.caffeinate.watcher` so any system/screen wake immediately re-evaluates gamma.

2. **Sentinel timing false-positive** — After "Apply & Reload", the Swift app reports "Runtime Inactive / Sentinel missing" even though `runtime.lua` loaded successfully. The `hs.reload()` IPC call kills the Mach port mid-call; the reply arrives corrupt or not at all (`CFMessagePort: dropping corrupt reply Mach message`). `reloadAndVerifyHealth` already handles this case correctly for the reload step (`isExpectedReloadTransportInvalidation`) and polls for a fresh sentinel with a 5-second timeout — but the timeout is being hit when Hammerspoon takes longer than 5 s to fully reload and publish `_G.hsControlSentinel`. The fix is to raise `timeoutSeconds` from `5.0` to `12.0` at all four `reloadAndVerifyHealth` call sites in `IntegrationService`.

## Context

### Bug 1 — Wake watcher
`status.json` showed `updateExternalDisplayColor()` last ran at 06:36:28 AM, just before sunrise at 06:37:16 AM. The Mac slept overnight. With no `hs.caffeinate.watcher`, no wake event triggered `updateExternalDisplayColor()`, so the night warmth gamma ramp stayed in GPU memory all morning.

### Bug 2 — Sentinel timing
Reproducer: user presses "Apply & Reload" while the Mac is under any non-trivial load. Menu bar shows:

```
Runtime Inactive
Diagnostic Reason: Sentinel missing (_G.hsControlSentinel is nil)
Reload command failed: CFMessagePort: dropping corrupt reply Mach message
```

`ProcessRunner.reloadAndVerifyHealth` (line 195–218) polls `queryRuntimeSentinel()` every 50 ms for `timeoutSeconds`. When Hammerspoon takes > 5 s to reload (common on first load or while indexing), the loop exits with "Sentinel missing" — a false negative. `runtime.lua` is correct and the sentinel was published; the query just arrived too early. Raising the timeout to 12 s is sufficient and safe (12 s × 50 ms polling = at most 240 IPC round-trips, each < 5 s timeout itself).

**No Swift logic changes are needed.** The poll-and-generation-check logic in `reloadAndVerifyHealth` is already correct. Only the timeout constant needs to increase.

## In scope
- `HammerspoonControl/Resources/runtime.lua` (Bug 1)
- `~/.hammerspoon/hammerspoon-control/runtime.lua` (Bug 1 — deployed copy)
- `HammerspoonControl/Services/IntegrationService.swift` (Bug 2 — four call sites)
- `_briefs/2026-08-08-wake-watcher-and-sentinel-timing.md`

## Out of scope
- Swift UI layouts or data models in `HammerspoonControl/Views` or `Models`.
- Command + scroll zoom logic.
- `ProcessRunner.swift` itself — the poll logic and `isExpectedReloadTransportInvalidation` are correct as-is.
- `ProcessRunnerTests.swift` — mock-based tests are unaffected by changing call-site constants in IntegrationService.
- Pause persistence across reloads (separate concern; `pauseUntilEpoch` is intentionally ephemeral).

## Acceptance criteria

### Bug 1 — Wake watcher
1. `runtime.lua` teardown block (lines 10–15) gains a `caffeinateWatcher` stop call alongside the existing four stops.
2. Inside the `if warmthEnabled then` branch, `hsControl.caffeinateWatcher` is created as an `hs.caffeinate.watcher` listening for `systemDidWake`, `screensDidWake`, and `screensDidUnlock`; it calls `updateExternalDisplayColor()` immediately (no debounce); it is started.
3. The watcher is NOT created in the `else` (warmth-disabled) branch.

### Bug 2 — Sentinel timeout
4. All four `reloadAndVerifyHealth(previousGeneration:..., timeoutSeconds: 5.0)` call sites in `IntegrationService.swift` use `timeoutSeconds: 12.0`:
   - `installIntegration` — line 151
   - `updateManagedRuntime` — line 214
   - `applySettings` — line 229
   - `retryReloadAndVerifyHealth` — line 235
5. Clean build, unit tests, `verify-safety.sh`, and prohibited-capability checks pass with zero errors.

## Implementation notes

### Bug 1
- Store the watcher on `hsControl.caffeinateWatcher` so the teardown block can stop it on the next reload.
- `screensDidUnlock` fires on screen-saver unlock — intentional; covers the case where the display was locked but not fully sleeping.
- Callback fires `updateExternalDisplayColor()` directly; no debounce wrapper needed for wake events.

### Bug 2
- `retryReloadAndVerifyHealth` (line 233–237) also calls `reloadAndVerifyHealth` with `timeoutSeconds: 5.0` — raise it to `12.0` as well so the "Retry Reload & Verify Runtime" button benefits from the same fix.
- Do NOT change any timeout values inside `ProcessRunner.swift` or any test files.

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

# 5. Spot-check wake watcher in deployed runtime
grep -n 'caffeinateWatcher' ~/.hammerspoon/hammerspoon-control/runtime.lua

# 6. Spot-check timeout values in IntegrationService
grep -n 'timeoutSeconds' '/Users/gabrielblacher/GitHub & Coding Projects/hammerspoon-control/HammerspoonControl/Services/IntegrationService.swift'
# Expected: all four occurrences show 12.0
```

## Report
The execution report must contain: files changed (paths and line ranges), the real output of every verification command above, deviations from this brief with reasons, and open questions.

## Execution report — 2026-08-08

### Files changed
- [HammerspoonControl/Resources/runtime.lua](file:///Users/gabrielblacher/GitHub%20&%20Coding%20Projects/hammerspoon-control/HammerspoonControl/Resources/runtime.lua#L12), [L258-L264](file:///Users/gabrielblacher/GitHub%20&%20Coding%20Projects/hammerspoon-control/HammerspoonControl/Resources/runtime.lua#L258-L264): Added `caffeinateWatcher` stop check to teardown block and created `caffeinateWatcher` listening for `systemDidWake`, `screensDidWake`, and `screensDidUnlock` inside `if warmthEnabled then` block.
- [~/.hammerspoon/hammerspoon-control/runtime.lua](file:///Users/gabrielblacher/.hammerspoon/hammerspoon-control/runtime.lua#L12), [L258-L264](file:///Users/gabrielblacher/.hammerspoon/hammerspoon-control/runtime.lua#L258-L264): Synchronized deployed runtime copy with resource template.
- [HammerspoonControl/Services/IntegrationService.swift](file:///Users/gabrielblacher/GitHub%20&%20Coding%20Projects/hammerspoon-control/HammerspoonControl/Services/IntegrationService.swift#L151), [L214](file:///Users/gabrielblacher/GitHub%20&%20Coding%20Projects/hammerspoon-control/HammerspoonControl/Services/IntegrationService.swift#L214), [L229](file:///Users/gabrielblacher/GitHub%20&%20Coding%20Projects/hammerspoon-control/HammerspoonControl/Services/IntegrationService.swift#L229), [L235](file:///Users/gabrielblacher/GitHub%20&%20Coding%20Projects/hammerspoon-control/HammerspoonControl/Services/IntegrationService.swift#L235): Updated `timeoutSeconds` parameter from `5.0` to `12.0` across all four `reloadAndVerifyHealth` call sites.

### Verification output

#### 1. Clean Build
```
Command: xcodebuild -project HammerspoonControl.xcodeproj -scheme HammerspoonControl -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/HammerspoonControlDerivedData CODE_SIGNING_ALLOWED=NO clean build
Output:
** BUILD SUCCEEDED **
```

#### 2. Run Unit Test Suite
```
Command: xcodebuild -project HammerspoonControl.xcodeproj -scheme HammerspoonControlTests -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/HammerspoonControlDerivedData CODE_SIGNING_ALLOWED=NO test
Output:
Test Suite 'All tests' passed at 2026-08-08 10:54:13.052.
	 Executed 42 tests, with 0 failures (0 unexpected) in 36.857 (36.879) seconds

** TEST SUCCEEDED **
```

#### 3. Run Safety & Fixture Script
```
Command: ./scripts/verify-safety.sh
Output:
============================================================
Hammerspoon Control Safety & Fixture Verification Script
============================================================
[1/8] Setting up isolated fixture root at /tmp/hammerspoon-control-safety-verify.pk7aAQ...
Known live baseline SHA: 75c40f52979bd6aa69160e3b9a59503793a8ff8f5d400e38ce0f71111a3fba67
[2/8] Running swift test suite against isolated environment...
✔ Automated tests succeeded.
[3/8] Verifying hs.configdir API regression (zero hs.configDir)...
✔ hs.configdir correctly used in IntegrationService.swift.
[4/8] Verifying changed-source refusal execution...
✔ Executed changed-source refusal test verified in test suite.
[5/8] Verifying JSON defaults & schema...
✔ settings.json lint passed.
[6/8] Verifying managed markers in runtime...
✔ IntegrationService contains managed bootstrap markers.
[7/8] Verifying no prohibited networking/analytics or shell-runner strings...
✔ No forbidden network, analytics, or shell-runner references found.
[8/9] Verifying failure injection and sentinel contract tests in test suite...
✔ Failure-injection, sentinel query, and exact command assertions verified.
[9/9] Verifying absence of live home directory writes during safety tests...
✔ Live ~/.hammerspoon/init.lua remained 100% untouched.
============================================================
✔ ALL SAFETY & FIXTURE CHECKS PASSED SUCCESSFULLY.
============================================================
```

#### 4. Prohibited Capability & Path Check
```
Command: rg -n 'URLSession|NWConnection|Analytics|Telemetry|https?://|Documents/|Downloads/|/bin/(ba)?sh|osascript' . --glob '!_briefs/**' --glob '!README.md' --glob '!AGENTS.md' --glob '!scripts/verify-safety.sh' --glob '!**/Info.plist'
Output:
(no output, exit code 1)
```

#### 5. Spot-check wake watcher in deployed runtime
```
Command: grep -n 'caffeinateWatcher' ~/.hammerspoon/hammerspoon-control/runtime.lua
Output:
12:  if _G.hsControlRuntime_old.caffeinateWatcher then pcall(function() _G.hsControlRuntime_old.caffeinateWatcher:stop() end) end
258:  hsControl.caffeinateWatcher = hs.caffeinate.watcher.new(function(event)
264:  hsControl.caffeinateWatcher:start()
```

#### 6. Spot-check timeout values in IntegrationService
```
Command: grep -n 'timeoutSeconds' '/Users/gabrielblacher/GitHub & Coding Projects/hammerspoon-control/HammerspoonControl/Services/IntegrationService.swift'
Output:
151:        let (reloadResult, healthResult, _) = processRunner.reloadAndVerifyHealth(previousGeneration: preGen, timeoutSeconds: 12.0)
214:        let (reloadResult, healthResult, _) = processRunner.reloadAndVerifyHealth(previousGeneration: preGen, timeoutSeconds: 12.0)
229:        let (reloadResult, healthResult, _) = processRunner.reloadAndVerifyHealth(previousGeneration: preGen, timeoutSeconds: 12.0)
235:        let (reloadResult, healthResult, _) = processRunner.reloadAndVerifyHealth(previousGeneration: preGen, timeoutSeconds: 12.0)
```

#### Whitespace check
```
Command: git diff --check
Output:
(no output, exit code 0)
```

### Deviations from brief
None.

### Open questions
None.
