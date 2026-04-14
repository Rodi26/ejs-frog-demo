# GitHub Actions, JFrog, and IAP (Google Cloud)

## Context

The [`gh-ejs-demo`](../.github/workflows/workflow.yml) workflow uses `jfrog/setup-jfrog-cli` with OIDC (`oidc-provider-name`, `oidc-audience`) and `JF_URL` pointing at the JFrog instance (`vars.JF_HOST`).

**There was no IAP documentation in this repository before**; this file is the single place for it.

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

## References

- [GitHub Blog — Node 20 deprecation on Actions runners](https://github.blog/changelog/2025-09-19-deprecation-of-node-20-on-github-actions-runners/)
- [JFrog `setup-jfrog-cli`](https://github.com/jfrog/setup-jfrog-cli) (v5 uses Node 24 for the action runtime)
