#!/usr/bin/env bash
# Phase 1 — Vérifier localement IAP + ID token (sans JFrog) avant WIF.
# Prérequis : gcloud installé ; compte de service autorisé sur IAP ; OAuth client IAP en allowlist programmatique.
# Usage :
#   export IAP_OAUTH_CLIENT_ID="xxxx.apps.googleusercontent.com"
#   export JF_URL="https://artifactory.example.org/"   # slash final OK
#   # Puis soit ADC avec un SA :
#   export GOOGLE_APPLICATION_CREDENTIALS=/chemin/vers/sa-key.json   # optionnel
#   ./scripts/iap-phase1-local-verify.sh
#
# Référence : https://cloud.google.com/iap/docs/authentication-howto

set -euo pipefail

: "${IAP_OAUTH_CLIENT_ID:?Set IAP_OAUTH_CLIENT_ID (OAuth 2.0 Client ID IAP)}"
: "${JF_URL:?Set JF_URL (ex. https://artifactory.example.org/)}"

echo "=== gcloud project ==="
gcloud config get-value project 2>/dev/null || true
echo "=== gcloud account (active) ==="
gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null || true

echo "=== Issuing identity token for IAP audience ==="
TOKEN="$(gcloud auth print-identity-token --audiences="${IAP_OAUTH_CLIENT_ID}")"
if [[ -z "${TOKEN}" ]]; then
  echo "ERROR: empty token from gcloud auth print-identity-token" >&2
  exit 1
fi

PING_URL="${JF_URL%/}/artifactory/api/system/ping"
echo "=== curl Artifactory ping (Authorization: Bearer <Google ID token> only) ==="
echo "URL: ${PING_URL}"
code="$(curl -sS -o /tmp/iap_ping_body.txt -w "%{http_code}" \
  -H "Authorization: Bearer ${TOKEN}" \
  "${PING_URL}" || echo "000")"
echo "HTTP ${code}"
if [[ "${code}" == "401" ]] || [[ "${code}" == "403" ]]; then
  echo "Body (first 200 chars):"
  head -c 200 /tmp/iap_ping_body.txt 2>/dev/null || true
  echo ""
  echo "FAIL: Still blocked at IAP or backend. Fix audience, programmatic allowlist, or IAP principal for this identity." >&2
  exit 1
fi

echo "OK: IAP layer accepted the request (HTTP ${code}). Next: Phase 2 WIF (scripts/iap-wif-bootstrap.sh)."
