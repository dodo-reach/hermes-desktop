# Hermes Desktop

Native macOS companion for Hermes Agent over SSH.

It turns the daily Hermes loop into something you can actually live in on a
Mac.

It brings the parts of the workflow that matter most into one focused window:
sessions, canonical files, usage, skills, cron jobs, and a real terminal.

If Hermes is already part of how you work, the app should feel immediately
legible: same host, same files, same shell, same profiles, same scheduler,
same session history.

No browser wrapper. No gateway API. No daemon on the host. No local mirror. No
extra sync layer slowly drifting away from the machine that actually matters.

That restraint is intentional:

- connects directly over SSH
- keeps the Hermes host as the only source of truth
- does not depend on a gateway API
- does not mirror files onto your Mac
- does not install a helper service on the remote host

That is the point of the app.

Hermes Desktop does not invent a softer second version of Hermes. It makes the
real workflow feel calm, fast, and native on a Mac while keeping the model
visible. You still know what host you are on, which Hermes profile is active,
where the canonical state lives, and which path the app is actually using.

## Preview

<table>
  <tr>
    <td width="50%">
      <img src="assets/CRON-JOBS.png" alt="Hermes Desktop Cron Jobs view" />
    </td>
    <td width="50%">
      <img src="assets/USAGE.png" alt="Hermes Desktop Usage view" />
    </td>
  </tr>
  <tr>
    <td width="50%">
      <img src="assets/SKILLS.png" alt="Hermes Desktop Skills view" />
    </td>
    <td width="50%">
      <img src="assets/TERMINALE.png" alt="Hermes Desktop Terminal view" />
    </td>
  </tr>
</table>

Cron Jobs, Usage, Skills, and Terminal on a live Hermes host, kept privacy-safe
for the public README.

## What You Get

- a native Mac app that feels like a Mac app, not a browser control panel
- direct SSH connection profiles for the default Hermes home and named Hermes
  profiles on the same host
- a profile-aware workspace where overview, files, sessions, usage, cron jobs,
  skills, and terminal behavior all resolve against the selected Hermes profile
- a real embedded SSH terminal with multiple tabs across hosts and profiles,
  plus quick themes and live background and text color controls
- a natural multi-agent workflow on macOS: keep one tab on a shell, another on
  a scheduler, another on a different profile, all without inventing a second
  model of the host
- an overview that surfaces the active profile, discovered profiles, resolved
  paths, session store, cron location, and host readiness checks
- conflict-aware editing for the canonical Hermes files:
  - `~/.hermes/memories/USER.md`
  - `~/.hermes/memories/MEMORY.md`
  - `~/.hermes/SOUL.md`
- session browsing, search, and deletion from the canonical remote session
  store in `~/.hermes/state.db`
- fallback to `~/.hermes/sessions/*.jsonl` only if the SQLite session store is
  not available
- aggregate usage totals, recent trends, model breakdowns, and host-wide
  cross-profile totals when more than one Hermes profile is readable
- recursive skill browsing from the local Hermes skills store plus configured `skills.external_dirs`, with local precedence
- direct skill editing and creation from Hermes Desktop, with atomic saves and
  conflict checks against the live remote `SKILL.md`
- cron job browsing, creation, editing, pause, resume, run-now, and deletion
  for the canonical remote scheduler state in `~/.hermes/cron/jobs.json`,
  including schedule, model, attached skills, and delivery target details
- app localization resources for English, Simplified Chinese, and Russian in a
  single macOS bundle that follows the user's preferred system language
- universal packaging for Apple Silicon and Intel Macs from the same build flow

If Hermes runs there and SSH already works, Hermes Desktop will usually meet you
there. That includes:

- Raspberry Pi
- another Mac
- a VPS or remote server
- the same Mac via `ssh localhost`, a local hostname, or a local SSH alias

## Hermes Desktop And The Official Web Dashboard

Nous Research now ships the official Hermes web dashboard. That is good news.

It clarifies the product landscape.

The official dashboard is great for browser-based management. Hermes Desktop is
for the side of Hermes you want to live in on a Mac.

That is not a hedge. It is a clean division of labor.

The split is simple:

- use the official web dashboard for browser-based management tasks such as
  config, API keys, logs, and dashboard-style administration
