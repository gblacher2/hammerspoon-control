# AGENTS.md — Hammerspoon Control Development Guidelines

## Build & verify

To build and verify the `HammerspoonControl` app and test targets:

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

## Runtime (`runtime.lua`) API Guidelines

- **Location API (`hs.location`)**: `hs.location.sunrise` and `hs.location.sunset` require separate numeric arguments `(latitude, longitude, offset)`. Never pass a location table `{latitude=..., longitude=...}` as argument 1, as it will return `nil`.
- **Gamma Reset (`hs.screen:setGamma`)**: To restore default monitor color balance and ICC profile, call `screen:setGamma()` with no parameters. Do not pass `{red=1, green=1, blue=1}`, which sets a linear gamma ramp overlay instead of clearing the hardware gamma table.

