# Brief: fix-warmth-slider-and-sunset-sunrise (2026-08-07)

**Author:** Claude | Codex · **Executor:** Antigravity · **Repo:** `/Users/gabrielblacher/GitHub & Coding Projects/hammerspoon-control`

## Objective
Fix external display color temperature slider updates and automatic sunset/sunrise warmth activation and deactivation in the Hammerspoon managed runtime (`runtime.lua`).

## Context
Investigation of the current `runtime.lua` implementation revealed two key bugs:
1. `hs.location.sunrise(location, offset)` and `hs.location.sunset(location, offset)` were called with `location` (a table containing `{latitude = ..., longitude = ...}`) as the first parameter instead of numeric `latitude` and `longitude`. This caused `hs.location.sunrise` and `sunset` in Hammerspoon to return `nil`, forcing `isNighttime()` to always evaluate to `false`. As a result:
   - External display warmth was never applied in `sunsetToSunrise` mode, making the warmth slider appear ineffective even after clicking "Apply & Reload".
   - Sunrise and sunset automatic scheduling failed to activate/deactivate warmth based on actual time.
2. In `applyGamma()`, applying neutral gamma passed `{red = 1.0, green = 1.0, blue = 1.0}` and `{red = 0.0, green = 0.0, blue = 0.0}` into `screen:setGamma(whitepoint, blackpoint)`. Passing custom linear table values instead of invoking `screen:setGamma()` without arguments does not clear custom display gamma tables or restore the monitor's native ICC profile.

## In scope
- `HammerspoonControl/Resources/runtime.lua`
- `~/.hammerspoon/hammerspoon-control/runtime.lua`
- `_briefs/2026-08-07-fix-warmth-slider-and-sunset-sunrise.md`

## Out of scope
- Swift UI layouts, settings schemas, or data models in `HammerspoonControl/Models` or `Views`.
- `IntegrationService.swift` or `ProcessRunner.swift` logic outside of runtime file alignment.
- Command + scroll zoom logic.

## Acceptance criteria
1. `runtime.lua` unpacks `location.latitude` and `location.longitude` as numbers when calling `hs.location.sunrise` and `hs.location.sunset`.
2. `applyGamma()` in `runtime.lua` invokes `screen:setGamma()` with no arguments when setting neutral gamma, properly clearing custom hardware gamma ramps and restoring default display ICC profiles.
3. In `sunsetToSunrise` schedule mode, `isNighttime()` correctly identifies nighttime vs daytime relative to local sunrise and sunset timestamps.
4. Color temperature slider changes take effect on external displays when warmth is active, and warmth automatically turns off at sunrise.
5. All verification commands (`xcodebuild` clean build, `xcodebuild` test suite, `./scripts/verify-safety.sh`, and prohibited capability checks) pass with zero errors.

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

## Execution report — 2026-08-07

### Files changed
- [`HammerspoonControl/Resources/runtime.lua`](file:///Users/gabrielblacher/GitHub%20&%20Coding%20Projects/hammerspoon-control/HammerspoonControl/Resources/runtime.lua)
- [`~/.hammerspoon/hammerspoon-control/runtime.lua`](file:///Users/gabrielblacher/.hammerspoon/hammerspoon-control/runtime.lua)
- [`_briefs/2026-08-07-fix-warmth-slider-and-sunset-sunrise.md`](file:///Users/gabrielblacher/GitHub%20&%20Coding%20Projects/hammerspoon-control/_briefs/2026-08-07-fix-warmth-slider-and-sunset-sunrise.md)

### Verification output

#### 1. Clean Build
```
Command: xcodebuild -project HammerspoonControl.xcodeproj -scheme HammerspoonControl -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/HammerspoonControlDerivedData CODE_SIGNING_ALLOWED=NO clean build
Exit Code: 0
Output snippet:
Touch /tmp/HammerspoonControlDerivedData/Build/Products/Debug/HammerspoonControl.app (in target 'HammerspoonControl' from project 'HammerspoonControl')
    cd /Users/gabrielblacher/GitHub\ \&\ Coding\ Projects/hammerspoon-control
    /usr/bin/touch -c /tmp/HammerspoonControlDerivedData/Build/Products/Debug/HammerspoonControl.app

RegisterWithLaunchServices /tmp/HammerspoonControlDerivedData/Build/Products/Debug/HammerspoonControl.app (in target 'HammerspoonControl' from project 'HammerspoonControl')
    cd /Users/gabrielblacher/GitHub\ \&\ Coding\ Projects/hammerspoon-control
    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted /tmp/HammerspoonControlDerivedData/Build/Products/Debug/HammerspoonControl.app

** BUILD SUCCEEDED **
```

#### 2. Unit Test Suite
```
Command: xcodebuild -project HammerspoonControl.xcodeproj -scheme HammerspoonControlTests -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/HammerspoonControlDerivedData CODE_SIGNING_ALLOWED=NO test
Exit Code: 0
Output snippet:
Test Suite 'HammerspoonControlTests.xctest' passed at 2026-08-07 19:27:24.162.
	 Executed 35 tests, with 0 failures (0 unexpected) in 0.363 (0.379) seconds
Test Suite 'All tests' passed at 2026-08-07 19:27:24.162.
	 Executed 35 tests, with 0 failures (0 unexpected) in 0.363 (0.380) seconds
2026-08-07 19:27:24.447 xcodebuild[70538:13837887] [MT] IDETestOperationsObserverDebug: 2.164 elapsed -- Testing started completed.
2026-08-07 19:27:24.447 xcodebuild[70538:13837887] [MT] IDETestOperationsObserverDebug: 0.000 sec, +0.000 sec -- start
2026-08-07 19:27:24.447 xcodebuild[70538:13837887] [MT] IDETestOperationsObserverDebug: 2.164 sec, +2.164 sec -- end

Test session results, code coverage, and logs:
	/tmp/HammerspoonControlDerivedData/Logs/Test/Test-HammerspoonControlTests-2026.08.07_19-27-19--0300.xcresult

** TEST SUCCEEDED **
```

#### 3. Safety & Fixture Script
```
Command: ./scripts/verify-safety.sh
Exit Code: 0
Output:
============================================================
Hammerspoon Control Safety & Fixture Verification Script
============================================================
[1/8] Setting up isolated fixture root at /tmp/hammerspoon-control-safety-verify.YHM2dz...
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
Exit Code: 1
Output: (zero matches found)
```

#### 5. Whitespace Check
```
Command: git diff --check
Exit Code: 0
Output: (zero whitespace warnings)
```

### Deviations from brief
None.

### Open questions
None.

