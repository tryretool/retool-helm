"""Render and HTTP behavior checks for the MCP helm test hook."""

import importlib.util
import json
import os
import subprocess
import sys
import textwrap
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch
from urllib.error import URLError


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "charts/retool/files/mcp_test.py"
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("mcp_test", SCRIPT)
mcp_test = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mcp_test)


class Handler(BaseHTTPRequestHandler):
    responses = {}

    def do_GET(self):
        status, content_type, body, headers = self.responses.get(self.path, (404, "text/plain", b"missing", {}))
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        for name, value in headers.items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


class BehaviorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.origin = f"http://127.0.0.1:{cls.server.server_port}"
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def setUp(self):
        resource = json.dumps({"resource": f"{self.origin}/mcp", "authorization_servers": [self.origin]}).encode()
        authorization = json.dumps({
            "issuer": self.origin,
            "authorization_endpoint": f"{self.origin}/auth/oauth2/authorize",
            "token_endpoint": f"{self.origin}/api/oauth2/token",
            "response_types_supported": ["code"],
        }).encode()
        Handler.responses = {
            "/mcp": (401, "text/plain", b"", {"WWW-Authenticate": f'Bearer realm="mcp", resource_metadata="{self.origin}/.well-known/oauth-protected-resource"'}),
            "/.well-known/oauth-protected-resource": (200, "application/json", resource, {}),
            "/.well-known/oauth-authorization-server": (200, "application/json", authorization, {}),
        }

    def replace(self, path, status=200, content_type="application/json", body=b"{}", headers=None):
        Handler.responses[path] = (status, content_type, body, headers or {})

    def assert_failure(self, url, expected, observed):
        with self.assertRaises(mcp_test.CheckFailure) as error:
            mcp_test.run(self.origin)
        self.assertIn(url, str(error.exception))
        self.assertIn(f"expected {expected}", str(error.exception))
        self.assertIn(f"observed {observed}", str(error.exception))

    def test_valid_discovery(self):
        mcp_test.run(self.origin)

    def test_mcp_redirect_fails_without_following_login(self):
        self.replace("/mcp", status=302, headers={"Location": "/login"})
        self.assert_failure(f"{self.origin}/mcp", "HTTP 401", "HTTP 302")

    def test_missing_resource_metadata_fails(self):
        self.replace("/mcp", status=401, headers={"WWW-Authenticate": 'Bearer realm="mcp"'})
        self.assert_failure(f"{self.origin}/mcp", "Bearer challenge with resource_metadata URL", "missing resource_metadata")

    def test_unusable_advertised_url_fails(self):
        self.replace("/mcp", status=401, headers={"WWW-Authenticate": 'Bearer resource_metadata="/relative"'})
        self.assert_failure(f"{self.origin}/mcp", "resource_metadata as an absolute HTTP(S) URL", "invalid URL")

    def test_missing_advertised_metadata_fails(self):
        self.replace("/mcp", status=401, headers={"WWW-Authenticate": f'Bearer resource_metadata="{self.origin}/missing-metadata"'})
        self.assert_failure(f"{self.origin}/missing-metadata", "HTTP 200 JSON metadata", "HTTP 404")

    def test_html_login_page_fails(self):
        path = "/.well-known/oauth-protected-resource"
        self.replace(path, content_type="text/html", body=b"<html>login</html>")
        self.assert_failure(f"{self.origin}{path}", "JSON Content-Type", "Content-Type text/html")

    def test_redirected_oauth_metadata_fails(self):
        path = "/.well-known/oauth-authorization-server"
        self.replace(path, status=302, headers={"Location": "/login"})
        self.assert_failure(f"{self.origin}{path}", "HTTP 200 JSON metadata", "HTTP 302")

    def test_malformed_json_fails(self):
        path = "/.well-known/oauth-protected-resource"
        self.replace(path, body=b"{")
        self.assert_failure(f"{self.origin}{path}", "valid JSON object", "malformed JSON")

    def test_missing_oauth_field_fails(self):
        path = "/.well-known/oauth-authorization-server"
        self.replace(path, body=json.dumps({"issuer": self.origin}).encode())
        self.assert_failure(f"{self.origin}{path}", "authorization_endpoint as an absolute HTTP(S) URL", "missing or non-string field")

    def test_wrong_resource_fails(self):
        path = "/.well-known/oauth-protected-resource"
        self.replace(path, body=json.dumps({"resource": f"{self.origin}/other", "authorization_servers": [self.origin]}).encode())
        self.assert_failure(f"{self.origin}{path}", f"resource {self.origin}/mcp", "resource differs")

    def test_missing_authorization_server_fails(self):
        path = "/.well-known/oauth-protected-resource"
        self.replace(path, body=json.dumps({"resource": f"{self.origin}/mcp"}).encode())
        self.assert_failure(f"{self.origin}{path}", "nonempty authorization_servers array", "missing or empty authorization_servers")

    def test_unreachable_endpoint_fails(self):
        with patch.object(mcp_test.OPENER, "open", side_effect=URLError("connection refused")):
            self.assert_failure(f"{self.origin}/mcp", "reachable endpoint", "unreachable")


