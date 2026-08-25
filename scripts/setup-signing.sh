#!/usr/bin/env bash
# One-time setup for Developer ID Application signing + Apple notarization.
#
# Automates:
#   - CSR generation (openssl)
#   - Private-key import into login keychain
#   - Downloaded .cer detection + install
#   - notarytool credential storage (keychain profile)
#   - .envrc.local writing (Team ID, notary profile name)
#
# You still do manually:
#   1. Upload the CSR at developer.apple.com and download the .cer
#      (Apple has no public API for this)
#   2. Generate an app-specific password at appleid.apple.com
#      (Apple has no public API for this either)
#
# Idempotent: rerunning after a partial setup only does the steps still needed.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$REPO_ROOT"

WORK=".signing"
KEY_PATH="$WORK/developerID.key"
CSR_PATH="$WORK/developerID.certSigningRequest"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
NOTARY_PROFILE="hister-safari-notary"

mkdir -p "$WORK"
chmod 700 "$WORK"

# Strip leading/trailing whitespace (including CR from paste-crossing-newlines).
strip() {
    local v="$1"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    printf '%s' "$v"
}

have_cert() {
    security find-identity -v -p codesigning 2>/dev/null | grep -q 'Developer ID Application'
}

have_notary_profile() {
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1
}

# --- Step 1: CSR ---
if have_cert; then
    echo "==> Developer ID Application cert already installed:"
    security find-identity -v -p codesigning | grep 'Developer ID Application' | sed 's/^/    /'
else
    if [[ ! -f "$CSR_PATH" ]]; then
        echo "==> Generating CSR"
        read -r -p "    Common Name (e.g., 'Nicholas Burns'): " CN
        read -r -p "    Email address: " EMAIL
        CN="$(strip "$CN")"
        EMAIL="$(strip "$EMAIL")"
        openssl req -new -newkey rsa:2048 -nodes \
            -keyout "$KEY_PATH" \
            -out "$CSR_PATH" \
            -subj "/CN=$CN/emailAddress=$EMAIL" \
            2>/dev/null
        chmod 600 "$KEY_PATH"
        echo "    CSR: $CSR_PATH"
        echo "    Key: $KEY_PATH (imported into your login keychain below)"
    else
        echo "==> Reusing existing CSR at $CSR_PATH"
    fi

    # Import the private key so macOS can pair it with the downloaded cert.
    if ! security find-certificate -c "$(basename "$KEY_PATH")" "$KEYCHAIN" >/dev/null 2>&1; then
        echo "==> Importing private key into login keychain"
        security import "$KEY_PATH" -k "$KEYCHAIN" -T /usr/bin/codesign 2>/dev/null || true
    fi

    cat <<EOF

    -------------------------------------------------------------------
    MANUAL STEP 1 - Upload the CSR at Apple Developer:
      1. Open  https://developer.apple.com/account/resources/certificates/add
      2. Software section -> select "Developer ID Application"
      3. Continue -> upload the file below:
             $(pwd)/$CSR_PATH
      4. Continue -> Download the .cer to ~/Downloads/
    -------------------------------------------------------------------

EOF
    read -r -p "    Press Enter after you've downloaded the .cer to ~/Downloads/... "

    CER=""
    for candidate in "$HOME/Downloads/developerID_application.cer" "$HOME/Downloads/developerID.cer"; do
        [[ -f "$candidate" ]] && CER="$candidate" && break
    done
    if [[ -z "$CER" ]]; then
        CER="$(ls -t "$HOME/Downloads"/*.cer 2>/dev/null | head -1 || true)"
    fi
    if [[ -z "$CER" || ! -f "$CER" ]]; then
        echo "error: no .cer found in ~/Downloads/; drop it there and rerun." >&2
        exit 1
    fi

    echo "==> Installing $CER into login keychain"
    security import "$CER" -k "$KEYCHAIN" 2>/dev/null || true

    if ! have_cert; then
        echo "error: cert install did not produce a Developer ID identity. Check Keychain Access." >&2
        exit 1
    fi
    echo "    OK:"
    security find-identity -v -p codesigning | grep 'Developer ID Application' | sed 's/^/    /'
fi

# --- Step 2: Team ID ---
TEAM_ID="$(security find-identity -v -p codesigning | grep 'Developer ID Application' | head -1 \
    | sed -n 's/.*(\([A-Z0-9]\{10\}\)).*/\1/p')"
if [[ -z "$TEAM_ID" ]]; then
    read -r -p "    Team ID (10 uppercase alphanum): " TEAM_ID
    TEAM_ID="$(strip "$TEAM_ID")"
fi
echo "==> Team ID: $TEAM_ID"

# --- Step 3: notarytool keychain profile ---
if have_notary_profile; then
    echo "==> notarytool profile '$NOTARY_PROFILE' already stored"
else
    cat <<EOF

    -------------------------------------------------------------------
    MANUAL STEP 2 - App-specific password for notarization:
      1. Open  https://appleid.apple.com
      2. Sign in -> Sign In and Security -> App-Specific Passwords
      3. Click + and generate one labelled 'hister-safari-notary'
      4. Copy the 4-block password (xxxx-xxxx-xxxx-xxxx). Apple only
         shows it once.
    -------------------------------------------------------------------

EOF
    read -r -p "    Apple ID email: " APPLE_ID
    read -r -s -p "    App-specific password: " APP_PW; echo
    APPLE_ID="$(strip "$APPLE_ID")"
    APP_PW="$(strip "$APP_PW")"
    echo "==> Storing notarytool credentials as keychain profile '$NOTARY_PROFILE'"
    xcrun notarytool store-credentials "$NOTARY_PROFILE" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_PW"
fi

# --- Step 4: ExportOptions.plist Team ID ---
EXPORT_PLIST="Safari/ExportOptions.plist"
if grep -q "REPLACE_WITH_TEAM_ID" "$EXPORT_PLIST"; then
    echo "==> Patching $EXPORT_PLIST teamID -> $TEAM_ID"
    /usr/libexec/PlistBuddy -c "Set :teamID $TEAM_ID" "$EXPORT_PLIST"
fi

# --- Step 5: .envrc.local for build.sh ---
IDENTITY="$(security find-identity -v -p codesigning | grep 'Developer ID Application' | head -1 \
    | sed -n 's/^[[:space:]]*[0-9]\{1,\})[[:space:]]*[0-9A-F]\{40\}[[:space:]]*"\(.*\)"$/\1/p')"

cat > .envrc.local <<EOF
# Written by scripts/setup-signing.sh. Gitignored. Source before running scripts/build.sh:
#   source .envrc.local && NOTARIZE=1 scripts/build.sh
export CODE_SIGN_IDENTITY="$IDENTITY"
export APPLE_TEAM_ID="$TEAM_ID"
export HISTER_NOTARY_PROFILE="$NOTARY_PROFILE"
EOF

echo
echo "==> Done. Signing setup complete."
echo "    Sourced env: CODE_SIGN_IDENTITY, APPLE_TEAM_ID, HISTER_NOTARY_PROFILE"
echo "    Run a signed + notarized build:"
echo "        source .envrc.local && NOTARIZE=1 scripts/build.sh"
