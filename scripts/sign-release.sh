#!/usr/bin/env bash
# Re-signs the built Hyperactive.app.
#
# 1. MACOS_CERTIFICATE (Developer ID) when set. Optional notarization stays in
#    the workflow. This is the signature that also satisfies Gatekeeper.
# 2. Otherwise HYPERACTIVE_SIGNING_CERTIFICATE, a long-lived self-signed
#    identity. The designated requirement stays the same across versions, so
#    an Accessibility grant survives updates. Gatekeeper still warns.
# 3. Otherwise the ad-hoc signature from xcodebuild is left as-is. Each
#    release then has a new cdhash and macOS forgets the Accessibility grant.
set -euo pipefail

app="${APP_PATH:?Set APP_PATH to the built Hyperactive.app}"
entitlements="${ENTITLEMENTS:-Hyperactive/Hyperactive/Hyperactive.entitlements}"

if [[ -z "${MACOS_CERTIFICATE:-}" && -z "${HYPERACTIVE_SIGNING_CERTIFICATE:-}" ]]; then
  echo "No signing certificate secret is set. Leaving the ad-hoc signature."
  exit 0
fi

keychain="${RUNNER_TEMP:-/tmp}/signing.keychain-db"
keychain_password="${KEYCHAIN_PASSWORD:?Set KEYCHAIN_PASSWORD}"
p12=""

cleanup() {
  if [[ -n "$p12" ]]; then
    rm -f "$p12"
  fi
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
}
trap cleanup EXIT

security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"

p12="$(mktemp)"
if [[ -n "${MACOS_CERTIFICATE:-}" ]]; then
  mode="Developer ID"
  printf '%s' "$MACOS_CERTIFICATE" | base64 --decode > "$p12"
  import_password="${MACOS_CERTIFICATE_PWD:?Set MACOS_CERTIFICATE_PWD}"
else
  mode="self-signed"
  printf '%s' "$HYPERACTIVE_SIGNING_CERTIFICATE" | base64 --decode > "$p12"
  import_password="${HYPERACTIVE_SIGNING_CERTIFICATE_PWD:?Set HYPERACTIVE_SIGNING_CERTIFICATE_PWD}"
fi

security import "$p12" -k "$keychain" -P "$import_password" -T /usr/bin/codesign
rm -f "$p12"
p12=""
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain"
# shellcheck disable=SC2046
security list-keychains -d user -s "$keychain" $(security list-keychains -d user | tr -d '"')

if [[ "$mode" == "Developer ID" ]]; then
  identity="$(security find-identity -v -p codesigning "$keychain" | grep -o '"Developer ID Application: [^"]*"' | head -n 1 | tr -d '"')"
  if [[ -z "$identity" ]]; then
    echo "No 'Developer ID Application' identity found in MACOS_CERTIFICATE" >&2
    exit 1
  fi
  codesign --force --options runtime --timestamp \
    --entitlements "$entitlements" \
    --sign "$identity" "$app"
else
  identity="$(security find-identity -v -p codesigning "$keychain" | sed -n 's/.*"\([^"]*\)".*/\1/p' | head -n 1)"
  if [[ -z "$identity" ]]; then
    echo "No code signing identity found in HYPERACTIVE_SIGNING_CERTIFICATE" >&2
    security find-identity -v "$keychain" >&2 || true
    exit 1
  fi
  # Apple's timestamp server accepts Developer ID certificates only.
  codesign --force --options runtime \
    --entitlements "$entitlements" \
    --sign "$identity" "$app"
fi

echo "Signed with $mode identity: $identity"
echo "Designated requirement (this must stay the same across versions):"
codesign -d -r- "$app"
