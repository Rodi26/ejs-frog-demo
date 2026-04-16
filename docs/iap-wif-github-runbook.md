# Runbook : IAP + Workload Identity Federation + GitHub Actions

Guide **réutilisable** pour plusieurs dépôts GitHub pointant vers le **même projet GCP** et la même instance Artifactory derrière IAP.

---

## Vue d’ensemble

| Élément | Rôle |
|---------|------|
| **IAP** | Valide un **ID token Google** (`Authorization: Bearer`) avec **audience** = OAuth 2.0 Client ID de l’appli IAP. |
| **Workload Identity Federation (WIF)** | Permet à GitHub Actions d’obtenir des credentials **sans clé JSON** longue durée, via OIDC `token.actions.githubusercontent.com`. |
| **JFrog** | `JF_ACCESS_TOKEN` authentifie auprès d’Artifactory **une fois le trafic autorisé** ; si un seul en-tête `Authorization` ne peut pas porter les deux jetons, voir votre équipe plateforme (proxy, hostname dédié, config ingress). |

Références Google : [Programmatic authentication (IAP)](https://cloud.google.com/iap/docs/authentication-howto), [WIF + pipelines de déploiement](https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines).

---

## Phase 1 — Preuve locale (gcloud sur votre poste)

Objectif : un `curl` vers l’URL Artifactory avec **uniquement** le jeton IAP retourne autre chose qu’un **401 `Invalid IAP credentials`**.

**Script automatisé (recommandé)** : après avoir exporté `IAP_OAUTH_CLIENT_ID` et `JF_URL`, exécuter [`scripts/iap-phase1-local-verify.sh`](../scripts/iap-phase1-local-verify.sh) (voir [`scripts/README.md`](../scripts/README.md)).

1. **Projet et compte actifs**

   ```bash
   gcloud config get-value project
   gcloud auth list
   ```

2. **Compte de service CI** (créer si besoin)

   ```bash
   # Remplacez PROJECT_ID et un nom de SA cohérent
   gcloud iam service-accounts create github-ci-iap \
     --project=PROJECT_ID \
     --display-name="GitHub Actions IAP"
   ```

3. **IAM sur le SA** — droits pour émettre des ID tokens (selon votre chemin ; souvent impersonation / rôles décrits dans [Generate ID token](https://cloud.google.com/iam/docs/create-short-lived-credentials-direct#id)).

4. **IAP** — dans la console IAP, ajoutez le **principal** `github-ci-iap@PROJECT_ID.iam.gserviceaccount.com` avec le rôle attendu pour votre ressource (ex. accès application protégée par IAP).

5. **Authentifiez-vous en tant que SA** (ex. clé JSON **temporaire** pour le test, ou `gcloud auth activate-service-account --key-file=...`).

6. **Jeton IAP + curl** (remplacez `CLIENT_ID` et l’URL)

   ```bash
   export IAP_OAUTH_CLIENT_ID="VOTRE_CLIENT_ID.apps.googleusercontent.com"
   export JF_URL="https://artifactory.example.org/"
   TOKEN=$(gcloud auth print-identity-token --audiences="${IAP_OAUTH_CLIENT_ID}")
   curl -sS -o /dev/null -w "HTTP %{http_code}\n" \
     -H "Authorization: Bearer ${TOKEN}" \
     "${JF_URL}artifactory/api/system/ping"
   ```

   Tant que vous voyez **401** avec message IAP, corrigez **audience**, **allowlist programmatic** pour ce client OAuth, et **accès IAP** du SA — pas la couche JFrog.

---

## Phase 2 — Workload Identity Federation (une fois par projet GCP)

Objectif : GitHub Actions obtient les mêmes capacités que le test local, **sans** stocker une clé JSON dans le dépôt.

**Méthode recommandée (IaC)** : module Terraform [`terraform/gcp-wif-github/`](../terraform/gcp-wif-github/README.md) — `terraform init` / `plan` / `apply`, puis copier les **outputs** (`workload_identity_provider`, `service_account_email`) dans les secrets GitHub.

**Alternative shell** : [`scripts/iap-wif-bootstrap.sh`](../scripts/iap-wif-bootstrap.sh) (variables `PROJECT_ID`, `POOL_ID`, `PROVIDER_ID`, `GITHUB_ORG`, `SA_ID` ; optionnel `GITHUB_REPO`, `DRY_RUN=1`). Pour un **deuxième dépôt** avec binding par repo, voir [`scripts/iap-wif-add-repo.sh`](../scripts/iap-wif-add-repo.sh).

Les détails et variantes restent dans la doc officielle [Configurer le déploiement depuis GitHub](https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines) (pool, provider OIDC GitHub, liaison du **SA** avec `roles/iam.workloadIdentityUser`).

Éléments à noter pour les **secrets GitHub** du dépôt :

| Secret | Exemple de contenu |
|--------|---------------------|
| `WORKLOAD_IDENTITY_PROVIDER` | `projects/123456789/locations/global/workloadIdentityPools/POOL_ID/providers/PROVIDER_ID` |
| `GCP_WIF_SERVICE_ACCOUNT` | `github-ci-iap@PROJECT_ID.iam.gserviceaccount.com` |

Variables GitHub (org ou repo) :

| Variable | Exemple |
|----------|---------|
| `IAP_USE_WIF` | `true` pour activer l’auth dans le workflow |
| `IAP_OAUTH_CLIENT_ID` | `xxxx.apps.googleusercontent.com` |
| `GCP_PROJECT_ID` | `mon-projet-gcp` |

---

## Ajouter un **deuxième** dépôt GitHub

1. Dans **IAM**, sur le binding qui attache le SA au **principal** WIF, **élargir la condition** pour inclure le nouveau dépôt (ex. `attribute.repository == "org/autre-repo"` ou liste de repos).
2. Dans le **nouveau dépôt** : créer les **mêmes** secrets `WORKLOAD_IDENTITY_PROVIDER` et `GCP_WIF_SERVICE_ACCOUNT`, et les **mêmes** variables `IAP_*` / `GCP_PROJECT_ID` si identiques.
3. Copier le **même bloc** de job (ou utiliser un [workflow réutilisable](https://docs.github.com/en/actions/using-workflows/reusing-workflows) dans un repo « platform »).

---

## Workflow dans ce dépôt

Le job `gh-ejs-demo` de [.github/workflows/workflow.yml](../.github/workflows/workflow.yml) :

- Si **`vars.IAP_USE_WIF`** vaut `true` : authentification WIF, `gcloud`, `gcloud auth print-identity-token --audiences=...`, variable d’environnement **`IAP_ID_TOKEN`**.
- Étape de vérification : si `IAP_ID_TOKEN` est défini, un **`curl`** vers `/artifactory/api/system/ping` avec ce jeton ; puis **`jf rt ping`** avec `JF_ACCESS_TOKEN` comme aujourd’hui.

| Variable | Exemple | Obligatoire si `IAP_USE_WIF=true` |
|----------|---------|-----------------------------------|
| `IAP_USE_WIF` | `true` | Oui pour activer WIF |
| `IAP_OAUTH_CLIENT_ID` | `xxx.apps.googleusercontent.com` | Oui |
| `GCP_PROJECT_ID` | `mon-projet` | Recommandé pour `setup-gcloud` |

| Secret | Obligatoire si `IAP_USE_WIF=true` |
|--------|-----------------------------------|
| `WORKLOAD_IDENTITY_PROVIDER` | Oui |
| `GCP_WIF_SERVICE_ACCOUNT` | Oui |

Tant que **deux** authentifications ne peuvent pas coexister sur une seule requête HTTP sortante de `jf`, l’étape `curl` valide surtout la **couche IAP** ; le comportement de **`jf`** dépend de votre configuration derrière le load balancer.

---

## Dépannage

| Symptôme | Piste |
|----------|--------|
| `Invalid IAP credentials: JWT signature is invalid` | Jeton non OIDC IAP ou mauvaise **audience** ; pas le secret JFrog. |
| WIF : permission denied | Condition IAM `repository` trop restrictive ; mauvais `WORKLOAD_IDENTITY_PROVIDER`. |
| IAP OK au `curl`, `jf` toujours KO | Conflit `Authorization` ou auth Artifactory uniquement après IAP — traiter avec l’équipe infra. |

Voir aussi [github-actions-jfrog-iap.md](github-actions-jfrog-iap.md).