- use Hermes Desktop when you want the host itself to feel native on macOS:
  direct SSH, canonical files, real sessions, profile-aware usage, cron
  workflows, editable skills, and a real terminal

That distinction matters because it preserves the strength of both tools.

Hermes Desktop is not trying to drag Hermes into a vague middle layer between
browser UI and host reality. It is for people who want to stay close to the
host, work through the real SSH path, and still have a polished native Mac
workspace around it.

## Before You Download

Setup is intentionally lightweight. You need only a few things:

- a Mac running macOS 14 or newer
- SSH access from this Mac that already works in Terminal without interactive
  prompts
- the SSH host key already accepted once in Terminal for that target
- a normal route from this Mac to the Hermes host, such as local LAN, public
  IP or DNS, VPN, or a Tailscale IP or hostname
- `python3` available on the Hermes host
- Hermes data under the remote user's `~/.hermes`

Simple rule: if this works in Terminal from this Mac without asking for a
password or host key confirmation, the app is usually ready to work too:

```bash
ssh your-host
```

## Install

Install takes about a minute:

1. Download `HermesDesktop.app.zip` from GitHub Releases.
2. Double click the zip.
3. Drag `HermesDesktop.app` into `Applications`.
4. Open it.

The public release is packaged as a universal macOS build for both Intel and
Apple Silicon Macs. It is still not notarized yet. Because of that, macOS may
show a warning saying Apple cannot verify the app for malware. That is expected
for the current release flow and does not mean macOS found malware in Hermes
Desktop.

If macOS blocks the first launch:

1. Click `Done`, not `Move to Bin`.
2. Right click `HermesDesktop.app` and choose `Open`.
3. If needed, go to `Privacy & Security` and click `Open Anyway`.

## Connect Your Hermes Host

Open the app, go to `Connections`, create a profile, then click `Test` and
`Use Host`.

You have two valid ways to fill the connection. In most cases, an SSH alias is
the cleanest one:

### Option 1: SSH alias

An SSH alias is just a short name saved in your Mac's SSH config, so instead of
typing a long command every time, you can type something simple like:

```bash
ssh hermes-home
```

That short name usually comes from `~/.ssh/config`.

Example:

```sshconfig
Host hermes-home
  HostName vps.example.com
  User alex
```

In the app:

- set `SSH alias` to `hermes-home`
- leave `Host`, `User`, and `Port` empty unless you want explicit overrides

### Option 2: host details directly

If you normally connect with something like:

```bash
ssh alex@vps.example.com
```

then in the app:

- `Host or IP`: `vps.example.com`
- `User`: `alex`
- `Port`: `22` or your real SSH port

### Hermes profiles on the same host

Hermes Desktop can target either the default Hermes home or a named profile on
the same SSH host.

Examples:

- leave `Hermes profile` empty to use `~/.hermes`
- set `Hermes profile` to `researcher` to use
  `~/.hermes/profiles/researcher`

The important part is what happens after that: the profile selection is not a
label stuck on a form. It flows through the app.

Overview resolves against that profile. Usage stays scoped to that profile while
still being able to show host-wide cross-profile totals. Cron jobs target that
profile's scheduler state. The terminal launches with the right `HERMES_HOME`.
And terminal tabs can stay open across different profiles, so it is natural to
work multiple Hermes agents on the same host side by side.

### Same Mac

If Hermes runs on the same Mac, the model stays the same: SSH.

Use one of these:

- `localhost`
- your local hostname
- a local SSH alias

Hermes Desktop still connects over SSH and never reads those files directly.

## What `Test` Checks

`Test` is the preflight, not a cosmetic button.

It checks that:

- the SSH target is reachable
- authentication works without interactive prompts
- `python3` is available in the remote SSH environment used by the app

If `Test` passes, `Use Host` should be on solid ground.

## What You Will See In The App

- `Overview`
  Confirms the active host, the active Hermes profile, the discovered profiles,
  tracked paths, cron location, and the session store source.
- `Files`
  Lets you edit `USER.md`, `MEMORY.md`, and `SOUL.md` on the host with a remote
  conflict check before save.
- `Sessions`
  Reads the real remote session store from `~/.hermes/state.db`, with search,
  cleaner metadata, refresh-on-entry behavior, and remote deletion.
