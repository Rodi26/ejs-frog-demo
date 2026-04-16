# GitHub Actions, JFrog, and IAP (Google Cloud)

## Context

The [`gh-ejs-demo`](../.github/workflows/workflow.yml) workflow uses `jfrog/setup-jfrog-cli` with **`JF_URL`** and **`JF_ACCESS_TOKEN`** (`secrets.JF_ACCESS_TOKEN`). **`vars.JF_HOST`** is the public / browser hostname (often behind **IAP**). When IAP is on, set **`vars.JF_HOST_CLI`** to another hostname for the **same** Artifactory that does **not** put IAP in front of `Authorization: Bearer` (internal load balancer, split DNS, etc.): **`JF_URL`** becomes `https://<JF_HOST_CLI>/`, while **`JF_PUBLIC_URL`** stays `https://<JF_HOST>/` for IAP checks. Docker uses **`JF_REGISTRY_HOST`** (same logic as **`JF_URL`**). If **`JF_HOST_CLI`** is unset, **`JF_HOST`** is used for both (works when there is no IAP).

That pattern matches the [JFrog GitHub Actions example](https://docs.jfrog.com/integrations/docs/example-continuous-integration-between-github-actions-and-artifactory) (Platform access token). It authenticates to **JFrog** once HTTP traffic reaches Artifactory. It does **not** satisfy **Google IAP** in front of the same URL — see the section **`401 Unauthorized` / Invalid IAP credentials** below.

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

If the CLI is pointed at **another** instance (typo, old variable, or duplicate deployment), the API will not list `dev-npm` even though it exists elsewhere. The **Verify JFrog connection** step lists **npm-related repository keys** visible to **`JF_ACCESS_TOKEN`**: **`curl`** IAP ping on **`JF_PUBLIC_URL`** when **`IAP_GOOGLE_JWT`** is set, then **`jf rt curl`** on **`JF_URL`** (requires **`JF_HOST_CLI`** when the public host is behind IAP — see below). If `dev-npm` is missing from that list, fix **URL**, **token scope**, or **Project / permission** assignment before changing `--repo-resolve` names.

## `401 Unauthorized` — `Invalid IAP credentials: JWT signature is invalid`

This response is produced by **Google Cloud IAP** in front of your hostname, **not** by JFrog. Request flow:

1. **HTTPS hits the load balancer** → IAP validates a **Google IAP identity JWT** (issuer, signature, audience that IAP trusts).
2. Only after IAP allows the request does traffic reach **Artifactory**, where **`JF_ACCESS_TOKEN`** is relevant.

`JF_ACCESS_TOKEN` is a **JFrog Platform** token. IAP does **not** accept it as an IAP JWT, so `jf rt ping` can return **401** with **Invalid IAP credentials: JWT signature is invalid** even though the same JFrog token would work **if** the HTTP request reached Artifactory (for example after interactive login in a browser, or from a network path that bypasses IAP).

**Why `X-JFrog-Art-Api` is not enough:** JFrog **Platform access tokens** are normally sent as **`Authorization: Bearer <token>`**. Putting the same token in **`X-JFrog-Art-Api`** (meant for legacy API keys) can produce Artifactory errors such as **`Props Authentication Token not found`** — IAP was satisfied, but Artifactory did not accept that auth style for the REST API.

**This repo’s approach:** set **`vars.JF_HOST_CLI`** (GitHub: **Settings → Secrets and variables → Actions → Variables**) to a hostname for the **same** instance where **`jf`** can use **`Authorization: Bearer`** alone (no IAP on that host). It **must differ** from **`vars.JF_HOST`**. The workflow pings **`JF_PUBLIC_URL`** (`vars.JF_HOST`) with **`IAP_GOOGLE_JWT`**, then runs **`jf`** against **`JF_URL`** (`https://<JF_HOST_CLI>/` when set).

### If you cannot expose “a backend without IAP” (or it would not be public)

“IAP off” on a URL does **not** have to mean “open to the whole Internet.” Common patterns that stay compatible with **`jf`** (Bearer only):

1. **Same Artifactory, different hostname or load balancer** where **IAP is not enabled**, but **access is restricted** with a **VPC firewall**, **Cloud Armor**, or **source IP allowlists**. GitHub documents [GitHub-hosted runners](https://docs.github.com/en/actions/using-github-hosted-runners/using-github-hosted-runners/about-github-hosted-runners); the [`api.github.com/meta`](https://api.github.com/meta) JSON includes an **`actions`** array of CIDRs many teams allow toward a CI-facing VIP. Traffic is still routed over the public Internet from GitHub’s perspective, but the endpoint is not anonymously reachable.

2. **Self-hosted GitHub Actions runners** (VM in your VPC, GKE, etc.) where the runner reaches Artifactory over **private IP**, **PSC**, **VPN**, or **Hybrid Connectivity**. Then **`jf`** does not need to traverse IAP at all for API/registry calls; you may still use **`vars.JF_HOST`** + WIF only to **prove** IAP for the public URL in a dedicated step.

3. **Path- or service-splitting at the load balancer** (platform team): e.g. browser UI behind IAP while a **separate backend or URL map** exposes Artifactory API/registry to trusted sources only. That is still “another route” than pure IAP-on-`Authorization`, even if you do not call it a second “public” site.

What **does not** work with GitHub-hosted runners and the stock **`jf`** client: a **single** hostname where **every** HTTPS request must present a **Google IAP JWT** in `Authorization` **and** Artifactory must see **`Authorization: Bearer` (JFrog)** — one header cannot carry both.

**Implication:** if only a **single** IAP-protected hostname exists and you cannot add a CI-facing hostname, **`jf`** from GitHub-hosted runners will not match a supported dual-auth pattern; options remain:

- a hostname or path for **API / CI** that is **not** behind IAP (subject to security review), or  
- **Self-hosted GitHub runners** (or VPN) so CI traffic does not hit public IAP like a random Internet client, or  
- **Programmatic IAP** (service account or workload identity issuing tokens for your IAP OAuth client audience) — see [Google Cloud IAP authentication overview](https://cloud.google.com/iap/docs/authentication-howto).

**Step-by-step (GitHub Actions + audience OAuth + SA / WIF) :** [iap-programmatic-auth-github-actions.md](iap-programmatic-auth-github-actions.md).

For **`jf`** itself (not raw `curl`), traffic must still reach Artifactory in a way compatible with how the CLI sends **`Authorization`** — otherwise steps after **Verify** (npm, Docker, build info, etc.) can fail even when **Verify** passes.

## References

- [Google Cloud — Authenticate to IAP](https://cloud.google.com/iap/docs/authentication-howto)
- [GitHub Blog — Node 20 deprecation on Actions runners](https://github.blog/changelog/2025-09-19-deprecation-of-node-20-on-github-actions-runners/)
- [JFrog `setup-jfrog-cli`](https://github.com/jfrog/setup-jfrog-cli) (v5 uses Node 24 for the action runtime)
