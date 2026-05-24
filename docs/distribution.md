# Distribution And Verification

This document describes the current Hermes Desktop release model in this
repository.

It is intentionally narrow: what the public release zip is, how it is produced,
what you can verify yourself, and what the current limitations are.

## Current Release Shape

Hermes Desktop is currently distributed as:

- a universal macOS app bundle for Apple Silicon and Intel
- zipped as `HermesDesktop.app.zip`
- ad-hoc signed with `codesign --sign -`
- not notarized by Apple

The release packaging flow in this repo is script-based:

- `scripts/build-macos-app.sh` builds the app bundle, ad-hoc signs it, and
  verifies the resulting bundle with `codesign --verify --deep --strict`
- `scripts/package-github-release.sh` builds the app, zips it, creates a
  SHA-256 checksum file for the zip, and emits a small JSON manifest for the
  release artifact
- `scripts/verify-release.sh` checks the packaged zip against that manifest,
  verifies the checksum, extracts the app bundle, and validates basic bundle
  expectations plus `codesign --verify --deep --strict`

## Release Manifest

Each packaged release now includes `HermesDesktop.app.zip.manifest.json`.

The manifest is intentionally small and stable. It records:

- the release zip file name
- the SHA-256 of the zip
- the zip size in bytes
- the bundled app name
- the bundle identifier
- the bundle version and build number
- the minimum supported macOS version
- the executable name
- the executable architectures present in the shipped app

This manifest is meant to make the package easier to inspect and verify. It is
not a signature, attestation, or notarization substitute.

## What Ad-Hoc Signing Means Here

Ad-hoc signing is still useful, but it is a limited signal.

In this repository's current flow, ad-hoc signing means the bundle is signed in
a way macOS can validate for internal integrity. It does not mean:

- the app is notarized by Apple
- the app is associated with a named Apple Developer identity
- Apple has reviewed or scanned the release as part of notarization

That is why first launch may require right-click `Open`, and why macOS may warn
that Apple cannot verify the app for malware.

## What The Published Checksum Proves

Each release zip includes a SHA-256 checksum and a small JSON manifest.

Comparing your local download against that checksum is useful because it lets
you confirm your copy matches the release asset you downloaded.

It does not, by itself, prove:

- who created the release
- that the release contents are benign
- that the GitHub account or release page you trusted was uncompromised

Checksums help you detect mismatch or corruption. They are not a substitute for
reviewing the source or understanding the distribution model.

## How To Verify A Release Zip

After downloading `HermesDesktop.app.zip`:

```bash
shasum -a 256 HermesDesktop.app.zip
```

Compare the output with the checksum published in the GitHub Release.

If you want the repo to perform the same local verification flow used in CI,
run this from a checkout of the repository:

```bash
./scripts/verify-release.sh \
  /path/to/HermesDesktop.app.zip \
  /path/to/HermesDesktop.app.zip.manifest.json
```

After extracting and moving the app into place:

```bash
codesign --verify --deep --strict /Applications/HermesDesktop.app
```

If you want more visibility into what macOS sees in the bundle:

```bash
codesign -dv --verbose=4 /Applications/HermesDesktop.app
```

For network behavior, you can observe live connections with Little Snitch,
LuLu, `lsof`, or `nettop`.

## Strongest Trust Path In This Repo

The strongest trust path available in this repository today is to inspect the
source and build the app yourself:

```bash
./scripts/build-macos-app.sh
```

That produces a local app bundle in `dist/HermesDesktop.app`.

For the Cael-local distribution loop on BigMac, the current private arm64 package
is served by Cael Workspace rather than GitHub:

```bash
cd /Users/cderamos/StorageRuntime/hermes-desktop-cael
HERMES_MAC_ARCHS=arm64 ./scripts/build-macos-app.sh
ditto -c -k --keepParent dist/HermesDesktop.app /tmp/CaelDesktop-macOS-arm64.zip
cp /tmp/CaelDesktop-macOS-arm64.zip \
  /Users/cderamos/StorageRuntime/hermes-workspace-cael/public/downloads/CaelDesktop-macOS-arm64.zip
cd /Users/cderamos/StorageRuntime/hermes-workspace-cael/public/downloads
shasum -a 256 CaelDesktop-macOS-arm64.zip > CaelDesktop-macOS-arm64.sha256
```

The private install page is `http://100.97.216.111:3077/desktop` on the
Tailscale mesh. It serves:

- `/downloads/CaelDesktop-macOS-arm64.zip`
- `/downloads/CaelDesktop-macOS-arm64.sha256`

Install paths used in the Cael setup:

- BigMac source/build path: `/Users/cderamos/StorageRuntime/hermes-desktop-cael`
- BigMac installed app: `/Applications/HermesDesktop.app`
- MBP installed app: `~/Applications/HermesDesktop.app` or `/Applications/HermesDesktop.app`

This is still an ad-hoc signed, non-notarized bundle, because that is the
current build and release model in the repo. Building locally does not turn it
into a notarized distribution, but it does let you trust your own build inputs
instead of a downloaded zip.

## What The App Depends On At Runtime

Trusting the release zip is only part of the picture. Hermes Desktop also
depends on the environment it connects to.

The app assumes:

- your Mac already has a working SSH path to the target host
- the host already has `python3`
- the host already has `hermes` on the non-interactive SSH `PATH` for in-app
  chat and resume flows

The app then uses SSH to execute remote commands on that host. See
[../SECURITY.md](../SECURITY.md) for the runtime security model.

## Honest Limitation

The current release model is intentionally documented without stronger claims
than the code and scripts support today.

If the project later adopts Developer ID signing, notarization, or additional
release verification, this document should be updated at the same time as the
implementation. Until then, the correct description is simple:

- public releases are ad-hoc signed
- public releases are not notarized
- published checksums help verify the downloaded zip
- the release manifest makes the artifact metadata easier to inspect and
  compare
- building from source is the clearest trust path for cautious users
