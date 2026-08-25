# Hister Safari extension (unofficial)

> **This is an unofficial Safari port of the [Hister](https://github.com/asciimoo/hister) browser extension.** It is not affiliated with or endorsed by the upstream Hister project. The upstream maintainer has declined to include Safari support in-tree (see [issue #49](https://github.com/asciimoo/hister/issues/49)); this repository exists to make a signed, notarized Safari build available anyway.

The wrapper adds no telemetry and makes no network calls beyond what upstream Hister does.

## What this repo contains

- `vendor/hister/` — the upstream Hister source, pinned to a specific commit as a git submodule.
- `patches/` — Safari-only overrides applied to the upstream extension bundle at build time (manifest tweaks, a small background-script shim).
- `Safari/` — Xcode project that wraps the built extension into a macOS Safari Web Extension host app.
- `scripts/` — build and notarization pipeline.
- `.github/workflows/release.yml` — CI that produces a signed DMG on tagged releases.

Upstream source is never modified; the wrapper only patches the produced `dist/` bundle.

## Install (end users)

Once a release is published:

1. Download `Hister-<version>.dmg` from the [Releases](https://github.com/nburns/hister-safari/releases) page.
2. Open the DMG and drag `Hister.app` to `/Applications`.
3. Launch `Hister.app` once. It will prompt you to open Safari's extension preferences.
4. In Safari → Settings → Extensions, enable **Hister**.
5. Click the Hister toolbar icon and enter the URL of your Hister server.

Because the app is signed with an Apple Developer ID and notarized, there is no need to enable "Allow unsigned extensions" and the extension stays enabled across Safari restarts.

## Build (developers)

Requires: macOS with Xcode 15+, Node.js 20+, an Apple Developer account (for signing).

```bash
git clone --recurse-submodules https://github.com/nburns/hister-safari.git
cd hister-safari
scripts/build.sh              # unsigned local build (CODE_SIGN_IDENTITY=- by default)
```

For a signed build, export your signing credentials and re-run `scripts/build.sh`; see `.github/workflows/release.yml` for the exact environment variables.

## Updating to a new upstream release

```bash
cd vendor/hister
git fetch origin
git checkout <tag-or-sha>
cd ../..
git add vendor/hister
git commit -m "Bump vendored hister to <tag-or-sha>"
```

Then re-run the build and re-tag.

## License

[AGPLv3](LICENSE), matching upstream.
