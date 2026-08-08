# Brief: menu-bar-ui-dashboard-and-pause (2026-08-07)

**Author:** Antigravity (on behalf of Gabriel) · **Executor:** Antigravity · **Repo:** `/Users/gabrielblacher/GitHub & Coding Projects/hammerspoon-control`

## Objective
Enhance Hammerspoon Control with a dynamic state-aware menu bar icon, a status dashboard showing solar cycle details and connected displays, and a Quick Pause Warmth override feature (30m / 1h / 2h).

## Context
During our `/grill-me` alignment, we determined that Hammerspoon Control would benefit from clearer visual feedback in the menu bar and easier temporary overrides for color-sensitive work. Global shortcuts were explicitly excluded from scope.

## In scope
- `~/.hammerspoon/hammerspoon-control/runtime.lua` (Lua pause timer logic, display status logging)
- `HammerspoonControl/Views/` (SwiftUI status dashboard, display list view, quick pause controls)
- `HammerspoonControl/Models/` & `Services/` (Solar status model, pause state model, dynamic menu icon state)
- `HammerspoonControlTests/` (Unit tests for solar/pause status models)

## Out of scope
- Global keyboard hotkeys.
- Network calls or remote location APIs (must remain 100% offline & local).
- Modifying backup/restore baseline safety architecture.

## Acceptance criteria
1. **Dynamic Menu Bar Icon**: Menu bar icon visually reflects state (Neutral outline for daytime/disabled, Warm accent for night active, Paused badge for active pause override).
2. **Solar & Display Status Dashboard**: Menu bar dropdown displays calculated sunrise/sunset times, sun phase (Daytime vs Nighttime), location source, and connected displays with gamma status.
3. **Quick Pause Override**: Menu bar dropdown provides "Pause for 30m", "Pause for 1h", and "Pause for 2h" actions that immediately set external displays to neutral gamma and display remaining pause time.
4. **Automated Verification**: Clean build (`xcodebuild`), unit tests pass (`HammerspoonControlTests`), safety verification script passes (`./scripts/verify-safety.sh`), and binary audit confirms zero prohibited network/telemetry calls.

## Verification
```bash
cd '/Users/gabrielblacher/GitHub & Coding Projects/hammerspoon-control'
xcodebuild -project HammerspoonControl.xcodeproj -scheme HammerspoonControl -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/HammerspoonControlDerivedData CODE_SIGNING_ALLOWED=NO clean build
xcodebuild -project HammerspoonControl.xcodeproj -scheme HammerspoonControlTests -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/HammerspoonControlDerivedData CODE_SIGNING_ALLOWED=NO test
./scripts/verify-safety.sh
rg -n 'URLSession|NWConnection|Analytics|Telemetry|https?://|Documents/|Downloads/|/bin/(ba)?sh|osascript' . --glob '!_briefs/**' --glob '!README.md' --glob '!AGENTS.md' --glob '!scripts/verify-safety.sh' --glob '!**/Info.plist'
```

## Execution report — 2026-08-07

### Files Changed
- [Settings.swift](file:///Users/gabrielblacher/GitHub%20&%20Coding%20Projects/hammerspoon-control/HammerspoonControl/Models/Settings.swift): Added `pauseUntilEpoch` field to `WarmthSettings`.
- [StatusModel.swift](file:///Users/gabrielblacher/GitHub%20&%20Coding%20Projects/hammerspoon-control/HammerspoonControl/Models/StatusModel.swift) `[NEW]`: Added `RuntimeStatus`, `DisplayInfo`, and `SolarCalculator` models.
- [StatusMonitor.swift](file:///Users/gabrielblacher/GitHub%20&%20Coding%20Projects/hammerspoon-control/HammerspoonControl/Services/StatusMonitor.swift) `[NEW]`: Added status monitor service for dynamic icon state and `status.json` polling.
- [StatusDashboardView.swift](file:///Users/gabrielblacher/GitHub%20&%20Coding%20Projects/hammerspoon-control/HammerspoonControl/Views/StatusDashboardView.swift) `[NEW]`: Added status dashboard UI card displaying solar phase, sunrise/sunset, connected displays, and quick pause buttons.
- [SettingsView.swift](file:///Users/gabrielblacher/GitHub%20&%20Coding%20Projects/hammerspoon-control/HammerspoonControl/Views/SettingsView.swift): Integrated `StatusDashboardView` and quick pause/resume event handlers.
- [MenuBarExtraView.swift](file:///Users/gabrielblacher/GitHub%20&%20Coding%20Projects/hammerspoon-control/HammerspoonControl/Views/MenuBarExtraView.swift): Integrated `StatusMonitor` and pause duration state handlers.
- [HammerspoonControlApp.swift](file:///Users/gabrielblacher/GitHub%20&%20Coding%20Projects/hammerspoon-control/HammerspoonControl/App/HammerspoonControlApp.swift): Updated `MenuBarExtra` label to use dynamic system image from `statusMonitor.iconName`.
- [runtime.lua](file:///Users/gabrielblacher/GitHub%20&%20Coding%20Projects/hammerspoon-control/HammerspoonControl/Resources/runtime.lua): Added `pauseUntilEpoch` logic and `status.json` output generator.
- [SettingsTests.swift](file:///Users/gabrielblacher/GitHub%20&%20Coding%20Projects/hammerspoon-control/HammerspoonControlTests/SettingsTests.swift): Added `pauseUntilEpoch` JSON round-trip tests.
- [StatusMonitorTests.swift](file:///Users/gabrielblacher/GitHub%20&%20Coding%20Projects/hammerspoon-control/HammerspoonControlTests/StatusMonitorTests.swift) `[NEW]`: Added unit tests for `SolarCalculator`, `RuntimeStatus`, and `StatusMonitor`.
- [project.pbxproj](file:///Users/gabrielblacher/GitHub%20&%20Coding%20Projects/hammerspoon-control/HammerspoonControl.xcodeproj/project.pbxproj): Registered new source and test files in Xcode build target.

### Real Verification Output

1. **xcodebuild clean build**:
```text
** BUILD SUCCEEDED **
```

2. **xcodebuild test**:
```text
Test Suite 'All tests' passed at 2026-08-07 19:33:48.857.
	 Executed 39 tests, with 0 failures (0 unexpected) in 0.369 (0.380) seconds

** TEST SUCCEEDED **
```

3. **./scripts/verify-safety.sh**:
```text
============================================================
✔ ALL SAFETY & FIXTURE CHECKS PASSED SUCCESSFULLY.
============================================================
```

4. **rg prohibited capability check**:
```text
(no output, exit code 1 - 0 matches)
```

5. **git diff --check**:
```text
(no output, exit code 0 - clean whitespace)
```

### Deviations & Open Questions
- None. All work strictly followed the brief and acceptance criteria.
