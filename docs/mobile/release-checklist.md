# HermesPhone Release Checklist

Use this checklist before a TestFlight or App Store submission from `codex/mobile-v1`.

## Branch Preflight

- Confirm the branch is `codex/mobile-v1`.
- Confirm `git status` is clean.
- Confirm the release commit is pushed to `origin/codex/mobile-v1`.
- Review recent commits for accidental desktop-only changes.
- Confirm `.gitignore` keeps local build output, credentials, and provisioning material out of the repo.

## Build And Test

Run SwiftPM tests:

```sh
swift test
```

Build the simulator app:

- project: `Apps/HermesPhone/HermesPhone.xcodeproj`
- scheme: `HermesPhone`
- configuration: `Debug`
- destination: current supported iPhone simulator

For App Store archive, build from Xcode with:

- scheme: `HermesPhone`
- configuration: `Release`
- destination: `Any iOS Device`
- signing team: configured Apple Developer team

## App Store Configuration

Verify in the Xcode project:

- bundle identifier is correct.
- marketing version is correct.
- build number is incremented.
- AppIcon asset catalog is present and selected.
- launch screen configuration is acceptable.
- supported orientations are intentional.
- signing and provisioning are valid.
- no debug-only build settings are enabled for Release.

Verify App Store metadata outside the repo:

- app name, subtitle, category, and screenshots.
- privacy answers.
- support URL.
- review notes explaining that the app connects to user-provided SSH hosts.

## Runtime Smoke Test

Run this on a simulator and, before submission, a real device:

- launch app cleanly.
- add a password SSH connection.
- add a private-key SSH connection if supported by the release.
- accept an unknown host key.
- reject or handle a changed host key.
- inspect the Sessions list, search, pagination, cached resume, and selectable transcript.
- confirm whole-message copy and reasoning/tool separation.
- confirm there is no chat composer, chat warmup process, or chat notification route.
- open Kanban and verify foreground polling stops after leaving the tab.
- verify Gateway, Profiles, Config, and Environment under Manage.
- open Terminal as a secondary utility and run a simple remote command.
- browse canonical files.
- browse and pin a remote directory.
- view skills.
- view cron jobs.
- pause/resume/run a cron job if a safe test job exists.
- background and foreground the app during Kanban and terminal usage.
- relaunch and confirm persisted connections, bookmarks, and session state behave as expected.

## Vendor Check

`Vendor/Citadel` should remain minimal:

- keep `Package.swift`, license/readme, and required source files.
- do not add upstream examples, tests, CI, or demo apps.
- do not commit `Vendor/Citadel/Package.resolved`.

If Citadel is updated, rebuild and repeat SSH smoke tests.

## Release Tag

After a successful App Store or TestFlight build, tag the exact commit:

```sh
git tag mobile/v1.0.0
git push origin mobile/v1.0.0
```

Use the actual released version number.

## Hotfix Rule

For mobile hotfixes:

1. branch from the released `codex/mobile-v1` commit.
2. keep the patch narrow.
3. run the full checklist sections that match the touched area.
4. merge back to `codex/mobile-v1`.
5. tag a new mobile patch version.
