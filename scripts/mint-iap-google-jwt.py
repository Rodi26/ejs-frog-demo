#!/usr/bin/env python3
"""Mint a Google OIDC ID token for IAP (audience = OAuth client id) via IAM Credentials API.

Expects gcloud user credentials (e.g. after WIF auth on GitHub Actions). Writes IAP_GOOGLE_JWT
to GITHUB_ENV when set (never use a name containing \"token\" — jfrog/setup-jfrog-cli strips it).

Environment:
  GCP_WIF_SERVICE_ACCOUNT — full SA email
  IAP_OAUTH_CLIENT_ID — IAP OAuth client id (audience)
  GITHUB_ENV — path to env file (GitHub Actions)
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from urllib.parse import quote


def main() -> int:
    try:
        sa = os.environ["GCP_WIF_SERVICE_ACCOUNT"].strip()
        aud = os.environ["IAP_OAUTH_CLIENT_ID"].strip()
    except KeyError as e:
        print(f"missing required env: {e}", file=sys.stderr)
        return 1

    access = subprocess.check_output(
        ["gcloud", "auth", "print-access-token"], text=True
    ).strip()
    url = (
        "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/"
        + quote(sa, safe="")
        + ":generateIdToken"
    )
    body = json.dumps({"audience": aud, "includeEmail": True}).encode()
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Authorization", f"Bearer {access}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            out = json.load(resp)
    except urllib.error.HTTPError as e:
        raise SystemExit(f"generateIdToken failed HTTP {e.code}: {e.read().decode()}")

    jwt = out.get("token")
    if not jwt:
        raise SystemExit(f"no token in response: {out}")

    gh_env = os.environ.get("GITHUB_ENV")
    if gh_env:
        with open(gh_env, "a", encoding="utf-8") as gh:
            gh.write(f"IAP_GOOGLE_JWT={jwt}\n")
    else:
        print("GITHUB_ENV not set; not persisting token", file=sys.stderr)
        return 1

    print("::add-mask::" + jwt)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
