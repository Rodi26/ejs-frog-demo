#!/usr/bin/env bash
# Configure JF_URL / registry for JFrog behind IAP: split DNS (JF_HOST_CLI) or local forward proxy.
# Env:
#   IAP_GOOGLE_JWT — set by mint-iap-google-jwt.py (optional; if empty, no-op)
#   JF_HOST — public IAP hostname (upstream for proxy)
#   JF_HOST_CLI — optional second hostname for jf when split DNS (non-empty skips proxy)
#   JF_IAP_PROXY_PORT — listen port for scripts/iap-jf-forward-proxy.py (default 18081)
#   GITHUB_WORKSPACE — repo root (GitHub Actions)
#   GITHUB_ENV — append JF_URL, JF_REGISTRY_HOST, JF_IAP_PROXY_MODE
#   WITH_DOCKER — "true" = Docker registry + daemon.json (main pipeline); "false" = API only (Frogbot)
set -euo pipefail

WITH_DOCKER="${WITH_DOCKER:-false}"
PORT="${JF_IAP_PROXY_PORT:-18081}"
JF_CLI="${JF_HOST_CLI:-}"

if [ -z "${IAP_GOOGLE_JWT:-}" ]; then
  if [ "${WITH_DOCKER}" = "true" ]; then
    echo "No IAP_GOOGLE_JWT; skipping IAP URL configuration."
  else
    echo "No IAP_GOOGLE_JWT; keeping job default JF_URL."
  fi
  exit 0
fi

if [ -n "${JF_CLI}" ]; then
  echo "JF_IAP_PROXY_MODE=false" >> "${GITHUB_ENV}"
  if [ "${WITH_DOCKER}" = "true" ]; then
    echo "Using JF_HOST_CLI for jf/Docker (split DNS): ${JF_CLI}"
  else
    echo "Using JF_HOST_CLI for Frogbot: ${JF_CLI}"
  fi
  exit 0
fi

if [ "${WITH_DOCKER}" = "true" ]; then
  echo "Starting local IAP forward proxy (IAP JWT in Proxy-Authorization) for jf/Docker ..."
else
  echo "Starting local IAP forward proxy for Frogbot (API only; no Docker daemon change) ..."
fi

export JF_UPSTREAM_HOST="${JF_HOST}"
nohup python3 "${GITHUB_WORKSPACE}/scripts/iap-jf-forward-proxy.py" >> /tmp/iap-jf-proxy.log 2>&1 &
echo $! > /tmp/iap-jf-proxy.pid

for _ in $(seq 1 100); do
  if (echo >/dev/tcp/127.0.0.1/"${PORT}") 2>/dev/null; then break; fi
  sleep 0.1
done
if ! (echo >/dev/tcp/127.0.0.1/"${PORT}") 2>/dev/null; then
  echo "::error::Local IAP proxy did not listen on 127.0.0.1:${PORT}. Log:"
  cat /tmp/iap-jf-proxy.log || true
  exit 1
fi

echo "JF_URL=http://127.0.0.1:${PORT}/" >> "${GITHUB_ENV}"
echo "JF_IAP_PROXY_MODE=true" >> "${GITHUB_ENV}"

if [ "${WITH_DOCKER}" = "true" ]; then
  echo "JF_REGISTRY_HOST=127.0.0.1:${PORT}" >> "${GITHUB_ENV}"
  echo "Docker: allow insecure registry 127.0.0.1:${PORT} (HTTP) for push/pull via proxy"
  sudo mkdir -p /etc/docker
  REG="127.0.0.1:${PORT}"
  if [ -f /etc/docker/daemon.json ]; then
    sudo python3 -c "import json; from pathlib import Path; r='${REG}'; p=Path('/etc/docker/daemon.json'); d=json.loads(p.read_text()); ir=d.setdefault('insecure-registries', []); ir.append(r) if r not in ir else None; p.write_text(json.dumps(d))"
  else
    echo "{\"insecure-registries\":[\"${REG}\"]}" | sudo tee /etc/docker/daemon.json >/dev/null
  fi
  sudo systemctl restart docker || sudo service docker restart
fi
