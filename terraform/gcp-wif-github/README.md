# Terraform — Workload Identity Federation (GitHub Actions)

Provisionne dans **un projet GCP** :

- APIs : IAM, IAM Credentials, STS  
- **Workload Identity Pool** + **OIDC provider** `https://token.actions.githubusercontent.com`  
- **Compte de service** CI  
- Binding `roles/iam.workloadIdentityUser` pour les identités fédérées GitHub (soumis à la **attribute condition**)

## Prérequis

- [Terraform](https://www.terraform.io/) >= 1.3  
- [Application Default Credentials](https://cloud.google.com/docs/authentication/provide-credentials-adc) avec un compte ayant les droits IAM suffisants (ex. `roles/owner` ou `roles/iam.securityAdmin` + création de SA).

## Utilisation

```bash
cd terraform/gcp-wif-github
cp terraform.tfvars.example terraform.tfvars
# Éditer terraform.tfvars (project_id, github_org, …)

terraform init
terraform plan
terraform apply
```

Copier les **outputs** vers les secrets / variables GitHub du dépôt :

| Output Terraform | Où sur GitHub |
|------------------|----------------|
| `workload_identity_provider` | Secret `WORKLOAD_IDENTITY_PROVIDER` |
| `service_account_email` | Secret `GCP_WIF_SERVICE_ACCOUNT` |
| (voir hint) | Vars `IAP_USE_WIF`, `GCP_PROJECT_ID`, `IAP_OAUTH_CLIENT_ID` |

Documentation dépôt : [docs/iap-wif-github-runbook.md](../../docs/iap-wif-github-runbook.md).

## Ce que Terraform ne fait pas

- **IAP** : ajouter le **compte de service** comme principal autorisé sur la ressource protégée par IAP (Backend Service / autre) se fait encore souvent dans la console ou via des ressources IAP spécifiques à ton LB — à traiter avec ton équipe plateforme.  
- **OAuth Client ID IAP** : reste une valeur à copier depuis **APIs & Services → Credentials** ou l’écran IAP.

## Variables

| Variable | Description |
|----------|-------------|
| `project_id` | ID du projet GCP. |
| `github_org` | Organisation (ou user) GitHub pour `assertion.repository_owner`. |
| `restrict_to_single_repo` | Si `true`, utiliser `github_repo_full` au lieu du filtre org seul. |
| `pool_id` / `provider_id` | IDs du pool et du provider OIDC. |
| `service_account_id` | ID court du compte de service. |
