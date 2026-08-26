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
#
# Timeouts / retries:
#   NOTARY_TIMEOUT_SEC     Wall-clock cap for the whole submission (default
#                          5400 = 90 min). notarytool's own --wait was
#                          observed to lose a 2h-old submission to a single
#                          network hiccup, so we submit without --wait and
#                          poll `notarytool info` ourselves with backoff so a
#                          transient failure only costs one poll, not the
#                          whole submission.

set -euo pipefail

TARGET="${1:?usage: notarize.sh <path-to-app-or-dmg>}"
NOTARY_TIMEOUT_SEC="${NOTARY_TIMEOUT_SEC:-5400}"

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

# Build the auth args once; every notarytool call reuses them.
AUTH_ARGS=()
if [[ -n "${HISTER_NOTARY_PROFILE:-}" ]]; then
    AUTH_ARGS=(--keychain-profile "$HISTER_NOTARY_PROFILE")
else
    : "${APPLE_NOTARY_USER:?set HISTER_NOTARY_PROFILE, or APPLE_NOTARY_USER/PASSWORD/TEAM_ID}"
    : "${APPLE_NOTARY_PASSWORD:?}"
    : "${APPLE_TEAM_ID:?}"
    AUTH_ARGS=(
        --apple-id "$APPLE_NOTARY_USER"
        --password "$APPLE_NOTARY_PASSWORD"
        --team-id  "$APPLE_TEAM_ID"
    )
fi

echo "==> Submitting to Apple notary service"
SUBMIT_JSON="$WORK/submit.json"
xcrun notarytool submit "$SUBMIT" "${AUTH_ARGS[@]}" --output-format json \
    > "$SUBMIT_JSON"
SUBMISSION_ID="$(/usr/bin/plutil -extract id raw -o - -- "$SUBMIT_JSON")"
if [[ -z "$SUBMISSION_ID" || "$SUBMISSION_ID" == "null" ]]; then
    echo "error: could not extract submission id from notarytool output:" >&2
    cat -- "$SUBMIT_JSON" >&2
    exit 1
fi
echo "==> Submission id: $SUBMISSION_ID"

# Poll with backoff. Transient network failures only cost the current
# iteration; only wall-clock timeout or a terminal Apple verdict ends the
# loop.
START="$(date +%s)"
DEADLINE=$(( START + NOTARY_TIMEOUT_SEC ))
BACKOFF=15
INFO_JSON="$WORK/info.json"

while :; do
    NOW="$(date +%s)"
    ELAPSED=$(( NOW - START ))
    if (( NOW >= DEADLINE )); then
        echo "error: notarization timed out after ${ELAPSED}s (submission $SUBMISSION_ID)" >&2
        echo "       resume manually with: xcrun notarytool info $SUBMISSION_ID <auth args>" >&2
        exit 1
    fi

    if xcrun notarytool info "$SUBMISSION_ID" "${AUTH_ARGS[@]}" \
            --output-format json > "$INFO_JSON" 2> "$WORK/info.err"; then
        STATUS="$(/usr/bin/plutil -extract status raw -o - -- "$INFO_JSON" 2>/dev/null || echo "unknown")"
        case "$STATUS" in
            Accepted)
                echo "==> Notarization Accepted (elapsed ${ELAPSED}s)"
                break
                ;;
            Invalid|Rejected)
                echo "error: notarization $STATUS (submission $SUBMISSION_ID)" >&2
                echo "==> Fetching notary log:" >&2
                xcrun notarytool log "$SUBMISSION_ID" "${AUTH_ARGS[@]}" >&2 || true
                exit 1
                ;;
            *)
                # "In Progress" or a status we don't recognise; keep waiting.
                echo "==> Status: $STATUS (elapsed ${ELAPSED}s, next poll in ${BACKOFF}s)"
                ;;
        esac
    else
        echo "warn: notarytool info failed transiently after ${ELAPSED}s; retrying in ${BACKOFF}s" >&2
        sed 's/^/  /' -- "$WORK/info.err" >&2 || true
    fi

    sleep "$BACKOFF"
    # Exponential backoff, capped at 60s so we still notice a quick flip
    # from In Progress to Accepted without a long tail.
    if (( BACKOFF < 60 )); then
        BACKOFF=$(( BACKOFF * 2 ))
        (( BACKOFF > 60 )) && BACKOFF=60
    fi
done

echo "==> Stapling ticket"
xcrun stapler staple -- "$TARGET"
xcrun stapler validate -- "$TARGET"
