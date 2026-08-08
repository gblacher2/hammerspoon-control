# Brief: control-center-widget-extension (2026-08-07)

**Author:** Antigravity (on behalf of Gabriel) · **Executor:** Antigravity · **Repo:** `/Users/gabrielblacher/GitHub & Coding Projects/hammerspoon-control`

## Objective
Add local offline `AppIntents` (`PauseWarmthIntent`, `ResumeWarmthIntent`, `ToggleWarmthIntent`) and a macOS `ControlWidget` implementation so users can trigger warmth controls directly from macOS Control Center and Shortcuts.

## Context
Following user request to control Hammerspoon warmth from system Control Center, we are implementing WidgetKit `ControlWidget` buttons/toggles and standard macOS `AppIntents`. All actions operate 100% locally by writing to `~/.hammerspoon/hammerspoon-control/settings.json` and triggering Hammerspoon reload.

## In scope
- `HammerspoonControl/Services/WarmthIntents.swift` (AppIntents for Pause, Resume, and Toggle warmth)
- `HammerspoonControl/Views/WarmthControlWidget.swift` (WidgetKit ControlCenter button & toggle widgets)
- `HammerspoonControl.xcodeproj/project.pbxproj` (Target configuration for AppIntents & WidgetKit references)
- `HammerspoonControlTests/` (Unit tests for AppIntents and settings mutations)

## Out of scope
- Remote API / network access (100% offline & local).
- Modifying init.lua backup/restore safety logic.

## Acceptance criteria
1. **AppIntents Implementation**: `PauseWarmthIntent`, `ResumeWarmthIntent`, and `ToggleWarmthIntent` are registered, performing local JSON settings mutations and executing Hammerspoon reload.
2. **Control Center Widget Support**: `ControlWidget` buttons/toggles are defined for Control Center integration.
3. **Automated Verification**: Clean build (`xcodebuild`), unit test suite (`HammerspoonControlTests`), safety script (`./scripts/verify-safety.sh`), and zero-network capability check pass cleanly.

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
- [WarmthIntents.swift](file:///Users/gabrielblacher/GitHub%20&%20Coding%20Projects/hammerspoon-control/HammerspoonControl/Services/WarmthIntents.swift) `[NEW]`: Added `PauseWarmthIntent`, `ResumeWarmthIntent`, and `ToggleWarmthIntent` offline AppIntents.
- [WarmthControlWidget.swift](file:///Users/gabrielblacher/GitHub%20&%20Coding%20Projects/hammerspoon-control/HammerspoonControl/Views/WarmthControlWidget.swift) `[NEW]`: Added `WarmthControlWidget` and `ToggleWarmthControlWidget` for macOS Control Center.
- [WarmthIntentsTests.swift](file:///Users/gabrielblacher/GitHub%20&%20Coding%20Projects/hammerspoon-control/HammerspoonControlTests/WarmthIntentsTests.swift) `[NEW]`: Added unit tests for AppIntents execution.
- [project.pbxproj](file:///Users/gabrielblacher/GitHub%20&%20Coding%20Projects/hammerspoon-control/HammerspoonControl.xcodeproj/project.pbxproj): Registered new source and test files in Xcode build target.
- `/Applications/HammerspoonControl.app`: Installed updated application bundle with AppIntents metadata.

### Real Verification Output

1. **xcodebuild clean build**:
```text
Writing Metadata.appintents
Metadata root: /tmp/HammerspoonControlDerivedData/Build/Products/Debug/HammerspoonControl.app/Contents/Resources/Metadata.appintents
** BUILD SUCCEEDED **
```

2. **xcodebuild test**:
```text
Test Suite 'WarmthIntentsTests' passed at 2026-08-07 19:43:22.919.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.585 (0.586) seconds
Test Suite 'All tests' passed at 2026-08-07 19:43:22.919.
	 Executed 42 tests, with 0 failures (0 unexpected) in 0.946 (0.959) seconds
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
- None. All AppIntents and ControlWidget components compiled cleanly and were registered into the app bundle.
