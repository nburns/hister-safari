#!/usr/bin/env bash
# Notarize a .app or .dmg with Apple, then staple the ticket.
#
# .dmg is submitted directly (its ticket covers everything inside). .app is
# zipped first because notarytool won't accept a bare bundle.
#
# Auth (in order of preference):
#   HISTER_NOTARY_PROFILE  Keychain profile name saved via
#                          `xcrun notarytool store-credentials` (recommended;
#                          set by scripts/setup-signing.sh).
#   APPLE_NOTARY_USER      Apple ID email                (fallback path,
#   APPLE_NOTARY_PASSWORD  App-specific password          for CI where
#   APPLE_TEAM_ID          10-character team ID           storing a keychain
#                                                         profile isn't easy.)

set -euo pipefail

TARGET="${1:?usage: notarize.sh <path-to-app-or-dmg>}"

WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT

case "$TARGET" in
    *.dmg)
        SUBMIT="$TARGET"
        ;;
    *)
        SUBMIT="$WORK/$(basename "$TARGET").zip"
        echo "==> Zipping $TARGET"
        ditto -c -k --keepParent -- "$TARGET" "$SUBMIT"
        ;;
esac

echo "==> Submitting to Apple notary service (this can take several minutes)"
if [[ -n "${HISTER_NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$SUBMIT" \
        --keychain-profile "$HISTER_NOTARY_PROFILE" \
        --wait
else
    : "${APPLE_NOTARY_USER:?set HISTER_NOTARY_PROFILE, or APPLE_NOTARY_USER/PASSWORD/TEAM_ID}"
    : "${APPLE_NOTARY_PASSWORD:?}"
    : "${APPLE_TEAM_ID:?}"
    xcrun notarytool submit "$SUBMIT" \
        --apple-id "$APPLE_NOTARY_USER" \
        --password "$APPLE_NOTARY_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait
fi

echo "==> Stapling ticket"
xcrun stapler staple -- "$TARGET"
xcrun stapler validate -- "$TARGET"
