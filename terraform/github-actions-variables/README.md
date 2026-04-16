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
- Un [Personal Access Token](https://github.com/settings/tokens) GitHub avec accès au dépôt cible (**repo** pour un dépôt privé, ou fine-grained avec *Variables* en lecture/écriture).

## Utilisation

```bash
cd terraform/github-actions-variables
cp terraform.tfvars.example terraform.tfvars
# Éditer terraform.tfvars ; pour le token :
export TF_VAR_github_token=ghp_...

terraform init
terraform plan
terraform apply
```

Le provider **`integrations/github`** utilise `owner` + nom de dépôt ; voir [`variables.tf`](variables.tf).

## Voir aussi

- Module GCP WIF : [../gcp-wif-github/README.md](../gcp-wif-github/README.md)  
- Documentation IAP : [../../docs/github-actions-jfrog-iap.md](../../docs/github-actions-jfrog-iap.md)
