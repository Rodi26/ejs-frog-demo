# Auth IAP programmatique depuis GitHub Actions (pas à pas)

Ce document décrit **une méthode** pour obtenir un jeton **accepté par Google Cloud IAP** (audience OAuth de l’application IAP), utilisable depuis un workflow GitHub Actions. Il complète [github-actions-jfrog-iap.md](github-actions-jfrog-iap.md) : le secret **`JF_ACCESS_TOKEN`** sert à **JFrog** une fois le trafic arrivé sur Artifactory ; **IAP** exige en général un **jeton Google** (OIDC) **distinct**, avec une **audience** liée au **client OAuth IAP**.

Les détails exacts (rôles IAM, noms de ressources) dépendent de votre projet GCP — ce guide reste **méthodologique** et renvoie à la doc Google pour les commandes officielles.

---

## 0. Ce que vous allez obtenir

| Couche | Rôle |
|--------|------|
| **IAP** (bordure HTTPS) | Vérifie un **ID token OAuth / OIDC** dont l’**audience** correspond au **OAuth 2.0 Client ID** configuré pour l’application protégée par IAP. |
| **Artifactory / JFrog** (application derrière IAP) | Utilise **`JF_ACCESS_TOKEN`** (ou autre mécanisme JFrog) **après** que la requête a été acceptée par IAP — selon votre architecture (souvent en-têtes ou réseau interne). |

Vous devez donc souvent combiner **deux** mécanismes d’auth dans la chaîne, pas un seul secret JFrog.