- `Cron Jobs`
  Browses the real Hermes cron definitions on the host, with create, edit,
  pause, resume, run-now, and delete actions, plus the details that matter when
  you are actually running them: schedule, model, skills, delivery target, and
  recent status.
- `Usage`
  Shows aggregate input and output token totals, top sessions, top models,
  recent session trends, and when available, a host-wide profile breakdown.
- `Skills`
  Discovers and reads remote `SKILL.md` files from the local Hermes skills
  store plus configured `skills.external_dirs`, while keeping skill creation
  and editing anchored to `~/.hermes/skills/`, with quick filtering,
  companion folder awareness, optional folder scaffolding, and remote
  conflict checks before save.
- `Terminal`
  Opens the real SSH shell inside the app, with multiple tabs, quick theme
  presets, live color tuning, and room for a genuinely multi-profile,
  multi-agent workflow that still stays close to the host.

## Why It Feels Different

Hermes Desktop comes from using Hermes enough to care about the annoying edges.

That is why the app keeps landing on the details that matter:

- the selected Hermes profile is not cosmetic; it stays coherent across the
  whole app
- terminal tabs are not ornamental; they let you keep parallel agent work open
  across hosts and profiles without losing context
- session and usage views come from the canonical remote store, not from a
  second local interpretation
- edits to memories and skills save atomically and respect remote state instead
  of blindly overwriting it
- cron workflows live next to the rest of the host workflow instead of being
  treated as a separate product

The result is a Mac app that feels calm not because it hides the underlying
system, but because it stays close to it.

## Why SSH And A Real Terminal

Hermes is strongest at the command line.

Hermes Desktop respects that. It keeps the real path visible and usable: real
SSH, real terminal, real remote files, real session data, real cron state.

It does not try to hide Hermes behind a separate gateway layer, invent a second
source of truth, or turn the workflow into something softer and less reliable.
The goal is not to abstract Hermes away. The goal is to give it a native Mac
surface that still feels honest.

That honesty is precisely what makes the app reassuring. You do not need to
guess where your data lives, which machine is authoritative, or whether the app
invented its own shadow world to feel convenient. Hermes Desktop stays close to
the host because that is the more trustworthy design.

## FAQ

### Is it safe to install?

That is exactly the right question, and you should not rely on reassurance
alone.

Here are concrete things you can verify yourself:

- the app is open source in this repo, and you can build it locally with
  `./scripts/build-macos-app.sh` instead of using the release zip
- GitHub shows a SHA-256 for the release asset, and you can compare it after
  download with `shasum -a 256 HermesDesktop.app.zip`
- you can verify the downloaded app bundle locally with
  `codesign --verify --deep --strict /Applications/HermesDesktop.app`
- Hermes Desktop uses direct SSH to the host you choose and does not require a
  gateway API; if you want to inspect its live network behavior, you can watch
  it with Little Snitch, LuLu, or `nettop`
- Hermes Desktop does not require installing a helper service on the remote
  host; if you want to be extra cautious, test it first against a disposable or
  non-critical Hermes host
- if you already use a coding agent you trust, point it at this repo and ask
  for an independent review of the codebase, build scripts, packaging flow, and
  release process

One important limitation today is distribution trust: the public build is
universal for both Intel and Apple Silicon Macs, but it is still not notarized
by Apple. That is why macOS may show a first-launch warning. It is a real
friction point, and it is different from Apple actively reporting that it found
malware in the app.

### Why use Hermes Desktop if the official web dashboard exists?

Because they solve different problems.

The official dashboard is a browser-based management surface. Hermes Desktop is
a native Mac workspace for direct SSH-based daily use. If you want config, API
keys, and browser-admin flows, the dashboard is the natural place. If you want
sessions, canonical files, cron jobs, profile-aware usage, editable skills, and
a real terminal in one native macOS window, that is what Hermes Desktop is for.

The dashboard is not a threat to this app. It sharpens the case for it.

### Why can't I browse every file the agent creates on the host?

On purpose. Hermes Desktop is not trying to become a remote file manager or a
full remote IDE. We wanted the app to stay focused on the Hermes flow that
matters most on Mac: sessions, memories, cron work, and terminal work.

