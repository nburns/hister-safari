#!/usr/bin/env bash
# Build the Safari-wrapped Hister extension.
#
# Stages:
#   1. Build the upstream extension bundle inside the vendored submodule.
#   2. Patch the manifest for Safari and stage the bundle under
#      "Safari/Hister Extension/Resources/".
#   3. If Safari/Hister.xcodeproj exists, run xcodebuild archive+export and
#      (optionally) notarize + package into a DMG.
#
# Environment variables:
#   SKIP_XCODE=1        Only stage the bundle; skip xcodebuild. Useful for CI
#                       linters or a first-time run before the Xcode project
#                       has been generated.
#   CODE_SIGN_IDENTITY  Passed through to xcodebuild. Default "-" (ad-hoc,
#                       for local development). Set to your Developer ID for
#                       release builds.
#   NOTARIZE=1          After a successful signed build, submit to Apple's
#                       notary service and staple. Requires APPLE_NOTARY_USER,
#                       APPLE_NOTARY_PASSWORD, APPLE_TEAM_ID.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$REPO_ROOT"

UPSTREAM_ROOT="vendor/hister"
UPSTREAM_EXT="$UPSTREAM_ROOT/webui/ext"
RESOURCES="Safari/Hister Extension/Resources"

# Version:
#   HISTER_VERSION unset      -> 0.<day-of-year>.<hour>.<minute> for local dev.
#   HISTER_VERSION="v0.0.1"   -> app is 0.0.1, DMG is Hister-v0.0.1.dmg.
#   HISTER_VERSION="v0.0.1-rc.1" -> app is 0.0.1, DMG is Hister-v0.0.1-rc.1.dmg
#     (Apple's CFBundleShortVersionString and Chrome extension manifest.version
#      accept only period-separated integers, so we strip the 'v' prefix and
#      anything after the first '-' for the on-disk version fields; the full
#      tag is preserved in the DMG filename so releases stay unambiguous.)
if [[ -n "${HISTER_VERSION:-}" ]]; then
    DMG_VERSION="$HISTER_VERSION"
    APP_VERSION="${HISTER_VERSION#v}"
    APP_VERSION="${APP_VERSION%%-*}"
    if ! [[ "$APP_VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
        echo "error: HISTER_VERSION '$HISTER_VERSION' does not reduce to N.N.N" >&2
        echo "       (stripped to '$APP_VERSION')" >&2
        exit 1
    fi
else
    APP_VERSION="0.$(date +%-j.%-H.%-M)"
    DMG_VERSION="$APP_VERSION"
fi
echo "==> App version: $APP_VERSION   DMG version: $DMG_VERSION"

if [[ ! -d "$UPSTREAM_EXT" ]]; then
    echo "error: $UPSTREAM_EXT missing; did you 'git submodule update --init'?" >&2
    exit 1
fi

echo "==> Building upstream extension bundle"
# The extension is part of an npm workspace; install from the repo root so
# workspace deps like @hister/components resolve, then build only the ext.
(
    cd -- "$UPSTREAM_ROOT"
    npm ci
    npm --workspace @hister/ext run build
)

echo "==> Staging bundle into $RESOURCES"
mkdir -p -- "$RESOURCES/assets/icons"
# Copy the dist tree wholesale, then overwrite manifest.json with the patched
# version. --delete keeps the resources directory in lockstep with dist.
rsync -a --delete \
    --exclude 'manifest.json' \
    --exclude 'manifest_ff.json' \
    "$UPSTREAM_EXT/dist/" "$RESOURCES/"

node scripts/patch-manifest.mjs \
    "$UPSTREAM_EXT/dist/manifest.json" \
    patches/manifest.safari.json \
    "$RESOURCES/manifest.json"

# Stamp the extension manifest with the same version as the host app.
python3 -c '
import json, sys
p = sys.argv[1]
m = json.load(open(p))
m["version"] = sys.argv[2]
json.dump(m, open(p, "w"), indent=2)
open(p, "a").write("\n")
' "$RESOURCES/manifest.json" "$APP_VERSION"

# Prepend the Safari shim so it runs before upstream background code. The
# service_worker entry in the manifest still points at background.js.
{
    cat -- patches/safari-shims.js
    printf '\n'
    cat -- "$UPSTREAM_EXT/dist/background.js"
} > "$RESOURCES/background.js.tmp"
mv -- "$RESOURCES/background.js.tmp" "$RESOURCES/background.js"

# Prebuilt icons replace the runtime OffscreenCanvas path (see safari-shims.js).
for name in icon-16.png icon-32.png icon-grey-16.png icon-grey-32.png; do
    if [[ ! -f "assets/$name" ]]; then
        echo "error: assets/$name missing; run scripts/generate-icons.sh" >&2
        exit 1
    fi
    cp -- "assets/$name" "$RESOURCES/assets/icons/$name"
done

if [[ "${SKIP_XCODE:-0}" == "1" ]]; then
    echo "==> SKIP_XCODE=1, done."
    exit 0
fi

if [[ ! -d "Safari/Hister.xcodeproj" ]]; then
    cat >&2 <<'EOF'
==> Safari/Hister.xcodeproj not found. Regenerate it with:

      xcrun safari-web-extension-converter \
          --project-location Safari-generated \
          --app-name Hister \
          --bundle-identifier org.hister.safari-unofficial \
          --swift --macos-only --copy-resources \
          --no-open --no-prompt --force \
          "Safari/Hister Extension/Resources"

    Then move Safari-generated/Hister/* into Safari/ and commit.
EOF
    exit 0
fi

CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

echo "==> xcodebuild archive (CODE_SIGN_IDENTITY=$CODE_SIGN_IDENTITY)"
mkdir -p build
XCODEBUILD_ARGS=(
    -project Safari/Hister.xcodeproj
    -scheme Hister
    -configuration Release
    -archivePath build/Hister.xcarchive
    CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY"
    MARKETING_VERSION="$APP_VERSION"
    CURRENT_PROJECT_VERSION="$APP_VERSION"
)
# Switch off Xcode automatic signing when we're providing an explicit identity
# (i.e. a real Developer ID Application build, not the ad-hoc default).
if [[ "$CODE_SIGN_IDENTITY" != "-" ]]; then
    XCODEBUILD_ARGS+=(CODE_SIGN_STYLE=Manual)
fi
if [[ -n "${APPLE_TEAM_ID:-}" ]]; then
    XCODEBUILD_ARGS+=(DEVELOPMENT_TEAM="$APPLE_TEAM_ID")
fi
xcodebuild "${XCODEBUILD_ARGS[@]}" archive

echo "==> xcodebuild exportArchive"
xcodebuild \
    -exportArchive \
    -archivePath build/Hister.xcarchive \
    -exportOptionsPlist Safari/ExportOptions.plist \
    -exportPath build/export

if [[ "${NOTARIZE:-0}" == "1" ]]; then
    DMG="build/Hister-${DMG_VERSION}.dmg"

    echo "==> Packaging DMG"
    # Stage a clean directory holding only Hister.app plus a /Applications
    # symlink so the DMG opens to the standard drag-to-install layout.
    DMG_STAGE="$(mktemp -d)"
    trap 'rm -rf -- "$DMG_STAGE"' EXIT
    cp -R build/export/Hister.app "$DMG_STAGE/"
    ln -s /Applications "$DMG_STAGE/Applications"
    hdiutil create -volname Hister -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG"

    "$REPO_ROOT/scripts/notarize.sh" "$DMG"
    echo "==> Built $DMG"
else
    echo "==> Unsigned/ad-hoc build available at build/export/Hister.app"
fi
