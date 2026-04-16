#!/usr/bin/env bash
# Ajouter un dépôt GitHub supplémentaire au même pool WIF en créant un binding IAM dédié
# (lorsque vous utilisez principalSet ... attribute.repository/OWNER/REPO par repo).
#
# Variables :
#   PROJECT_ID, POOL_ID, SA_ID  — comme pour iap-wif-bootstrap.sh
#   GITHUB_REPO                 — ex. Rodi26/autre-repo
#
# Référence : https://cloud.google.com/iam/docs/workload-identity-federation#principal-types

set -euo pipefail

: "${PROJECT_ID:?}"
: "${POOL_ID:?}"
: "${GITHUB_REPO:?}"
: "${SA_ID:?}"

SA_EMAIL="${SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"

MEMBER="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${GITHUB_REPO}"

gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="${MEMBER}"

echo "Granted workloadIdentityUser for ${MEMBER} -> ${SA_EMAIL}"
