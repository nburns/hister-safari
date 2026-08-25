# Contributor guide

This repo is an **unofficial Safari port** of the upstream [Hister](https://github.com/asciimoo/hister) browser extension. The upstream maintainer declined Safari support in-tree ([issue #49](https://github.com/asciimoo/hister/issues/49)); this repo exists to produce a signed, notarized Safari build without forking upstream.

## Repo origin and shape

- `vendor/hister/` — upstream source, pinned as a git submodule. **Never modified in place.**
- `patches/` — Safari-only overrides applied to the built `dist/` bundle (manifest tweaks, a background-script shim). This is how we avoid forking upstream.
- `Safari/` — the macOS host app + Safari Web Extension target. Contains Swift sources, Info.plists, storyboard, and `project.yml`. The Xcode project itself is generated (see below).
- `scripts/` — build, notarize, icon-generation, and manifest-patching helpers.
- `assets/` — prebuilt PNG icons that replace upstream's runtime `OffscreenCanvas` icon path (Safari's background service worker cannot use it).
- `.github/workflows/release.yml` — CI: every push to `main` produces a signed, notarized DMG release.

## Xcode project is generated — do not edit `.xcodeproj`

`Safari/Hister.xcodeproj/` is **gitignored** and regenerated from `Safari/project.yml` by [XcodeGen](https://github.com/yonki/XcodeGen). This is deliberate: pbxproj files diff terribly, churn under different Xcode versions, and merge-conflict on trivial changes.

Rules:

- To change targets, build settings, frameworks, deployment targets, entitlements-adjacent flags (`ENABLE_APP_SANDBOX`, `REGISTER_APP_GROUPS`, etc.), or add source folders → **edit `Safari/project.yml`**, then rerun `xcodegen generate` inside `Safari/` (or just `scripts/build.sh`, which does it for you).
- Do **not** commit changes to `Safari/Hister.xcodeproj/` — they are ignored, but if you touch them in Xcode's UI they will be silently wiped on the next generate.
- Extension resources (`Safari/Hister Extension/Resources/`) are also gitignored — they are the output of `scripts/build.sh` (upstream `npm run build` + patches). Don't hand-edit them.

## Setup

```bash
brew bundle                                # installs xcodegen + node from Brewfile
git submodule update --init --recursive
scripts/build.sh                           # unsigned local build
```

`scripts/build.sh` does the full pipeline: builds the upstream extension via npm, stages the patched bundle into `Safari/Hister Extension/Resources/`, regenerates the Xcode project via xcodegen, then `xcodebuild archive` + optional notarize.

Environment knobs:

- `SKIP_XCODE=1` — stage the bundle only, skip xcodebuild. Useful for iterating on the extension side without a full build.
- `CODE_SIGN_IDENTITY` — defaults to `-` (ad-hoc). Set to `Developer ID Application` for a real signed build.
- `NOTARIZE=1` — after signing, submit to Apple notary and staple, then package the DMG. Requires `APPLE_NOTARY_USER`, `APPLE_NOTARY_PASSWORD`, `APPLE_TEAM_ID`.
- `HISTER_VERSION` — release version. Unset → `0.<day-of-year>.<hour>.<minute>`. Set → strips `v` prefix and everything after `-` for the on-disk version; full tag preserved in DMG filename.

## Conventions

- **Never modify `vendor/hister/`.** All Safari-specific behavior lives in `patches/` and is applied at build time by `scripts/build.sh` / `scripts/patch-manifest.mjs`. To upgrade upstream, bump the submodule pointer and re-run the build.
- **Never commit `Safari/Hister.xcodeproj/` or `Safari/Hister Extension/Resources/`.** Both are gitignored and generated.
- **CI actions are pinned to full commit SHAs** with the version tag in a trailing comment. See `.github/workflows/release.yml`. This is defense against tag-mutation / action-repo compromise. When bumping, resolve the SHA via `gh api /repos/<owner>/<repo>/git/refs/tags/<tag>`.
- **Every push to `main` publishes a full release**, not a prerelease. Tag pushes (`vX.Y.Z`) use the tag as the version; branch pushes get a `v0.<day-of-year>.<h>.<m>` stamp. `workflow_dispatch` only uploads a build artifact, never a release.
- **macOS 15 (Sequoia) is the deployment target** for the app; the extension target keeps `MACOSX_DEPLOYMENT_TARGET=10.14` as inherited from Apple's Safari extension template. Both are declared in `Safari/project.yml`.
- **The wrapper adds no telemetry** and makes no network calls beyond what upstream Hister does. Keep it that way.

## Updating to a new upstream release

```bash
cd vendor/hister && git fetch origin && git checkout <tag-or-sha> && cd ../..
git add vendor/hister
git commit -m "Bump vendored hister to <tag-or-sha>"
```

Then push to `main` (auto-release) or tag with `vX.Y.Z` for a pinned release.
