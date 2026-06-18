# Mobile Branch Policy

This document makes the branch split explicit.

`main` is the desktop product branch. `codex/mobile-v1` is the mobile product branch.

The split is intentional. It is not just historical cleanup.

## Why Branches Stay Separate

Hermes Desktop and HermesPhone share the same product domain, but they do not share the same runtime model.

Desktop:

- ships from GitHub Releases as a zipped macOS app.
- uses `/usr/bin/ssh`.
- uses `Process` and local SSH configuration.
- relies on the user's macOS SSH agent, known hosts, and shell environment.

Mobile:

- ships through App Store review.
- uses Citadel for native SSH.
- stores credentials in Keychain.
- owns host-key trust prompts inside the app.
- must work without local SSH config, `Process`, or macOS shell assumptions.

Because of that, a single shared core would currently force awkward abstractions around the most important boundary: remote execution.

## Core Compatibility Map

These files are currently safe to compare or port manually when remote Hermes behavior changes:

- `CronJobModels.swift`
- `RemoteDiscovery.swift`
- `RemoteTrackedFile.swift`
- `SharedModelTypes.swift`
- `SkillLaunchability.swift`
- `SkillModels.swift`
- `FileEditorService.swift`
- `RemoteHermesService.swift`
- `SkillBrowserService.swift`
- `DateFormatters.swift`
- `RemotePythonScript.swift`
- `ShellCommandQuoting.swift`

These files are intentionally divergent and must not be synchronized blindly:

- `ConnectionProfile.swift`
- `SessionModels.swift`
- `WorkspaceFileModels.swift`
- `CronBrowserService.swift`
- `SessionBrowserService.swift`
- desktop `SSHTransport.swift`
- mobile `CoreBuildShims.swift`
- desktop `HermesGatewayChatService.swift`
- mobile management stays request/response over the existing SSH transport; do
  not restore the removed native chat gateway runtime.

## Change Workflow

Mobile-only changes:

1. Branch from `codex/mobile-v1`.
2. Touch `Apps/HermesPhone`, `Sources/HermesPhoneKit`, `Tests/HermesPhoneKitTests`, or mobile docs.
3. Run mobile build verification and relevant tests.
4. Merge or push back to `codex/mobile-v1`.

Desktop-only changes:

1. Branch from `main`.
2. Touch desktop code and desktop docs only.
3. Run desktop tests and packaging checks.
4. Release through GitHub Releases.

Remote protocol or data-shape changes:

1. Identify whether the change affects desktop, mobile, or both.
2. Port the semantic change, not necessarily the file diff.
3. Add or update tests on each affected branch.
4. Keep branch-specific transport behavior intact.

## Merge Rules

- Avoid routine merges from `main` into `codex/mobile-v1`.
- Avoid routine merges from `codex/mobile-v1` into `main`.
- Use cherry-pick only for narrow commits that are known to apply to the target branch.
- For model/service drift, compare behavior and tests before copying code.
- Never assume identical filenames imply identical responsibilities.

## Release Hygiene

The mobile branch should stay App Store oriented:

- no DerivedData, SwiftPM cache, or local logs.
- no private credentials, keys, certificates, or provisioning profiles.
- no desktop release packaging changes unless needed to keep the package manifest valid.
- no vendored examples/tests/CI from third-party libraries unless required by the mobile build.

If a cleanup does not help mobile release, mobile maintenance, or mobile debugging, leave it out.
