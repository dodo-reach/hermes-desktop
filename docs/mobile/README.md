# HermesPhone Mobile Branch

`codex/mobile-v1` is the long-lived product branch for the iOS app.

`main` remains the public desktop release branch for Hermes Desktop. The two branches intentionally have different release paths, different users, and some incompatible runtime assumptions.

## What Lives Here

- `Apps/HermesPhone`: Xcode iOS app project and app assets.
- `Sources/HermesPhoneKit`: iOS app shell, stores, read-only sessions, Kanban, SSH management services, and secondary utilities.
- `Tests/HermesPhoneKitTests`: focused tests for mobile-only infrastructure.
- `Vendor/Citadel`: minimal vendored SSH library source used by the iOS app.

## Operating Rule

Do not treat `codex/mobile-v1` as a temporary feature branch over `main`.

Treat it as the mobile product branch:

- Mobile-only changes start from and land on `codex/mobile-v1`.
- Desktop-only changes start from and land on `main`.
- Changes to remote Hermes formats or behavior are evaluated explicitly for both branches.
- Do not merge `main` into `codex/mobile-v1` just to keep histories similar.
- Do not extract shared core code unless there is a concrete release or maintenance payoff.

The detailed policy is in [branch-policy.md](branch-policy.md).

## Product Direction

HermesPhone is an SSH-first companion, not a native interactive-chat client.
The primary tabs are Sessions, Kanban, and Manage. Sessions are read-only and
retain durable lineage and cached transcript snapshots. Kanban polls only while
foregrounded. Manage contains profile-scoped gateway/channel monitoring,
profiles, schema-derived config, redacted environment status, and secondary
Files, Skills, Cron, Connections, and Terminal utilities.

The host remains authoritative. Do not add a mobile backend, shadow sync store,
dashboard dependency, or direct remote filesystem access outside the SSH
transport. Terminal is a utility and must not become a substitute chat composer.

## Verification

Use these checks before pushing release-sensitive mobile work:

```sh
swift test
```

Build the app through Xcode or XcodeBuildMCP using:

- project: `Apps/HermesPhone/HermesPhone.xcodeproj`
- scheme: `HermesPhone`
- simulator target: current supported iPhone simulator

The release checklist is in [release-checklist.md](release-checklist.md).

## Release Naming

Use mobile-specific tags for App Store releases:

```text
mobile/v1.0.0
mobile/v1.0.1
```

Desktop releases continue to use desktop/GitHub release naming on `main`.
