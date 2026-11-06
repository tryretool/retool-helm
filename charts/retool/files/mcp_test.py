"""Unauthenticated MCP discovery check run by the Helm test Job."""

import json
import os
import re
import sys
from http.client import HTTPException
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


class CheckFailure(Exception):
    pass


class NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        return None


OPENER = build_opener(NoRedirects)


def fail(url, expected, observed):
    raise CheckFailure(f"{url}: expected {expected}; observed {observed}")


def http_url(value, source_url, field):
    if not isinstance(value, str):
        fail(source_url, f"{field} as an absolute HTTP(S) URL", "missing or non-string field")
    try:
        parsed = urlsplit(value)
        valid = (
            parsed.scheme in ("http", "https")
            and parsed.hostname
            and parsed.username is None
            and parsed.password is None
            and not parsed.fragment
            and not any(char.isspace() for char in value)
        )
    except ValueError:
        valid = False
    if not valid:
        fail(source_url, f"{field} as an absolute HTTP(S) URL without credentials or fragment", "invalid URL")
    try:
        parsed.port
    except ValueError:
        fail(source_url, f"{field} with a valid port", "invalid port")
    return parsed


def get(url, accept="application/json"):
    try:
        try:
            response = OPENER.open(Request(url, headers={"Accept": accept}), timeout=10)
        except HTTPError as error:
            response = error
        with response:
            status = response.status
            headers = response.headers
            body = response.read(1024 * 1024 + 1) if status == 200 else b""
    except (URLError, TimeoutError, OSError, HTTPException) as error:
        fail(url, "reachable endpoint", f"unreachable ({type(error).__name__})")
    return status, headers, body


def json_metadata(url):
    status, headers, body = get(url)
    if status != 200:
        fail(url, "HTTP 200 JSON metadata without a redirect", f"HTTP {status}")
    content_type = headers.get("Content-Type", "").split(";", 1)[0].strip().lower()
    if content_type != "application/json" and not content_type.endswith("+json"):
        fail(url, "JSON Content-Type", f"Content-Type {content_type or 'missing'}")
    if len(body) > 1024 * 1024:
        fail(url, "JSON metadata under 1 MiB", "body too large")
    try:
        data = json.loads(body)
    except (UnicodeDecodeError, json.JSONDecodeError):
        fail(url, "valid JSON object", "malformed JSON")
    if not isinstance(data, dict):
        fail(url, "JSON object", f"JSON {type(data).__name__}")
    return data


def protected_resource(url, expected_resource):
    data = json_metadata(url)
    resource = data.get("resource")
    http_url(resource, url, "resource")
    if resource != expected_resource:
        fail(url, f"resource {expected_resource}", "resource differs")
    servers = data.get("authorization_servers")
    if not isinstance(servers, list) or not servers:
        fail(url, "nonempty authorization_servers array", "missing or empty authorization_servers")
    for server in servers:
        http_url(server, url, "authorization_servers entry")
    return servers


def run(public_url):
    parsed = http_url(public_url, "configured public URL", "public URL")
    origin = public_url.rstrip("/")
    if parsed.path not in ("", "/") or "?" in public_url or "#" in public_url:
        fail("configured public URL", "Retool origin without path or query", "path or query present")

    mcp_url = f"{origin}/mcp"
    resource_url = f"{origin}/.well-known/oauth-protected-resource"
    oauth_url = f"{origin}/.well-known/oauth-authorization-server"

    status, headers, _ = get(mcp_url, "text/event-stream")
    if status != 401:
        fail(mcp_url, "HTTP 401 Bearer challenge without a redirect", f"HTTP {status}")
    challenge = ", ".join(headers.get_all("WWW-Authenticate", []))
    bearer = re.search(r"(?:^|,)\s*Bearer(?:\s|$)", challenge, re.IGNORECASE)
    if not bearer:
        fail(mcp_url, "Bearer challenge with resource_metadata", "missing Bearer challenge")
    match = re.search(r'(?:^|[\s,])resource_metadata=(?:"([^"]+)"|([^\s,]+))', challenge[bearer.end() :], re.IGNORECASE)
    if not match:
        fail(mcp_url, "Bearer challenge with resource_metadata URL", "missing resource_metadata")
    advertised_url = match.group(1) or match.group(2)
    advertised = http_url(advertised_url, mcp_url, "resource_metadata")
    if (advertised.scheme, advertised.netloc) != (parsed.scheme, parsed.netloc):
        fail(mcp_url, "resource_metadata URL on the public Retool origin", "different origin")

    advertised_servers = protected_resource(advertised_url, mcp_url)
    servers = protected_resource(resource_url, mcp_url)
    if advertised_url != resource_url and advertised_servers != servers:
        fail(advertised_url, "same authorization_servers as the well-known resource", "different authorization_servers")

    metadata = json_metadata(oauth_url)
    issuer = metadata.get("issuer")
    http_url(issuer, oauth_url, "issuer")
    if issuer.rstrip("/") not in [server.rstrip("/") for server in servers]:
        fail(oauth_url, "issuer listed in authorization_servers", "issuer differs")
    for field in ("authorization_endpoint", "token_endpoint"):
        http_url(metadata.get(field), oauth_url, field)
    response_types = metadata.get("response_types_supported")
    if not isinstance(response_types, list) or "code" not in response_types:
        fail(oauth_url, "response_types_supported containing code", "missing code response type")
    print(f"MCP discovery passed: {mcp_url}, {resource_url}, {oauth_url}")


if __name__ == "__main__":
    try:
        run(os.environ["RETOOL_PUBLIC_URL"])
    except CheckFailure as error:
        print(f"MCP discovery failed: {error}", file=sys.stderr)
        sys.exit(1)
