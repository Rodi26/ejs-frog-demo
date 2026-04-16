# Scripts IAP / WIF

| Script | Rôle |
|--------|------|
| [iap-phase1-local-verify.sh](iap-phase1-local-verify.sh) | **Phase 1** : depuis votre machine, émettre un ID token IAP et tester `curl` sur `/artifactory/api/system/ping`. |
| [iap-wif-bootstrap.sh](iap-wif-bootstrap.sh) | **Phase 2** : créer le pool WIF, le provider GitHub OIDC, le compte de service et le binding `roles/iam.workloadIdentityUser` (une fois par projet). |
| [iap-wif-add-repo.sh](iap-wif-add-repo.sh) | Optionnel : ajouter un binding **par dépôt** (`attribute.repository/owner/name`) pour un second repo. |

Documentation : [docs/iap-wif-github-runbook.md](../docs/iap-wif-github-runbook.md).

```bash
chmod +x scripts/*.sh
```