class RenderTests(unittest.TestCase):
    def render(self, *settings, json_settings=()):
        command = [
            "helm", "template", "mcp-smoke", "charts/retool",
            "--values", "charts/retool/ci/test-install-values.yaml",
            "--values", "charts/retool/ci/test-mcp-enabled-option.yaml",
        ]
        for setting in settings:
            command.extend(("--set", setting))
        for setting in json_settings:
            command.extend(("--set-json", setting))
        return subprocess.check_output(command, cwd=ROOT, text=True)

    @staticmethod
    def hook(output):
        return output.split("# Source: retool/templates/test_mcp.yaml", 1)[1].split("\n---\n", 1)[0]

    def test_hook_absent_without_public_url_or_mcp(self):
        marker = "# Source: retool/templates/test_mcp.yaml"
        self.assertNotIn(marker, self.render())
        self.assertNotIn(marker, self.render("mcp.enabled=false", "mcp.test.publicUrl=https://retool.example.com"))

    def test_hook_renders_configured_image_and_url(self):
        output = self.render("mcp.test.publicUrl=https://retool.example.com", "mcp.test.image=registry.example.com/python:3.12")
        hook = self.hook(output)
        self.assertIn("kind: Job", hook)
        self.assertIn('"helm.sh/hook": test', hook)
        self.assertIn('image: "registry.example.com/python:3.12"', hook)
        self.assertIn('value: "https://retool.example.com"', hook)
        self.assertIn("automountServiceAccountToken: false", hook)
        self.assertIn("resource_metadata", hook)
        self.assertNotIn("EXPIRED-LICENSE-KEY-TRIAL", hook)

    def test_hook_inherits_pod_placement(self):
        affinity = {"nodeAffinity": {"requiredDuringSchedulingIgnoredDuringExecution": {
            "nodeSelectorTerms": [{"matchExpressions": [{"key": "kubernetes.io/arch", "operator": "In", "values": ["amd64"]}]}]
        }}}
        output = self.render(
            "mcp.test.publicUrl=https://retool.example.com",
            "tolerations[0].key=dedicated",
            "tolerations[0].operator=Exists",
            json_settings=(f"affinity={json.dumps(affinity)}",),
        )
        hook = self.hook(output)
        self.assertIn("nodeSelector:\n        kubernetes.io/arch: amd64", hook)
        self.assertIn("tolerations:\n        - key: dedicated\n          operator: Exists", hook)
        self.assertIn("affinity:\n        nodeAffinity:", hook)

    def test_rendered_python_command_runs_against_http_fixture(self):
        output = self.render("mcp.test.publicUrl=https://retool.example.com")
        hook = self.hook(output)
        self.assertIn("command: [python3, -c]", hook)
        script = textwrap.dedent(hook.split("          args:\n            - |\n", 1)[1].split("\n          env:\n", 1)[0])

        with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
            origin = f"http://127.0.0.1:{server.server_port}"
            resource = json.dumps({"resource": f"{origin}/mcp", "authorization_servers": [origin]}).encode()
            authorization = json.dumps({
                "issuer": origin,
                "authorization_endpoint": f"{origin}/auth/oauth2/authorize",
                "token_endpoint": f"{origin}/api/oauth2/token",
                "response_types_supported": ["code"],
            }).encode()
            Handler.responses = {
                "/mcp": (401, "text/plain", b"", {"WWW-Authenticate": f'Bearer resource_metadata="{origin}/.well-known/oauth-protected-resource"'}),
                "/.well-known/oauth-protected-resource": (200, "application/json", resource, {}),
                "/.well-known/oauth-authorization-server": (200, "application/json", authorization, {}),
            }
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                env = {**os.environ, "RETOOL_PUBLIC_URL": origin}
                result = subprocess.run([sys.executable, "-c", script], env=env, text=True, capture_output=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("MCP discovery passed", result.stdout)

                Handler.responses["/mcp"] = (302, "text/html", b"", {"Location": "/login"})
                result = subprocess.run([sys.executable, "-c", script], env=env, text=True, capture_output=True, timeout=10)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f"{origin}/mcp", result.stderr)
                self.assertIn("expected HTTP 401", result.stderr)
                self.assertIn("observed HTTP 302", result.stderr)
            finally:
                server.shutdown()
                thread.join()


if __name__ == "__main__":
    unittest.main()
