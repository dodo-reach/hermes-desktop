# Hermes Desktop

Native macOS app for Hermes over SSH.

Hermes Desktop gives you the parts of Hermes that matter most on a Mac:
sessions, memories, and a real terminal. In one clean place. 

It stays deliberately simple:

- connects directly over SSH
- keeps the Hermes host as the only source of truth
- does not depend on a gateway API
- does not mirror files onto your Mac
- does not install a helper service on the remote host

That is the point of the app. It adds a polished Mac interface around the real
Hermes workflow instead of replacing it with a heavier or more abstract layer.

![Hermes Desktop Sessions view](assets/readme-preview-sessions-safe.png)

Preview of the Sessions view, with recent Hermes conversations on the active
host.

## What You Get

- a native Mac app, not a browser wrapper
- a real embedded SSH terminal with tabs
- remote editing for:
  - `~/.hermes/memories/USER.md`
  - `~/.hermes/memories/MEMORY.md`
  - `~/.hermes/SOUL.md`
- session browsing from the canonical remote store at `~/.hermes/state.db`
- fallback to `~/.hermes/sessions/*.jsonl` only if the SQLite store is not
  available

Works with:

- Raspberry Pi
- another Mac
- a VPS or remote server
- the same Mac via `ssh localhost`, a local hostname, or a local SSH alias

## Before You Download

You need only a few things:

- an Apple Silicon Mac for the current public release build
- macOS 14 or newer
- SSH access that already works from Terminal without password prompts
- the SSH host key already accepted once in Terminal for that target
- `python3` available on the Hermes host
- Hermes data under the remote user's `~/.hermes`

Simple rule:
if this works in Terminal without asking for a password, the app is usually ready to work too:

```bash
ssh your-host
```

## Install

1. Download `HermesDesktop.app.zip` from GitHub Releases.
2. Double click the zip.
3. Drag `HermesDesktop.app` into `Applications`.
4. Open it.

The current public build is Apple Silicon only and not notarized yet.
Because of that, macOS may show a warning saying Apple cannot verify the app
for malware. That is expected for this release and does not mean macOS found
malware in Hermes Desktop.

If macOS blocks the first launch:

1. Click `Done`, not `Move to Bin`.
2. Right click `HermesDesktop.app` and choose `Open`.
3. If needed, go to `Privacy & Security` and click `Open Anyway`.

## Connect Your Hermes Host

Open the app, go to `Connections`, create a profile, then click `Test` and
`Use Host`.

You have two valid ways to fill the connection:

### Option 1: SSH alias

This is the easiest option.

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

### Same Mac

If Hermes runs on the same Mac, the model stays the same: SSH.

Use one of these:

- `localhost`
- your local hostname
- a local SSH alias

Hermes Desktop still connects over SSH and never reads those files directly.

## What `Test` Checks

`Test` is not a cosmetic button.

It checks that:

- the SSH target is reachable
- authentication works without interactive prompts
- `python3` is available in the remote SSH environment used by the app

If `Test` passes, `Use Host` should be on solid ground.

## What You Will See In The App

- `Overview`
  Confirms the remote `HOME`, the Hermes root, the tracked Hermes files, and
  the session source.
- `Files`
  Lets you edit `USER.md`, `MEMORY.md`, and `SOUL.md` on the host.
- `Sessions`
  Reads the real remote session store from `~/.hermes/state.db`.
- `Terminal`
  Opens the real SSH shell inside the app.

## Why SSH And A Real Terminal

Hermes is strongest at the command line.

Hermes Desktop keeps that direct path visible and usable: real SSH, real
terminal, real remote files. It does not try to hide Hermes behind a separate
gateway layer or turn it into something else.

## FAQ

### Is it safe to install?

That is a fair question, and you should not rely on reassurance alone.

Here are concrete things you can verify yourself:

- the app is open source in this repo, and you can build it locally with `./scripts/build-macos-app.sh` instead of using the release zip
- GitHub shows a SHA-256 for the release asset, and you can compare it after download with `shasum -a 256 HermesDesktop.app.zip`
- you can verify the downloaded app bundle locally with `codesign --verify --deep --strict /Applications/HermesDesktop.app`
- Hermes Desktop uses direct SSH to the host you choose and does not require a gateway API; if you want to inspect its live network behavior, you can watch it with Little Snitch, LuLu, or `nettop`
- Hermes Desktop does not require installing a helper service on the remote host; if you want to be extra cautious, test it first against a disposable or non-critical Hermes host
- if you already use a coding agent you trust, point it at this repo and ask for an independent review of the codebase, build scripts, packaging flow, and release process

One important limitation is distribution trust: the current public build is not
notarized by Apple yet. That is why macOS may show a first-launch warning. It
is a real friction point, and it is different from Apple actively reporting
that it found malware in the app.

### Why can't I browse every file the agent creates on the host?

On purpose. Hermes Desktop is not trying to become a remote file manager or a
full remote IDE. We wanted the app to stay focused on the Hermes flow that
matters most on Mac: sessions, memories, and terminal work.

If you need full filesystem access, there are already better tools for it:
your normal SSH shell, SFTP apps, or remote editors. Keeping the in-app file
surface narrow also avoids encouraging people to casually open arbitrary
agent-generated files they have not reviewed yet. It is a product choice first,
and a safer default second, not a hard security boundary.

### Why do I still need SSH working in Terminal first?

Because the app does not replace SSH. It depends on the same connection path
your Mac already uses. If Terminal still needs passwords, host key
confirmation, or other interactive fixes, the app will usually hit the same
wall.

### Why doesn't the app mirror Hermes files onto my Mac?

Because the remote Hermes host stays the source of truth. Once the app starts
caching or syncing copies locally, you introduce stale state, conflict
handling, and harder-to-explain behavior. The current design keeps reads and
edits attached to the real remote files.

### Why are sessions read from `~/.hermes/state.db` first?

Because that is the canonical Hermes session store. Reading it gives the app
the same view Hermes itself uses. `~/.hermes/sessions/*.jsonl` exists as a
fallback only when the SQLite store is not available.

## Roadmap

This is the current direction for the next waves of work:

### Recently Shipped

- [x] richer workflows around the canonical Hermes files: `USER.md`, `MEMORY.md`, and `SOUL.md`

### Next

- skill management views for tracking, inspecting, editing, and organizing agent skills from the app
- multi-profile support, aligned with Hermes Agent profiles and the app-side connection flow needed to select and use them cleanly
- UI skins and appearance options to personalize the terminal and the broader chat-like workspace
- clearer documentation, setup guides, and troubleshooting for new users
- easier distribution for non-technical users through signed, notarized builds and, if realistic, App Store or similarly frictionless delivery
- better first-run onboarding and connection diagnostics so SSH setup problems are easier to understand and fix
- continued product polish across session browsing, terminal UX, and multi-host workflows

## Build From Source

For local development, the supported path in this repo is to build the app
bundle directly:

```bash
./scripts/build-macos-app.sh
```

Then open `dist/HermesDesktop.app`.

To create the Mac app bundle again:

```bash
./scripts/build-macos-app.sh
```

To create the GitHub Releases archive:

```bash
./scripts/package-github-release.sh
```

Release artifact:

- `dist/HermesDesktop.app.zip` for Apple Silicon Macs
