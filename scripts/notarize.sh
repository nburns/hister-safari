#!/usr/bin/env bash
# Notarize an already-signed .app with Apple, then staple the ticket.
#
# Required environment:
#   APPLE_NOTARY_USER      Apple ID email
#   APPLE_NOTARY_PASSWORD  App-specific password (not the account password)
#   APPLE_TEAM_ID          10-character team ID

set -euo pipefail

APP="${1:?usage: notarize.sh <path-to-app>}"

: "${APPLE_NOTARY_USER:?}"
: "${APPLE_NOTARY_PASSWORD:?}"
: "${APPLE_TEAM_ID:?}"

WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT
ZIP="$WORK/Hister.zip"

echo "==> Zipping $APP"
ditto -c -k --keepParent -- "$APP" "$ZIP"

echo "==> Submitting to Apple notary service (this can take several minutes)"
xcrun notarytool submit "$ZIP" \
    --apple-id "$APPLE_NOTARY_USER" \
    --password "$APPLE_NOTARY_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait

echo "==> Stapling ticket"
xcrun stapler staple -- "$APP"
xcrun stapler validate -- "$APP"
