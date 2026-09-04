# AGENTS.md — Hammerspoon Control Development Guidelines

## Build & verify

To build and verify the `HammerspoonControl` app and test targets:

Run from the repository root:

```bash
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
- **Gamma Reset (`hs.screen:setGamma`)**: `screen:setGamma` requires both `whitepoint` and `blackpoint` component tables. For an external-display-only neutral restore, use `{red=1, green=1, blue=1}` and `{red=0, green=0, blue=0}`; Hammerspoon reapplies the original gamma table it captured for that display. Do not pass empty tables (missing components become zero) or omit either argument. `hs.screen.restoreGamma()` restores ColorSync defaults globally, so do not use it inside the external-only loop.

## GitHub workflow and agent guardrails

- GitHub is the canonical system of record. Record durable decisions, acceptance
  criteria, implementation state, review findings, and validation in the repository,
  Issues, or pull requests rather than only in an AI conversation.
- Meaningful work uses an Issue or equivalent complete PR context, a scoped branch,
  an early draft PR, review comments, verification, and a final `READY FOR HUMAN` state.
- Use `feat/`, `fix/`, `refactor/`, or `chore/` branch prefixes. Do not implement normal
  feature work directly on `main` and do not merge without human authorization.
- Inspect the existing architecture and `git status` before changing files. Preserve
  unrelated local work and prefer minimal, scoped modifications.
- Do not suppress type or lint failures, replace working implementations unnecessarily,
  introduce dependencies without justification, or alter unrelated code.
- Never commit secrets, credentials, `.env` values, personal data, local databases,
  logs, or machine-specific state. Commit reconstruction-safe examples and setup docs.
- Push meaningful checkpoints and keep the PR accurate so a fresh agent can continue
  from GitHub alone.
