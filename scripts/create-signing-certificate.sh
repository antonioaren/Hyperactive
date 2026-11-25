#!/usr/bin/env bash
# Creates a long-lived self-signed code signing certificate for Hyperactive.
#
# The .p12 is a secret. Do not commit it. Store it in GitHub Actions:
#   HYPERACTIVE_SIGNING_CERTIFICATE      base64 of the .p12
#   HYPERACTIVE_SIGNING_CERTIFICATE_PWD  the password you set below
#
# Reuse this same file for every release. A new certificate is a new
# designated requirement, and macOS will forget the Accessibility grant.
#
# Usage:
#   export HYPERACTIVE_SIGNING_CERTIFICATE_PWD
#   scripts/create-signing-certificate.sh
set -euo pipefail

name="${1:-Hyperactive Signing}"
days="${2:-3650}"
out="${3:-hyperactive-signing.p12}"
: "${HYPERACTIVE_SIGNING_CERTIFICATE_PWD:?}"

workdir="$(mktemp -d)"
cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT

openssl req -x509 -newkey rsa:2048 -sha256 -days "$days" -nodes \
  -keyout "$workdir/key.pem" \
  -out "$workdir/cert.pem" \
  -subj "/CN=$name" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"

# -legacy writes a p12 that macOS `security import` accepts.
openssl pkcs12 -export -legacy \
  -inkey "$workdir/key.pem" \
  -in "$workdir/cert.pem" \
  -out "$out" \
  -name "$name" \
  -passout "pass:${HYPERACTIVE_SIGNING_CERTIFICATE_PWD}"

echo "Wrote $out"
echo
echo "Base64 for the HYPERACTIVE_SIGNING_CERTIFICATE secret:"
base64 < "$out"
echo
echo "Do not commit $out. Delete it after the secret is saved."