Référence Google : [Programmatic authentication](https://cloud.google.com/iap/docs/authentication-howto) (section *Authenticate a service account*, OIDC ID token avec audience = client ID IAP).

---

## 1. Prérequis côté Google Cloud (à faire une fois, avec un admin)

### 1.1 Identifier l’audience OAuth IAP

1. Console Google Cloud → **APIs & Services** → **Credentials**.
2. Repérer le **OAuth 2.0 Client ID** associé à votre backend **IAP** (souvent type *Web application*), ou suivre [OAuth client creation for IAP](https://cloud.google.com/iap/docs/oauth-client-creation) / [Sharing OAuth clients](https://cloud.google.com/iap/docs/sharing-oauth-clients).
3. Noter la valeur du client ID, typiquement :  
   `XXXXXXXXXXXX-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.apps.googleusercontent.com`  
   C’est l’**audience** attendue par IAP pour les **ID tokens** (OIDC).

### 1.2 Autoriser l’accès « programmatique » pour ce client

Suivre la doc Google : [Programmatic access allowlist](https://cloud.google.com/iap/docs/sharing-oauth-clients#programmatic_access) — le client OAuth utilisé pour les ID tokens doit être autorisé pour l’accès programmatique à l’application IAP concernée.

### 1.3 Compte de service (SA) pour la CI

1. Créer un **compte de service** dédié à la CI (ex. `github-ci-iap@PROJET.iam.gserviceaccount.com`), ou en réutiliser un.
2. Accorder à ce principal le droit d’**utiliser IAP** sur la ressource protégée : en pratique, l’ajouter comme utilisateur autorisé dans la configuration **IAP** du backend (Load Balancer / Backend Service / etc.), avec le rôle adapté (souvent accès « IAP-secured » / **HTTPS Resource Accessor** selon la console — voir [Managing access](https://cloud.google.com/iap/docs/managing-access)).

### 1.4 Permissions pour *émettre* des jetons OIDC (ID token)

Pour qu’un processus (CI) obtienne un **ID token** au nom du compte de service, les rôles IAM typiques sont décrits dans la même page Google : par exemple **Service Account OpenID Connect Identity Token Creator** (`roles/iam.serviceAccountOpenIdTokenCreator`) pour l’**usurpation** / génération de jetons, selon que vous utilisez une clé JSON, l’API IAM Credentials, ou **Workload Identity Federation**. Voir [Generate ID token](https://cloud.google.com/iam/docs/create-short-lived-credentials-direct#id).

---

## 2. Obtenir un ID token OIDC pour l’audience IAP (hors GitHub, test local)

Objectif : prouver qu’un jeton avec **`aud` = OAuth Client ID IAP** fonctionne contre votre URL.

La doc Google décrit notamment :

- **OIDC token for service account** avec **target audience = IAP client ID** : section *Authenticate with a service account OIDC token* dans [authentication-howto](https://cloud.google.com/iap/docs/authentication-howto).
- Exemples en Python / Node / Go utilisant la **client ID** comme *target audience* pour `GetOidcToken` / `getIdTokenClient`, etc.

En ligne de commande, une fois authentifié en tant que compte de service (ADC ou `gcloud auth activate-service-account`), on utilise souvent :

```bash
gcloud auth print-identity-token --audiences="IAP_OAUTH_CLIENT_ID.apps.googleusercontent.com"
```

(Vérifier les flags exacts pour votre version de `gcloud` : [`gcloud auth print-identity-token`](https://cloud.google.com/sdk/gcloud/reference/auth/print-identity-token).)

Test manuel :

```bash
TOKEN="$(gcloud auth print-identity-token --audiences="$IAP_OAUTH_CLIENT_ID")"
curl -sS -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer ${TOKEN}" "https://votre-host-iap/"
```

Si vous obtenez **401** avec message IAP sur ce test, le problème est encore côté IAM / audience / allowlist — pas côté JFrog.

---

## 3. Brancher ça sur GitHub Actions (sans clé JSON longue durée si possible)

Deux approches courantes :

### 3.A Workload Identity Federation (recommandé par Google pour CI)

1. Configurer un **Workload Identity Pool** + **Provider** qui fait confiance à **GitHub OIDC** (`token.actions.githubusercontent.com`).
2. Lier le compte de service GCP au dépôt / environnement GitHub souhaité.
3. Dans le workflow, utiliser l’action officielle **`google-github-actions/auth@v2`** (ou version courante) pour obtenir des **credentials** auprès de Google **sans** fichier de clé JSON permanent.

Documentation : [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation) et [GitHub](https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines).

### 3.B Clé JSON du compte de service (plus simple, plus risqué)

1. Créer une **clé** pour le compte de service (éviter si la politique de sécu l’interdit).
2. Stocker le JSON entier dans un **secret GitHub** (ex. `GCP_SA_KEY`).
3. Dans le workflow :  
   `echo '${{ secrets.GCP_SA_KEY }}' > sa.json` puis  
   `gcloud auth activate-service-account --key-file=sa.json`  
   puis `gcloud auth print-identity-token --audiences=...` comme en section 2.

Rotation et périmètre du secret : à gérer avec l’équipe sécurité.

---

## 4. Exemple d’enchaînement minimal dans un job (schéma)

Ordre logique des étapes (à adapter) :

1. **Checkout** (si besoin).
2. **`google-github-actions/auth`** — connexion à GCP (WIF ou clé).
3. **Shell** :  
   `export IAP_ID_TOKEN="$(gcloud auth print-identity-token --audiences="$IAP_OAUTH_CLIENT_ID")"`  
   (en passant le client ID par `vars` / `secrets`.)
4. **Requêtes vers l’URL IAP** : pour les outils qui acceptent un en-tête personnalisé, envoyer **`Authorization: Bearer $IAP_ID_TOKEN`** pour franchir IAP.
5. **JFrog** : selon votre installation, configurer ensuite **`JF_ACCESS_TOKEN`** / `jf` pour parler à Artifactory **une fois** IAP passé (souvent via proxy interne, double auth, ou chemin réseau — **à valider avec l’équipe qui a posé IAP devant Artifactory**).

Important : le CLI **`jf`** envoie typiquement **`Authorization: Bearer` + jeton JFrog**. Si IAP exige **son** Bearer en premier, il peut y avoir **conflit** sur un seul en-tête : solutions possibles = **proxy** qui termine IAP, **hostname** sans IAP pour l’API CI, ou **split** des responsabilités réseau — ce n’est pas résolvable uniquement par un secret JFrog.

---

## 5. Vérifications en cas d’échec

| Symptôme | Piste |
|----------|--------|
| `Invalid IAP credentials: JWT signature is invalid` | Jeton **non** OIDC Google pour l’audience IAP, ou mauvaise audience / client pas en allowlist programmatique. |
| `403` IAP après un `200` sur le token | Principal (SA) pas autorisé sur la ressource IAP. |
| IAP OK mais JFrog refuse | Couche Artifactory : **`JF_ACCESS_TOKEN`**, droits repo, etc. |

---

## 6. Références Google (à lire dans l’ordre)

1. [Programmatic authentication (IAP)](https://cloud.google.com/iap/docs/authentication-howto) — OIDC service account, audience OAuth client ID.  
2. [Sharing OAuth clients & programmatic access](https://cloud.google.com/iap/docs/sharing-oauth-clients).  
3. [Managing IAP access](https://cloud.google.com/iap/docs/managing-access).  
4. [Generate short-lived credentials / ID token](https://cloud.google.com/iam/docs/create-short-lived-credentials-direct#id).  
5. [gcloud auth print-identity-token](https://cloud.google.com/sdk/gcloud/reference/auth/print-identity-token).

---

## 7. Lien avec ce dépôt

Le workflow [`gh-ejs-demo`](../.github/workflows/workflow.yml) n’implémente **pas** encore les étapes 3–4 ci-dessus : elles dépendent de votre **projet GCP**, du **client OAuth IAP**, et du choix WIF vs clé. Ce fichier sert de **modèle réutilisable** pour un autre repo ou une évolution future du même pipeline.
