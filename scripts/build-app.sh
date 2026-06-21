#!/usr/bin/env bash
# Build CCUsageBar.app, assemble the bundle, and codesign with a stable
# self-signed identity so the Keychain ACL persists across rebuilds.
#
# Uses swiftc directly (not swift build) to work with CLT-only setups where
# xcrun --show-sdk-platform-path is unavailable.
set -euo pipefail

IDENTITY_NAME="CCUsageBar"
APP_NAME="CCUsageBar"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
TARGET=arm64-apple-macosx13.0
OUT_DIR="${REPO_DIR}/.build/release"
APP_BUNDLE="${REPO_DIR}/${APP_NAME}.app"

# ── 1. Ensure we have a stable self-signed code-signing identity ─────────────
ensure_identity() {
    if security find-identity -v -p codesigning 2>/dev/null \
            | grep -q "\"${IDENTITY_NAME}\""; then
        echo "[ok] Signing identity '${IDENTITY_NAME}' already exists"
        return 0
    fi

    echo "Creating stable self-signed code-signing identity '${IDENTITY_NAME}'..."
    local tmpd
    tmpd=$(mktemp -d)

    cat > "${tmpd}/cert.cfg" <<'CERTEOF'
[req]
prompt             = no
distinguished_name = dn
x509_extensions    = ext

[dn]
CN = CCUsageBar

[ext]
basicConstraints = CA:FALSE
keyUsage         = critical, digitalSignature
extendedKeyUsage = codeSigning
CERTEOF

    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "${tmpd}/key.pem" \
        -out    "${tmpd}/cert.pem" \
        -days   3650 \
        -config "${tmpd}/cert.cfg" 2>/dev/null

    # Import cert and key separately (PKCS12 MAC verification fails on macOS 26+)
    security import "${tmpd}/cert.pem" \
        -k ~/Library/Keychains/login.keychain-db

    # -T /usr/bin/codesign: allow codesign to use the key without per-run dialog
    security import "${tmpd}/key.pem" \
        -k ~/Library/Keychains/login.keychain-db \
        -T /usr/bin/codesign -A

    # Trust the cert for code-signing in the user domain.
    # macOS will show one authorisation dialog here (expected; one-time only).
    security add-trusted-cert \
        -r trustRoot \
        -p codeSign \
        -k ~/Library/Keychains/login.keychain-db \
        "${tmpd}/cert.pem"

    rm -rf "${tmpd}"
    echo "[ok] Identity '${IDENTITY_NAME}' created and trusted."
    echo "     (A dialog above is the one-time setup prompt -- expected.)"
}

# Set CCUSAGEBAR_SKIP_SIGN=1 to skip identity setup and codesigning. Used by CI
# to verify the build path compiles and assembles without Keychain access.
if [[ "${CCUSAGEBAR_SKIP_SIGN:-0}" == "1" ]]; then
    echo "[skip] CCUSAGEBAR_SKIP_SIGN=1 -- skipping signing identity setup"
else
    ensure_identity
fi

# ── 2. Compile with swiftc ────────────────────────────────────────────────────
echo ""
echo "Compiling ${APP_NAME}..."
mkdir -p "${OUT_DIR}"

# Collect all Swift sources recursively (compatible with macOS bash 3.2)
SOURCES=()
while IFS= read -r f; do
    SOURCES+=("$f")
done < <(find "${REPO_DIR}/Sources/CCUsageBar" -name "*.swift" | sort)

swiftc \
    -sdk "${SDK}" \
    -target "${TARGET}" \
    -parse-as-library \
    -O \
    -module-name "${APP_NAME}" \
    -o "${OUT_DIR}/${APP_NAME}" \
    "${SOURCES[@]}"

echo "[ok] Compiled -> ${OUT_DIR}/${APP_NAME}"

# ── 3. Assemble .app bundle ───────────────────────────────────────────────────
echo ""
echo "Assembling ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${OUT_DIR}/${APP_NAME}"             "${APP_BUNDLE}/Contents/MacOS/"
cp "${REPO_DIR}/Resources/Info.plist"  "${APP_BUNDLE}/Contents/"
printf 'APPL????' > "${APP_BUNDLE}/Contents/PkgInfo"

# ── 4. Codesign ───────────────────────────────────────────────────────────────
if [[ "${CCUSAGEBAR_SKIP_SIGN:-0}" == "1" ]]; then
    echo "[skip] CCUSAGEBAR_SKIP_SIGN=1 -- skipping codesign"
else
    echo "Signing with '${IDENTITY_NAME}'..."
    codesign --force --deep --sign "${IDENTITY_NAME}" "${APP_BUNDLE}"
    echo "[ok] Signed."
fi

echo ""
echo "Done: ${APP_BUNDLE}"
echo "Launch: open \"${APP_BUNDLE}\""
echo ""
echo "First run: macOS may prompt for Keychain access -- click 'Always Allow'."
echo "Subsequent runs and rebuilds will NOT prompt again (stable identity)."
