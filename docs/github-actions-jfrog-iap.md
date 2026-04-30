# GitHub Actions, JFrog, and IAP (Google Cloud)

## Context

The [`gh-ejs-demo`](../.github/workflows/workflow.yml) workflow uses `jfrog/setup-jfrog-cli` with **`JF_URL`** and **`JF_ACCESS_TOKEN`** (`secrets.JF_ACCESS_TOKEN`). **`vars.JF_HOST`** is the public / browser hostname (often behind **IAP**). **`JF_PUBLIC_URL`** is `https://<JF_HOST>/` for IAP-related checks.

**Two supported ways to reach Artifactory from the runner when IAP protects the public hostname:**

1. **Proxy-Authorization (preferred when you only have one public URL)** — Google IAP can validate the Google **OIDC ID token** in `Proxy-Authorization: Bearer <Google ID token>` so the client can keep `Authorization: Bearer <JFrog platform token>` for Artifactory. See [Authenticate from Proxy-Authorization Header](https://cloud.google.com/iap/docs/authentication-howto#authenticating_from_proxy-authorization_header). The stock **`jf`** CLI does not send **`Proxy-Authorization`**, so this repo starts a small local forwarder ([`scripts/iap-jf-forward-proxy.py`](../scripts/iap-jf-forward-proxy.py)) when **`vars.IAP_USE_WIF`** is **`true`** and **`vars.JF_HOST_CLI`** is **empty**. The workflow then sets **`JF_URL`** and **`JF_REGISTRY_HOST`** to `http://127.0.0.1:<port>/` (HTTP to the local proxy), configures Docker **`insecure-registries`** for that address, and **`jf docker login` / push** go through the proxy (IAP JWT added upstream; JFrog token unchanged).

2. **Second hostname (`JF_HOST_CLI`)** — Set **`vars.JF_HOST_CLI`** to another hostname for the **same** Artifactory that does **not** put IAP in front of **`Authorization: Bearer`** (internal load balancer, split DNS, etc.). Then **`JF_URL`** is `https://<JF_HOST_CLI>/` and **`JF_REGISTRY_HOST`** matches. Use this if you prefer not to run the local proxy or your platform forbids it.

If **`IAP_USE_WIF`** is false or there is no IAP, **`JF_HOST_CLI`** empty means **`JF_URL`** defaults to **`https://<JF_HOST>/`** (works when IAP is not in the path).

That pattern matches the [JFrog GitHub Actions example](https://docs.jfrog.com/integrations/docs/example-continuous-integration-between-github-actions-and-artifactory) (Platform access token). It authenticates to **JFrog** once HTTP traffic reaches Artifactory.

**Frogbot** ([`frogbot-scan-repository.yaml`](../.github/workflows/frogbot-scan-repository.yaml), [`frogbot-scan-pr.yaml`](../.github/workflows/frogbot-scan-pr.yaml)) uses the same rules: when **`vars.IAP_USE_WIF`** is **`true`**, the workflow issues an IAP JWT (WIF + IAM Credentials `generateIdToken`), then either sets **`JF_URL`** to **`https://<JF_HOST_CLI>/`** or starts the local forwarder and sets **`JF_URL`** to **`http://127.0.0.1:<port>/`**. Frogbot only needs HTTP(S) to Artifactory (no Docker), so those workflows **do not** modify **`daemon.json`**. **`pull_request_target`** jobs must **`actions/checkout`** before the proxy step so [`scripts/iap-jf-forward-proxy.py`](../scripts/iap-jf-forward-proxy.py) exists on the runner.

### Composite action (this repo)

The shared steps (**WIF auth**, **gcloud**, **mint IAP JWT**, **configure `JF_URL` / proxy / optional Docker**) live in **[`.github/actions/jfrog-iap-setup`](../.github/actions/jfrog-iap-setup/action.yml)**:

- **`scripts/mint-iap-google-jwt.py`** — IAM Credentials `generateIdToken` → **`IAP_GOOGLE_JWT`** in `GITHUB_ENV` (name avoids `*token*` so `setup-jfrog-cli` does not strip it).
- **`scripts/configure-jfrog-iap-proxy.sh`** — split DNS (`JF_HOST_CLI`) or local forwarder; **`with_docker: "true"`** (main pipeline) also sets **`JF_REGISTRY_HOST`**, **`daemon.json`**, and restarts Docker; **`"false"`** (Frogbot) is API-only.

### Variable precedence (GitHub Actions)

Order (highest wins when the same name exists in more than one place): **Environment** → **Repository** → **Organization**. Secrets follow the same idea for **Environment** vs **Repository** vs **Organization**. See [Variables](https://docs.github.com/en/actions/learn-github-actions/variables) and [Secrets](https://docs.github.com/en/actions/security-guides/using-secrets-in-github-actions).

So if the job uses **`environment: my-env`**, variables and secrets defined on **that** GitHub Environment override repository-level **`vars.*`** / **`secrets.*`** with the **same name**. Variables you do **not** set on the Environment keep falling back to repository (and then organization) values.

### GitHub Environments (optional, `gh-ejs-demo`)

[`workflow.yml`](../.github/workflows/workflow.yml) exposes an optional **`workflow_dispatch`** input **`environment`**. The job does **not** set **`jobs.*.environment`** by default: an empty **`environment:`** name is invalid, and the same workflow also runs on **`schedule`**, where **`github.event.inputs`** does not apply—so you cannot express “omit the key on schedule, set it on dispatch” in one YAML line without duplicating jobs or workflows.

**Ways to use Environment-scoped vars:**

1. **Manual runs only** — Add under **`jobs.gh-ejs-demo`**: **`environment: ${{ github.event.inputs.environment }}`** and trigger with **Run workflow**, passing the Environment name. Ensure scheduled runs either use a **second workflow** without that line or rely on **repository** variables only.
2. **All triggers** — Set **`environment: <fixed-name>`** on the job and create that [GitHub Environment](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment); put overrides there. Scheduled runs then use that Environment too.
3. **Repository variables only** — Leave **`environment`** unset and keep using **Settings → Secrets and variables → Actions → Variables** at repo level (what this repo documents as **`vars.JF_HOST`**, etc.).

### Reusing in another repository (e.g. WebGoat)

Copy the same building blocks and wire **`vars` / `secrets`** in the target repo:

| Path | Role |
|------|------|
| [`.github/actions/jfrog-iap-setup/`](../.github/actions/jfrog-iap-setup/action.yml) | Composite (WIF + mint + configure) |
| [`scripts/mint-iap-google-jwt.py`](../scripts/mint-iap-google-jwt.py) | IAP JWT |
| [`scripts/configure-jfrog-iap-proxy.sh`](../scripts/configure-jfrog-iap-proxy.sh) | `JF_URL` / proxy / optional Docker |
| [`scripts/iap-jf-forward-proxy.py`](../scripts/iap-jf-forward-proxy.py) | Local forwarder (Proxy-Authorization) |

Then add a **`checkout`** step **before** the composite, and pass **`jf_host`**, **`jf_host_cli`**, **`with_docker`**, and WIF-related **`inputs`** like in [`workflow.yml`](../.github/workflows/workflow.yml) or the Frogbot workflows. Align **repository variables** (`JF_HOST`, `JF_HOST_CLI`, `IAP_USE_WIF`, `GCP_PROJECT_ID`, `IAP_OAUTH_CLIENT_ID`, `JF_PROJECT_KEY`, …) and **secrets** (`WORKLOAD_IDENTITY_PROVIDER`, `GCP_WIF_SERVICE_ACCOUNT`, `JF_ACCESS_TOKEN`, …) with the target instance.

#### WebGoat: three JFrog environments, one IAP host

WebGoat is wired to **three** JFrog instances. Only **`https://artifactory.rodolphef.org/`** (hostname **`artifactory.rodolphef.org`**) sits behind **Google IAP** (browser “Sign in with Google” on that URL). The **other two** instances are **not** IAP-fronted from CI’s perspective: do **not** run the WIF + IAP JWT + forward-proxy path for them.

| Target | IAP | Typical `vars` |
|--------|-----|----------------|
| **`artifactory.rodolphef.org`** | Yes | `IAP_USE_WIF=true`, `JF_HOST=artifactory.rodolphef.org`, plus WIF secrets and `IAP_OAUTH_CLIENT_ID`; use composite + proxy or `JF_HOST_CLI` as in this repo. |
| **Other JFrog A / B** | No | `IAP_USE_WIF=false` (or omit the composite step behind `if: vars.IAP_USE_WIF == 'true'`). Set **`JF_URL`** / **`JF_HOST`** to that instance’s hostname only; plain **`jf`** + **`JF_ACCESS_TOKEN`** is enough. |

**Suggested layout in the WebGoat repo:** three [GitHub Environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment) (e.g. one per JFrog instance), each with its own **`JF_HOST`**, **`JF_PROJECT_KEY`**, **`IAP_USE_WIF`**, and **`JF_ACCESS_TOKEN`** (or token secret) as needed. **Only** the environment that points at **`artifactory.rodolphef.org`** sets **`IAP_USE_WIF=true`** and the WIF-related secrets. Jobs use **`environment: <name>`** or a **matrix** so each run selects **one** instance and the right flags.

**There was no IAP documentation in this repository before** the first version of this file; the playbook is [playbook-iap-github-actions.md](playbook-iap-github-actions.md).

## IAP and failures like “JFrog CLI exited with exit code 1”

If the JFrog URL (`https://<JF_HOST>/`) is exposed behind **Identity-Aware Proxy (IAP)**, HTTPS requests from **GitHub-hosted runners** (`ubuntu-latest`, etc.) arrive as Internet clients. IAP typically expects **user** authentication (Google OAuth), suited to a browser, not a non-interactive CI job.

Then the CLI can fail early (connection, TLS, redirect to a login page, or a non-API response), often surfacing as **exit code 1** on a step that runs `jf` or the JFrog setup action — **without stating IAP explicitly** in the error.

The **“Node.js 20 actions are deprecated”** warning on other actions is **separate**: it is about the JavaScript **runtime of those GitHub Actions**, not the root cause of an IAP or network block.

## Infrastructure-side options (outside this repo)

Usual approaches are architectural, for example:

- **Self-hosted runner** in a network where access to JFrog is not subject to the same IAP posture as public Internet traffic.
- **Hostname or API path** reserved for CI and not protected by IAP (subject to org security policy).
- **IAP rules** (if your org uses them for service identities or specific paths) — validate with platform / GCP teams.

This repo cannot “fix” IAP through YAML alone; it documents the constraint so diagnosis and ownership stay clear.

## “Repository does not exist” while it exists in the UI

`vars.JF_HOST` must be the **same host** you use in the browser to open Artifactory (hostname only, e.g. `artifactory.example.org`). The workflow builds `JF_URL` as `https://<JF_HOST>/`.

If the CLI is pointed at **another** instance (typo, old variable, or duplicate deployment), the API will not list `dev-npm` even though it exists elsewhere. The **Verify JFrog connection** step lists **npm-related repository keys** visible to **`JF_ACCESS_TOKEN`**: when **`IAP_GOOGLE_JWT`** is set, it **`curl`**s **`JF_PUBLIC_URL`** with **`Proxy-Authorization`** (IAP) and **`Authorization`** (JFrog), then runs **`jf rt curl`** against **`JF_URL`** (local proxy or **`JF_HOST_CLI`**). If `dev-npm` is missing from that list, fix **URL**, **token scope**, or **Project / permission** assignment before changing `--repo-resolve` names.

## `401 Unauthorized` — `Invalid IAP credentials: JWT signature is invalid`

This response is produced by **Google Cloud IAP** in front of your hostname, **not** by JFrog. Request flow:

1. **HTTPS hits the load balancer** → IAP validates a **Google IAP identity JWT** (issuer, signature, audience that IAP trusts).
2. Only after IAP allows the request does traffic reach **Artifactory**, where **`JF_ACCESS_TOKEN`** is relevant.

`JF_ACCESS_TOKEN` is a **JFrog Platform** token. IAP does **not** accept it as an IAP JWT, so `jf rt ping` can return **401** with **Invalid IAP credentials: JWT signature is invalid** even though the same JFrog token would work **if** the HTTP request reached Artifactory (for example after interactive login in a browser, or from a network path that bypasses IAP).

**Why `X-JFrog-Art-Api` is not enough:** JFrog **Platform access tokens** are normally sent as **`Authorization: Bearer <token>`**. Putting the same token in **`X-JFrog-Art-Api`** (meant for legacy API keys) can produce Artifactory errors such as **`Props Authentication Token not found`** — IAP was satisfied, but Artifactory did not accept that auth style for the REST API.

**This repo’s approaches:** (a) leave **`vars.JF_HOST_CLI`** empty and use the **local IAP forward proxy** so **`jf`** talks to `http://127.0.0.1:<port>/` while the verify step proves **`JF_PUBLIC_URL`** with both headers; or (b) set **`vars.JF_HOST_CLI`** (GitHub: **Settings → Secrets and variables → Actions → Variables**) to a hostname for the **same** instance where **`jf`** can use **`Authorization: Bearer`** alone (no IAP on that host). **`JF_HOST_CLI`** **must differ** from **`vars.JF_HOST`** when you use that path. The workflow runs **`jf`** against **`JF_URL`** (`http://127.0.0.1:.../` or `https://<JF_HOST_CLI>/` accordingly).

### If you cannot expose “a backend without IAP” (or it would not be public)

“IAP off” on a URL does **not** have to mean “open to the whole Internet.” Common patterns that stay compatible with **`jf`** (Bearer only):

1. **Same Artifactory, different hostname or load balancer** where **IAP is not enabled**, but **access is restricted** with a **VPC firewall**, **Cloud Armor**, or **source IP allowlists**. GitHub documents [GitHub-hosted runners](https://docs.github.com/en/actions/using-github-hosted-runners/using-github-hosted-runners/about-github-hosted-runners); the [`api.github.com/meta`](https://api.github.com/meta) JSON includes an **`actions`** array of CIDRs many teams allow toward a CI-facing VIP. Traffic is still routed over the public Internet from GitHub’s perspective, but the endpoint is not anonymously reachable.

2. **Self-hosted GitHub Actions runners** (VM in your VPC, GKE, etc.) where the runner reaches Artifactory over **private IP**, **PSC**, **VPN**, or **Hybrid Connectivity**. Then **`jf`** does not need to traverse IAP at all for API/registry calls; you may still use **`vars.JF_HOST`** + WIF only to **prove** IAP for the public URL in a dedicated step.

3. **Path- or service-splitting at the load balancer** (platform team): e.g. browser UI behind IAP while a **separate backend or URL map** exposes Artifactory API/registry to trusted sources only. That is still “another route” than pure IAP-on-`Authorization`, even if you do not call it a second “public” site.

Google documents putting the **IAP OIDC token** in **`Proxy-Authorization`** so **`Authorization`** remains available for the **origin** (Artifactory). That is exactly the dual-header pattern **`curl`** can send; **`jf`** still needs either **`JF_HOST_CLI`** or the **local forward proxy** in this workflow because the CLI does not add **`Proxy-Authorization`** itself.

**Implication:** a **single public hostname** can be enough for **API** access from GitHub-hosted runners if IAP accepts **`Proxy-Authorization`** on your load balancer and you use the **proxy** path (or **`JF_HOST_CLI`**). Remaining constraints are operational (TLS, Docker **`insecure-registries`** for the local HTTP endpoint, and **SLSA container provenance**: the reusable provenance job runs on **another** runner and cannot pull an image that exists only as `127.0.0.1:...` on the first runner, so the workflow **skips** that job when the local proxy mode is active).

Other org-level options still apply: **self-hosted runners**, **VPC / allowlisted** CI endpoints, **Programmatic IAP** (WIF) — see [Google Cloud IAP authentication overview](https://cloud.google.com/iap/docs/authentication-howto) and [iap-programmatic-auth-github-actions.md](iap-programmatic-auth-github-actions.md).

For **`jf`** and Docker, traffic must reach Artifactory in a way compatible with how those clients send **`Authorization`** — the forward proxy adds **`Proxy-Authorization`** only on the hop from the runner to **`https://<JF_HOST>`**.

## Terraform (variables dépôt)

Pour créer les **`vars.*`** GitHub Actions à partir de fichiers versionnés, ce dépôt fournit **[`terraform/github-actions-variables/`](../terraform/github-actions-variables/)** (provider `integrations/github`). Le module GCP WIF **[`terraform/gcp-wif-github/`](../terraform/gcp-wif-github/)** continue de provisionner uniquement l’identité et les outputs pour les **secrets** ; les secrets eux-mêmes ne sont pas dans ce Terraform par défaut.

## References

- [Google Cloud — Authenticate to IAP](https://cloud.google.com/iap/docs/authentication-howto)
- [GitHub Blog — Node 20 deprecation on Actions runners](https://github.blog/changelog/2025-09-19-deprecation-of-node-20-on-github-actions-runners/)
- [JFrog `setup-jfrog-cli`](https://github.com/jfrog/setup-jfrog-cli) (v5 uses Node 24 for the action runtime)
