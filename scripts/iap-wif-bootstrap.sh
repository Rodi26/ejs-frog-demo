#!/usr/bin/env bash
# Phase 2 — Créer pool + provider OIDC GitHub + lier le compte de service (Workload Identity Federation).
# À exécuter une fois par projet GCP (admin IAM). Réutilisable pour d’autres repos : voir scripts/iap-wif-add-repo.sh
#
# Variables obligatoires :
#   PROJECT_ID          Projet GCP (id string)
#   POOL_ID             Id du pool (ex. github-pool)
#   PROVIDER_ID         Id du provider (ex. github-provider)
#   GITHUB_ORG          Organisation ou user GitHub (ex. Rodi26)
#   SA_ID               Nom court du compte de service (ex. github-ci-iap) — email = SA_ID@PROJECT_ID.iam.gserviceaccount.com
#
# Optionnel :
#   GITHUB_REPO         Si défini, restreint l’IAM à un seul dépôt (ORG/REPO). Sinon, toute l’org via repository_owner.
#   DRY_RUN=1           Affiche les commandes sans les exécuter
#
# Référence : https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines

set -euo pipefail

: "${PROJECT_ID:?}"
: "${POOL_ID:?}"
: "${PROVIDER_ID:?}"
: "${GITHUB_ORG:?}"
: "${SA_ID:?}"

SA_EMAIL="${SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"

run() {
  if [[ "${DRY_RUN:-}" == "1" ]]; then
    echo "+ $*"
  else
    "$@"
  fi
}

echo "PROJECT_NUMBER=${PROJECT_NUMBER}"
echo "SA_EMAIL=${SA_EMAIL}"

run gcloud config set project "${PROJECT_ID}"

# APIs requises pour WIF + impersonation
run gcloud services enable iamcredentials.googleapis.com sts.googleapis.com iam.googleapis.com --project "${PROJECT_ID}"

run gcloud iam workload-identity-pools create "${POOL_ID}" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --display-name="GitHub Actions (${POOL_ID})" \
  --description="WIF pool for GitHub OIDC"

# Condition d’attribut : org entière (recommandé pour réutiliser plusieurs repos)
ATTR_CONDITION="assertion.repository_owner=='${GITHUB_ORG}'"
# Mapping minimal + repository pour principalSet par repo si besoin
ATTR_MAPPING="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner"

run gcloud iam workload-identity-pools providers create-oidc "${PROVIDER_ID}" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --workload-identity-pool="${POOL_ID}" \
  --display-name="GitHub OIDC" \
  --issuer-uri="https://token.actions.githubusercontent.com/" \
  --attribute-mapping="${ATTR_MAPPING}" \
  --attribute-condition="${ATTR_CONDITION}"

run gcloud iam service-accounts create "${SA_ID}" \
  --project="${PROJECT_ID}" \
  --display-name="GitHub Actions IAP" 2>/dev/null || echo "(service account may already exist)"

# Principal : par dépôt si GITHUB_REPO=org/name, sinon restreindre par attribut repository (premier repo seulement si tu préfères)
if [[ -n "${GITHUB_REPO:-}" ]]; then
  MEMBER="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${GITHUB_REPO}"
else
  # Toute identité du pool satisfaisant la condition du provider (même org)
  MEMBER="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/*"
fi

run gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="${MEMBER}"

PROVIDER_RESOURCE="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"

echo ""
echo "=== Add these to GitHub (repo or org secrets) ==="
echo "WORKLOAD_IDENTITY_PROVIDER=${PROVIDER_RESOURCE}"
echo "GCP_WIF_SERVICE_ACCOUNT=${SA_EMAIL}"
echo ""
echo "=== GitHub Actions vars ==="
echo "IAP_USE_WIF=true"
echo "GCP_PROJECT_ID=${PROJECT_ID}"
echo "IAP_OAUTH_CLIENT_ID=<your IAP OAuth client id>.apps.googleusercontent.com"
echo ""
echo "For a second repository in the same org, you typically only need to ensure workflows run under ${GITHUB_ORG} and reuse the same secrets. To lock to specific repos only, set GITHUB_REPO=org/name and use attribute.repository principalSet (see docs/iap-wif-github-runbook.md)."
