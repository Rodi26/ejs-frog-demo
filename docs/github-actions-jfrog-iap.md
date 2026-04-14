# GitHub Actions, JFrog, and IAP (Google Cloud)

## Context

The [`gh-ejs-demo`](../.github/workflows/workflow.yml) workflow uses `jfrog/setup-jfrog-cli` with **`JF_URL`** (`https://<JF_HOST>/` from **`vars.JF_HOST`**) and **`JF_ACCESS_TOKEN`** (`secrets.JF_ACCESS_TOKEN`). Docker uses the same CLI config via `jf docker login <JF_HOST>`.

That pattern matches the [JFrog GitHub Actions example](https://docs.jfrog.com/integrations/docs/example-continuous-integration-between-github-actions-and-artifactory) (Platform access token). It avoids relying on OIDC from the runner when IAP or network policy blocks that path.

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

If the CLI is pointed at **another** instance (typo, old variable, or duplicate deployment), the API will not list `dev-npm` even though it exists elsewhere. The **Verify JFrog connection** step in [`workflow.yml`](../.github/workflows/workflow.yml) runs `jf rt ping` and lists **npm-related repository keys** visible to **`JF_ACCESS_TOKEN`**. If `dev-npm` is missing from that list, fix **URL**, **token scope**, or **Project / permission** assignment before changing `--repo-resolve` names.

## References

- [GitHub Blog — Node 20 deprecation on Actions runners](https://github.blog/changelog/2025-09-19-deprecation-of-node-20-on-github-actions-runners/)
- [JFrog `setup-jfrog-cli`](https://github.com/jfrog/setup-jfrog-cli) (v5 uses Node 24 for the action runtime)
