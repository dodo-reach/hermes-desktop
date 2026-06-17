# Hermes UI Codex Capsule

## Project
- SwiftPM workspace for Hermes Desktop plus the native iOS client.
- Active mobile work normally happens on `codex/mobile-v1`.
- Package targets: `HermesDesktop`, `HermesPhoneKit`, `HermesDesktopTests`, `HermesPhoneKitTests`.
- iPhone app project: `Apps/HermesPhone/HermesPhone.xcodeproj`, scheme `HermesPhone`.

## Commands
- Run tests: `./scripts/run-tests.sh`
- Build macOS app bundle: `./scripts/build-macos-app.sh`
- Verify release: `./scripts/verify-release.sh`
- Package GitHub release: `./scripts/package-github-release.sh`
- Build only the phone package target quickly: `swift build --target HermesPhoneKit`
- Physical iPhone build/install uses the `HermesPhone` Xcode project. Prefer the connected device id discovered by `xcrun devicectl list devices`.

## Working Rules
- Check `git status --short --branch` before editing; preserve user changes.
- Keep mobile UI work restrained and chat-first. Do not turn the app into a session-management dashboard.
- Preserve fast resume, cached transcripts, typing during warmup, session lineage, and reasoning/tool ticker separation.
- Treat gateway/session ids carefully; do not confuse live gateway session ids with durable transcript/session lineage ids.
- Do not touch `Vendor/` unless the bug is clearly inside vendored code.

## Verification
- For shared Swift logic, run `./scripts/run-tests.sh`.
- For mobile chat/UI changes, also build `HermesPhoneKit`; if the user asks to test on device, build and install the `HermesPhone` scheme.
- For macOS release work, run `./scripts/verify-release.sh` after packaging.
