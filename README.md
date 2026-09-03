# Hister Safari extension (unofficial)

> **This is an unofficial Safari port of the [Hister](https://github.com/asciimoo/hister) browser extension.** It is not affiliated with or endorsed by the upstream Hister project. The upstream maintainer has declined to include Safari support in-tree (see [issue #49](https://github.com/asciimoo/hister/issues/49)); this repository exists to make a signed, notarized Safari build available anyway.

[Hister](https://github.com/asciimoo/hister) is a self-hosted personal search engine that indexes the full contents of pages you visit (and PDFs you open) so you can search them later. The browser extension is what sends visited pages to your Hister server; this repo packages that extension for Safari on macOS.

The wrapper adds no telemetry and makes no network calls beyond what upstream Hister does.

## What this repo contains

- `vendor/hister/` — the upstream Hister source, pinned to a specific commit as a git submodule.
- `patches/` — Safari-only overrides applied to the upstream extension bundle at build time (manifest tweaks, a small background-script shim).
- `Safari/` — host app + Safari Web Extension target sources. The `Hister.xcodeproj` is generated on demand from `Safari/project.yml` by [XcodeGen](https://github.com/yonki/XcodeGen) and is not checked in.
- `scripts/` — build and notarization pipeline.
- `.github/workflows/release.yml` — CI that produces a signed DMG on tagged releases.

Upstream source is never modified; the wrapper only patches the produced `dist/` bundle.

## Install (end users)

Requires macOS 15 (Sequoia) or later, and a running [Hister server](https://github.com/asciimoo/hister) you can reach from your Mac.

Once a release is published:

1. Download `Hister-<version>.dmg` from the [Releases](https://github.com/nburns/hister-safari/releases) page.
2. Open the DMG and drag `Hister.app` to `/Applications`.
3. Launch `Hister.app` once. It will prompt you to open Safari's extension preferences.
4. In Safari → Settings → Extensions, enable **Hister**.
5. Click the Hister toolbar icon and enter the URL of your Hister server.

Because the app is signed with an Apple Developer ID and notarized, there is no need to enable "Allow unsigned extensions" and the extension stays enabled across Safari restarts.

The toolbar popup, skip rules, PDF indexing, access-token auth, and indexed-badge behaviour are the same code as the Chrome and Firefox extensions. Safari-only differences:

- Toolbar icons are pre-rendered PNGs (Safari's service worker cannot use `OffscreenCanvas`).
- Keyboard shortcuts are **not** applied from `suggested_key`. Assign them in Safari → Settings → Extensions if you want them.
- The popup talks to your Hister server with a `safari-web-extension://` origin. Current Hister already allows that origin for CSRF. Token-auth from the popup also needs the server to answer CORS preflight (`OPTIONS`). Background indexing of pages works against stock Hister.

### Uninstall

Quit Safari, drag `Hister.app` from `/Applications` to the Trash, then reopen Safari. Any extension settings stored in Safari are removed with the containing app.

## Build (developers)

Requires: macOS with Xcode 15+, plus the tools in `Brewfile` (Node.js, XcodeGen). An Apple Developer account is needed for signed builds.

```bash
git clone --recurse-submodules https://github.com/nburns/hister-safari.git
cd hister-safari
brew bundle                   # installs xcodegen + node
node --test scripts/patch-manifest.test.mjs
scripts/build.sh              # unsigned local build (CODE_SIGN_IDENTITY=- by default)
```

Unsigned local builds require Safari's Develop menu → **Allow Unsigned Extensions** after each Safari restart.

`scripts/build.sh` regenerates `Safari/Hister.xcodeproj` from `Safari/project.yml` on every run, so if you need to open Xcode directly, run `xcodegen generate` inside `Safari/` first (or just run the build script once).

Edit target/build settings by modifying `Safari/project.yml` — never by editing the generated `.xcodeproj`, since your changes will be wiped on the next generate. See [AGENTS.md](AGENTS.md) for the full contributor guide.

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
