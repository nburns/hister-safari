#!/usr/bin/env bash
# Generate the normal + greyscale 16 and 32 pixel icons from the upstream
# icon128.png. Output goes into assets/. Uses sips (ships with macOS) so no
# ImageMagick dependency.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$REPO_ROOT"

SRC="vendor/hister/webui/ext/assets/icon128.png"
if [[ ! -f "$SRC" ]]; then
    echo "error: $SRC missing; did you 'git submodule update --init'?" >&2
    exit 1
fi

mkdir -p assets
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

# sips writes to the file it's given; work on copies.
for size in 16 32; do
    cp -- "$SRC" "$TMP/icon-$size.png"
    sips -z "$size" "$size" "$TMP/icon-$size.png" >/dev/null
    cp -- "$TMP/icon-$size.png" "assets/icon-$size.png"

    # Greyscale variant. --setProperty format-options 'grey' isn't enough —
    # some Safari versions render Grayscale PNGs oddly, so keep RGBA and
    # desaturate manually via matrix-based colour conversion.
    cp -- "$SRC" "$TMP/icon-grey-$size.png"
    sips -z "$size" "$size" "$TMP/icon-grey-$size.png" >/dev/null
    sips -m /System/Library/ColorSync/Profiles/Generic\ Gray\ Gamma\ 2.2\ Profile.icc \
        "$TMP/icon-grey-$size.png" >/dev/null
    sips --matchTo /System/Library/ColorSync/Profiles/sRGB\ Profile.icc \
        "$TMP/icon-grey-$size.png" >/dev/null
    cp -- "$TMP/icon-grey-$size.png" "assets/icon-grey-$size.png"
done

echo "wrote assets/icon-{16,32}.png and assets/icon-grey-{16,32}.png"
