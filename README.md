# Hammerspoon Control

Native macOS menu-bar app (**Hammerspoon Control**, Bundle ID `com.gabrielblacher.HammerspoonControl`) built in Swift/SwiftUI for managing Hammerspoon external-display warmth and Command-plus-scroll zoom settings safely without editing Lua files directly.

> **Local-Only Guarantee**: This app contains no network code, no analytics/telemetry SDKs, no external dependencies, and no remote updates. It operates purely on local filesystem paths within `~/.hammerspoon/hammerspoon-control/`.

---

## Architecture & Integration Design

- **App Model**: Native macOS SwiftUI menu-bar app using `MenuBarExtra` window style.
- **Managed Settings**: Stores structured configuration as JSON at `~/.hammerspoon/hammerspoon-control/settings.json`.
- **Managed Runtime**: Executes isolated Lua runtime logic at `~/.hammerspoon/hammerspoon-control/runtime.lua`.
- **Installation Manifest**: Records backup location and original baseline SHA-256 fingerprint at `~/.hammerspoon/hammerspoon-control/install.json`.
- **Defensive Bootstrap**: Replaces unmanaged `~/.hammerspoon/init.lua` with a lightweight `pcall` wrapper that enables IPC and safely loads `runtime.lua`.

---

## Safety Guardrails & First-Run Behavior

1. **Read-Only First Launch**: Launching the app performs read-only state inspection. No files under `~/.hammerspoon` are changed until explicit user action (**Install integration**).
2. **Fingerprint Verification**: Automatic migration is offered only if the existing `init.lua` matches the known unmanaged baseline (`b90f23843142261c456194152e8edd82455c8d5c76208824ee0c17ad80610324`). If the file was edited or contains unrecognized code, migration is safely refused.
3. **Collision-Safe Backup**: Installing integration creates a timestamped backup (`init.lua.codex-backup-YYYYMMDD-HHMMSS`). Historic backups (`init.lua.codex-backup-*`) are never deleted or modified.
4. **Byte-Exact Restoration**: **Restore pre-app configuration** verifies the backup hash before restoring, creates a safety pre-restore backup (`init.lua.pre-restore-backup-YYYYMMDD-HHMMSS`), and restores the exact original baseline bytes.

---

## Development Environment Override

For isolated acceptance testing without affecting live `~/.hammerspoon`, set the debug environment variable:

```bash
export HAMMERSPOON_CONTROL_CONFIG_DIR="/tmp/my-fake-hammerspoon"
```

---

## Build & Test Commands

```bash
cd '/Users/gabrielblacher/GitHub & Coding Projects/hammerspoon-control'

# Clean build
xcodebuild -project HammerspoonControl.xcodeproj -scheme HammerspoonControl -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/HammerspoonControlDerivedData CODE_SIGNING_ALLOWED=NO clean build

# Run unit tests
xcodebuild -project HammerspoonControl.xcodeproj -scheme HammerspoonControlTests -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/HammerspoonControlDerivedData CODE_SIGNING_ALLOWED=NO test

# Run safety verification script
./scripts/verify-safety.sh
```