If you need full filesystem access, there are already better tools for it: your
normal SSH shell, SFTP apps, or remote editors. Keeping the in-app file surface
narrow also avoids encouraging people to casually open arbitrary
agent-generated files they have not reviewed yet. It is a product choice first,
and a safer default second, not a hard security boundary.

### Why do I still need SSH working in Terminal first?

Because the app does not replace SSH. It uses the same connection path your Mac
already uses, but in a non-interactive way.

If Terminal still needs password entry, host key confirmation, or other
interactive fixes for that target, the app will usually hit the same wall.

The important distinction is this: the remote host may still allow password
login in general, but Hermes Desktop works best when this Mac can complete the
SSH connection without prompts.

### Does my Mac need to be on the same Wi-Fi or local network as the Hermes host?

No.

Your Mac just needs a normal SSH route to the host from wherever it is. That
can be:

- the same local network
- a public IP or DNS name
- a VPN
- a Tailscale IP or MagicDNS hostname

If `ssh your-host` works from this Mac, Hermes Desktop can usually use that
same path too.

One important nuance: Hermes Desktop uses standard `/usr/bin/ssh`. So if your
setup works only through the separate `tailscale ssh` command and not through
normal `ssh`, that is a different setup and may not behave the same way inside
the app.

### Why doesn't the app mirror Hermes files onto my Mac?

Because the remote Hermes host stays the source of truth. Once the app starts
caching or syncing copies locally, you introduce stale state, conflict
handling, and harder-to-explain behavior. The current design keeps reads and
edits attached to the real remote files.

### Why are sessions read from `~/.hermes/state.db` first?

Because that is the canonical Hermes session store. Reading it gives the app
the same view Hermes itself uses. `~/.hermes/sessions/*.jsonl` exists as a
fallback only when the SQLite store is not available.

### What happens if a remote file changed after I opened it?

Hermes Desktop will not blindly overwrite it.

Before saving `USER.md`, `MEMORY.md`, or `SOUL.md`, the app checks whether the
remote file still matches the version you originally loaded. If it changed on
the host in the meantime, save is blocked and your local edits stay intact. At
that point the app asks you to `Reload from Remote` first, so you can make an
intentional decision instead of silently overwriting newer remote state.

## Roadmap

Most of the original roadmap is now shipped.

This app has reached the point we wanted: a calm, capable native macOS
workspace for the real Hermes workflow, still anchored to SSH and the host as
source of truth.

### Shipped

- [x] richer workflows around the canonical Hermes files:
  `USER.md`, `MEMORY.md`, and `SOUL.md`
- [x] native session workflows with cleaner metadata, search, deletion, and
  refresh-on-entry behavior
- [x] a usage dashboard with aggregate token totals, top sessions, top models,
  trends, and host-wide multi-profile totals when available
- [x] native skill workflows for discovering, inspecting, creating, and editing
  remote `SKILL.md` files from the Hermes skills store, with support for
  configured external discovery directories and local write precedence
- [x] profile-aware host workflows aligned with Hermes Agent profiles on the
  same SSH target
- [x] native cron job workflows for the canonical remote scheduler state
- [x] a real embedded SSH terminal with tabs, appearance controls, and coherent
  multi-profile workspace behavior
- [x] English, Simplified Chinese, and Russian localization resources packaged
  in the app bundle
- [x] universal macOS release packaging for Apple Silicon and Intel, with
  bundle version stamping in the packaging flow

### From Here

- reduce distribution friction with signing and notarization
- keep polishing onboarding, diagnostics, terminal UX, and multi-host details
  without adding a second transport model or shadow state

Anything larger than that should be justified by Hermes itself, not added here
for novelty.

## Build From Source

For local development, the supported path in this repo is to build the app
bundle directly:

```bash
./scripts/build-macos-app.sh
```

Then open `dist/HermesDesktop.app`.

To run the release-support test suite:

```bash
./scripts/run-tests.sh
```

To create the GitHub Releases archive:

```bash
./scripts/package-github-release.sh
```

For release-candidate packaging, you can stamp an explicit version:

```bash
HERMES_VERSION=0.5.0 ./scripts/package-github-release.sh
```

Release artifact:

- `dist/HermesDesktop.app.zip` as a universal macOS archive for Apple Silicon
  and Intel Macs
