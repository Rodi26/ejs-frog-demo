# Terraform — GitHub Actions repository variables (JFrog / IAP)

Crée ou met à jour les **variables de configuration** du dépôt GitHub (`Settings → Secrets and variables → Actions → Variables`) attendues par les workflows de ce repo :

| Variable | Usage |
|----------|--------|
| `IAP_USE_WIF` | `true` / `false` — active les étapes WIF + JWT IAP |
| `GCP_PROJECT_ID` | Projet GCP (gcloud / IAP) |
| `JF_HOST` | Hostname public Artifactory (sans `https://`) |
| `JF_PROJECT_KEY` | Clé projet JFrog Platform |
| `IAP_OAUTH_CLIENT_ID` | Client OAuth IAP (`*.apps.googleusercontent.com`) |
| `JF_HOST_CLI` | (optionnel) Second hostname pour `jf` |
| `JF_DOCKER_USERNAME` | (optionnel) Utilisateur Docker / Artifactory |

**Secrets** (`JF_ACCESS_TOKEN`, `WORKLOAD_IDENTITY_PROVIDER`, `GCP_WIF_SERVICE_ACCOUNT`, etc.) ne sont **pas** gérés ici : les ajouter manuellement ou étendre Terraform avec [`github_actions_secret`](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_secret) si tu acceptes le secret dans le state.

## Prérequis

- [Terraform](https://www.terraform.io/) >= 1.3  
- Accès à l’API GitHub avec droits sur les **Actions variables** du dépôt.

**Token sans copier un PAT à la main** : si [GitHub CLI](https://cli.github.com/) est connecté (`gh auth login`), utilise le jeton de session :

```bash
export TF_VAR_github_token="$(gh auth token -h github.com)"
```

Sinon, un [PAT](https://github.com/settings/tokens) classique avec scope **repo** (dépôt privé) convient aussi.

## Utilisation

```bash
cd terraform/github-actions-variables
cp terraform.tfvars.example terraform.tfvars
# Éditer terraform.tfvars (sans commit : fichier gitignoré)
export TF_VAR_github_token="$(gh auth token -h github.com)"

terraform init
terraform plan
terraform apply
```

### Variables déjà créées dans l’UI GitHub

Si `terraform apply` renvoie **409 Already exists**, importer chaque variable puis réappliquer :

```bash
export TF_VAR_github_token="$(gh auth token -h github.com)"
terraform import 'github_actions_variable.repo["JF_HOST"]' 'ejs-frog-demo:JF_HOST'
# … répéter pour chaque clé (format ID : `<nom_du_depot>:<NOM_VARIABLE>`)
terraform plan   # doit afficher « No changes »
```

Le provider **`integrations/github`** utilise `owner` + nom de dépôt ; voir [`variables.tf`](variables.tf).

## Voir aussi

- Module GCP WIF : [../gcp-wif-github/README.md](../gcp-wif-github/README.md)  
- Documentation IAP : [../../docs/github-actions-jfrog-iap.md](../../docs/github-actions-jfrog-iap.md)
