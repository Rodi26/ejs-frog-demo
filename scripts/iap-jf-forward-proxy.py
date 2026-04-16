#!/usr/bin/env python3
"""
Local HTTP forward proxy for GitHub Actions: adds Google IAP OIDC to Proxy-Authorization
so JFrog can keep Authorization: Bearer <platform token>.

See: https://cloud.google.com/iap/docs/authentication-howto#authenticating_from_proxy-authorization_header

Environment:
  JF_UPSTREAM_HOST  — Artifactory hostname only (e.g. artifactory.example.org)
  IAP_GOOGLE_JWT    — OIDC ID token (audience = IAP OAuth client ID)
  JF_IAP_PROXY_BIND — host:port to listen (default 127.0.0.1:18081)
"""
from __future__ import annotations

import http.client
import os
import ssl
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Dict


UPSTREAM = os.environ.get("JF_UPSTREAM_HOST", "").strip()
IAP_JWT = os.environ.get("IAP_GOOGLE_JWT", "").strip()
BIND = os.environ.get("JF_IAP_PROXY_BIND", "127.0.0.1:18081").strip()

if not UPSTREAM or not IAP_JWT:
    print("iap-jf-forward-proxy: need JF_UPSTREAM_HOST and IAP_GOOGLE_JWT", file=sys.stderr)
    sys.exit(1)

# Origin clients use to talk to this listener (Docker push/pull via insecure registry).
_LOCAL_HTTP_ORIGIN = f"http://{BIND}"

# Response headers whose values may contain absolute upstream URLs; clients would follow them
# over HTTPS and bypass this proxy → IAP sees no Proxy-Authorization ("empty token").
_HEADERS_REWRITE_UPSTREAM_URLS = frozenset(
    {"www-authenticate", "location", "content-location"}
)


def _rewrite_upstream_absolute_urls(value: str) -> str:
    """
    Replace https://<UPSTREAM>/... with http://<BIND>/... so clients (Docker/registry, npm)
    keep talking to this forwarder, which adds Proxy-Authorization for IAP.

    Used for:
    - WWW-Authenticate (realm=... OAuth token URL)
    - Location / Content-Location (redirects to blob upload URLs, etc.)
    """
    # Replace longer match first so :443 is not left behind as a bogus suffix.
    v = value.replace(f"https://{UPSTREAM}:443", _LOCAL_HTTP_ORIGIN)
    v = v.replace(f"https://{UPSTREAM}", _LOCAL_HTTP_ORIGIN)
    v = v.replace(f"http://{UPSTREAM}", _LOCAL_HTTP_ORIGIN)
    return v


def _hop_by_hop() -> set[str]:
    return {
        "connection",
        "content-length",
        "keep-alive",
        "proxy-authenticate",
        "proxy-authorization",
        "te",
        "trailers",
        "transfer-encoding",
        "upgrade",
    }


class ForwardHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:
        print(f"[iap-jf-forward-proxy] {self.address_string()} - {fmt % args}", file=sys.stderr)

    def _forward(self) -> None:
        clen = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(clen) if clen > 0 else None

        out_headers: Dict[str, str] = {}
        for k, v in self.headers.items():
            lk = k.lower()
            if lk in _hop_by_hop() or lk == "host":
                continue
            out_headers[k] = v
        out_headers["Host"] = UPSTREAM
        out_headers["Proxy-Authorization"] = f"Bearer {IAP_JWT}"

        ctx = ssl.create_default_context()
        conn = http.client.HTTPSConnection(UPSTREAM, context=ctx, timeout=600)
        try:
            conn.request(self.command, self.path, body=body, headers=out_headers)
            resp = conn.getresponse()
            # Read full body so we can send a single Content-Length. Streaming without
            # Content-Length after stripping Transfer-Encoding confuses some clients and
            # can truncate or corrupt binary bodies (npm tar TAR_ENTRY_INVALID).
            payload = resp.read()
            self.send_response(resp.status)
            for hk, hv in resp.getheaders():
                if hk.lower() in _hop_by_hop():
                    continue
                if hk.lower() in _HEADERS_REWRITE_UPSTREAM_URLS:
                    hv = _rewrite_upstream_absolute_urls(hv)
                self.send_header(hk, hv)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            if payload:
                self.wfile.write(payload)
        finally:
            conn.close()

    def do_GET(self) -> None:
        self._forward()

    def do_HEAD(self) -> None:
        self._forward()

    def do_POST(self) -> None:
        self._forward()

    def do_PUT(self) -> None:
        self._forward()

    def do_PATCH(self) -> None:
        self._forward()

    def do_DELETE(self) -> None:
        self._forward()

    def do_OPTIONS(self) -> None:
        self._forward()


def main() -> None:
    host, _, port_s = BIND.partition(":")
    port = int(port_s or "18081")
    server = ThreadingHTTPServer((host, port), ForwardHandler)
    print(
        f"iap-jf-forward-proxy: listening on http://{host}:{port} → https://{UPSTREAM}/",
        flush=True,
    )
    server.serve_forever()


if __name__ == "__main__":
    main()
