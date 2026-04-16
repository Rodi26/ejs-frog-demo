# GitHub Actions, JFrog, and IAP (Google Cloud)

## Context

The [`gh-ejs-demo`](../.github/workflows/workflow.yml) workflow uses `jfrog/setup-jfrog-cli` with **`JF_URL`** and **`JF_ACCESS_TOKEN`** (`secrets.JF_ACCESS_TOKEN`). **`vars.JF_HOST`** is the public / browser hostname (often behind **IAP**). **`JF_PUBLIC_URL`** is `https://<JF_HOST>/` for IAP-related checks.

**Two supported ways to reach Artifactory from the runner when IAP protects the public hostname:**

1. **Proxy-Authorization (preferred when you only have one public URL)** — Google IAP can validate the Google **OIDC ID token** in `Proxy-Authorization: Bearer <Google ID token>` so the client can keep `Authorization: Bearer <JFrog platform token>` for Artifactory. See [Authenticate from Proxy-Authorization Header](https://cloud.google.com/iap/docs/authentication-howto#authenticating_from_proxy-authorization_header). The stock **`jf`** CLI does not send **`Proxy-Authorization`**, so this repo starts a small local forwarder ([`scripts/iap-jf-forward-proxy.py`](../scripts/iap-jf-forward-proxy.py)) when **`vars.IAP_USE_WIF`** is **`true`** and **`vars.JF_HOST_CLI`** is **empty**. The workflow then sets **`JF_URL`** and **`JF_REGISTRY_HOST`** to `http://127.0.0.1:<port>/` (HTTP to the local proxy), configures Docker **`insecure-registries`** for that address, and **`jf docker login` / push** go through the proxy (IAP JWT added upstream; JFrog token unchanged).

2. **Second hostname (`JF_HOST_CLI`)** — Set **`vars.JF_HOST_CLI`** to another hostname for the **same** Artifactory that does **not** put IAP in front of **`Authorization: Bearer`** (internal load balancer, split DNS, etc.). Then **`JF_URL`** is `https://<JF_HOST_CLI>/` and **`JF_REGISTRY_HOST`** matches. Use this if you prefer not to run the local proxy or your platform forbids it.

If **`IAP_USE_WIF`** is false or there is no IAP, **`JF_HOST_CLI`** empty means **`JF_URL`** defaults to **`https://<JF_HOST>/`** (works when IAP is not in the path).

That pattern matches the [JFrog GitHub Actions example](https://docs.jfrog.com/integrations/docs/example-continuous-integration-between-github-actions-and-artifactory) (Platform access token). It authenticates to **JFrog** once HTTP traffic reaches Artifactory.

**Frogbot** ([`frogbot-scan-repository.yaml`](../.github/workflows/frogbot-scan-repository.yaml), [`frogbot-scan-pr.yaml`](../.github/workflows/frogbot-scan-pr.yaml)) uses the same rules: when **`vars.IAP_USE_WIF`** is **`true`**, the workflow issues an IAP JWT (WIF + IAM Credentials `generateIdToken`), then either sets **`JF_URL`** to **`https://<JF_HOST_CLI>/`** or starts the local forwarder and sets **`JF_URL`** to **`http://127.0.0.1:<port>/`**. Frogbot only needs HTTP(S) to Artifactory (no Docker), so those workflows **do not** modify **`daemon.json`**. **`pull_request_target`** jobs must **`actions/checkout`** before the proxy step so [`scripts/iap-jf-forward-proxy.py`](../scripts/iap-jf-forward-proxy.py) exists on the runner.

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

## References

- [Google Cloud — Authenticate to IAP](https://cloud.google.com/iap/docs/authentication-howto)
- [GitHub Blog — Node 20 deprecation on Actions runners](https://github.blog/changelog/2025-09-19-deprecation-of-node-20-on-github-actions-runners/)
- [JFrog `setup-jfrog-cli`](https://github.com/jfrog/setup-jfrog-cli) (v5 uses Node 24 for the action runtime)
