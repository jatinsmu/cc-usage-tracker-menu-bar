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
# Resolve the macOS SDK that matches the active toolchain. Hardcoding the CLT
# path breaks when Xcode is selected (its swiftc can't read the CLT SDK's
# swiftmodule). xcrun returns the right SDK for both CLT-only and Xcode setups;
# fall back to the CLT path if xcrun can't answer.
SDK="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
if [[ -z "${SDK}" || ! -d "${SDK}" ]]; then
    SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
fi
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

# Signing mode:
#   CCUSAGEBAR_SKIP_SIGN=1   -- no codesign at all (CI compile check)
#   CCUSAGEBAR_ADHOC_SIGN=1  -- ad-hoc sign ("-"); used by the release workflow,
#                               which has no stable identity. Distributed builds
#                               are ad-hoc by necessity (no Developer ID); each
#                               downloaded update re-prompts Keychain access once.
#   (default)                -- stable self-signed identity for LOCAL rebuilds, so
#                               the Keychain ACL persists. Don't use ad-hoc here.
if [[ "${CCUSAGEBAR_SKIP_SIGN:-0}" == "1" || "${CCUSAGEBAR_ADHOC_SIGN:-0}" == "1" ]]; then
    echo "[skip] not creating a local signing identity"
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
elif [[ "${CCUSAGEBAR_ADHOC_SIGN:-0}" == "1" ]]; then
    echo "Ad-hoc signing (release build, no stable identity)..."
    codesign --force --deep --sign - "${APP_BUNDLE}"
    echo "[ok] Ad-hoc signed."
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
