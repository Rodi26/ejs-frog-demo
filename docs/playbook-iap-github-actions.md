# Playbook : IAP (Google Cloud) et GitHub Actions — méthodologie réutilisable

Ce document décrit une **méthode pas à pas** pour diagnostiquer et corriger des échecs de CI lorsque des outils (JFrog CLI, Docker registry, API interne, etc.) sont appelés depuis des **runners GitHub hébergés** alors que la cible est protégée par **Identity-Aware Proxy (IAP)**. Vous pouvez **reprendre la même logique dans n’importe quel dépôt** qui utilise GitHub Actions.

---

## 1. Comprendre le problème (réutilisable tout service)

| Élément | Rôle |
|--------|------|
| **Runner GitHub** (`ubuntu-latest`, etc.) | Machine éphémère sur Internet, **pas** dans votre VPC GCP. |
| **IAP** | Situé devant HTTPS ; attend en général une **identité humaine** (OAuth Google) ou une configuration **non triviale** pour l’automatisation. |
| **Job CI** | Requêtes **non interactives** : pas de navigateur pour compléter un login Google. |

**Symptôme fréquent :** étape qui appelle un CLI ou `curl` vers `https://votre-service/` → **exit code 1**, timeout, HTML de login dans le corps de réponse, ou redirections en chaîne — **sans** message explicite « IAP » dans les logs GitHub.

**À ne pas confondre :** avertissements du type **Node.js 20 deprecated** sur les *actions* GitHub ; c’est un sujet de **runtime des actions**, pas la cause d’un blocage IAP.

---

## 2. Avant d’agir : inventaire minimal (checklist)

À remplir pour **chaque dépôt** (copier-colier dans une issue ou un ticket) :

- [ ] **URL exacte** utilisée par le workflow (variable `JF_HOST`, `REGISTRY_URL`, etc.).
- [ ] **Produit** derrière l’URL (JFrog, Artifact Registry, API custom, …).
- [ ] **IAP** est-il **documenté** comme actif sur ce hostname ou ce load balancer ? (équipe plateforme / GCP).
- [ ] Le workflow utilise **OIDC**, **token**, **Basic**, ou **rien** vers l’API ?
- [ ] Un **même job** fonctionne depuis un **runner auto-hébergé** ou une **machine interne** ?

---

## 3. Étape A — Confirmer que ce n’est pas un bug applicatif

1. Ouvrir le run GitHub en échec → **Annotations** et **logs** de la première étape rouge.
2. Noter : **nom de l’étape**, **code de sortie**, **dernières lignes** (souvent une URL ou un `curl` implicite).
3. Rejouer **localement** (même branche) avec les mêmes commandes si possible (sans secrets : dry-run ou mock).

Si **local OK** et **CI KO** → suspect **réseau / auth / IAP**, pas un simple bug de script.

---

## 4. Étape B — Preuve « IAP ou front qui impose un login »

Objectif : prouver que le runner **ne reçoit pas** une réponse API attendue.

### Option 1 — Job de diagnostic **temporaire** (recommandé)

Ajouter un job **dans une branche de test** (pas sur `main` si vous préférez) avec uniquement des commandes **lecture** :

```yaml
# Exemple minimal — à adapter (hostname, secrets interdits en clair)
jobs:
  iap-smoke:
    runs-on: ubuntu-latest
    steps:
      - name: TLS + HTTP smoke (no secrets)
        env:
          TARGET_HOST: ${{ vars.JF_HOST }}   # ou secret masqué côté repo
        run: |
          set -euo pipefail
          echo "Testing https://${TARGET_HOST}/"
          curl -sS -o /tmp/body.txt -w "%{http_code}" "https://${TARGET_HOST}/" | tee /tmp/code.txt
          echo "\n--- first 80 chars of body ---"
          head -c 80 /tmp/body.txt; echo
```

**Interprétation rapide :**

- **302/301** vers `accounts.google.com` → très fort signal **IAP / OAuth**.
- **200** avec HTML d’une page de login → même famille.
- **401/403** avec body non-JSON → à creuser (IAP, WAF, ou autre).

Supprimer ou désactiver ce job une fois le diagnostic fait.

### Option 2 — `curl` depuis une machine **déjà** autorisée (VPN / bureau)

Comparer le **code HTTP** et les **headers** avec ce que vous obtiendriez depuis un runner (via les logs du job ci-dessus). Écart = problème de **chemin réseau / identité**, pas de version d’outil.

---

## 5. Étape C — Cartographier où corriger (sans supposer une seule bonne réponse)

Les corrections **se décident** avec l’équipe sécurité / GCP. Voici des **pistes** classiques, **réutilisables d’un repo à l’autre** :

| Piste | Idée | Utile quand |
|-------|------|-------------|
| **Runner auto-hébergé** | GitHub Actions **dans** le réseau qui a déjà accès à JFrog / l’API. | IAP protège l’entrée Internet ; le trafic interne est autorisé autrement. |
| **Hostname séparé pour l’API / CI** | `jfrog-ci.example.com` non derrière IAP, strictement contrôlé (firewall, IP allowlist GitHub si acceptable). | Politique d’org accepte un endpoint « machine ». |
| **Backend service / identité de service** (selon config GCP) | IAP peut être configuré pour des **identités** non humaines ; à valider avec la doc GCP et votre équipe. | Besoin d’automatisation sans navigateur. |
| **Tunnel / VPN** vers le runner | Rare sur GitHub-hosted ; plutôt **self-hosted** ou **proxy** sortant. | Contraintes réseau très strictes. |

**Ce fichier ne remplace pas** la décision d’architecture : il structure **la demande** à faire aux bonnes équipes (réseau, sécurité, GCP).

---

## 6. Étape D — Après changement infra : valider le workflow

1. Déclencher **workflow_dispatch** (ou push) sur la branche de test.
2. Vérifier que l’étape **setup** (JFrog CLI, `docker login`, etc.) **passe**.
3. Garder une **trace** : lien vers le run vert + résumé de la solution (ticket / wiki) pour le **prochain dépôt** qui réutilisera ce playbook.

---

## 7. Réutiliser ce playbook dans un **autre** dépôt GitHub

1. Copier ce fichier (ou le lien vers ce repo) dans `docs/` du nouvel dépôt.
2. Remplacer les placeholders : **hostname**, **noms de secrets/vars**, **type d’outil** (JFrog, npm registry, etc.).
3. Adapter le **job de diagnostic** (section 4) sans y mettre de **secrets en clair** ; utiliser `vars` / `secrets` GitHub.
4. Aligner avec la **même** équipe plateforme : souvent une **seule** décision GCP (IAP, DNS, runner) sert **plusieurs** pipelines.

---

## 8. Références utiles

- [Google Cloud — Identity-Aware Proxy](https://cloud.google.com/iap/docs) (concept et modèles d’accès).
- [GitHub — Variables et secrets](https://docs.github.com/en/actions/security-guides/using-secrets-in-github-actions) pour les URLs et tokens sans les exposer.
- [GitHub Blog — dépréciation Node 20 sur les runners](https://github.blog/changelog/2025-09-19-deprecation-of-node-20-on-github-actions-runners/) (pour les avertissements d’actions, pas IAP).

---

## 9. Lien avec ce dépôt

Le workflow [`gh-ejs-demo`](../.github/workflows/workflow.yml) utilise JFrog avec OIDC ; le contexte produit est détaillé dans [github-actions-jfrog-iap.md](github-actions-jfrog-iap.md).
