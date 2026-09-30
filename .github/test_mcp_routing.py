"""Check MCP public routes and migration errors in rendered Helm manifests."""

import re
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASE = [
    "helm", "template", "routing", "charts/retool",
    "--values", "charts/retool/ci/test-install-values.yaml",
    "--values", "charts/retool/ci/test-mcp-enabled-option.yaml",
    "--set", "ingress.hosts[0].host=retool.example.com",
    "--set", "ingress.hosts[0].paths[0].path=/",
]
MAIN = "routing-retool"
MCP = "routing-retool-mcp"
BACKEND_API = "routing-retool-backend-internal"


def render(*settings):
    command = BASE.copy()
    for setting in settings:
        command.extend(("--set", setting))
    return subprocess.run(command, cwd=ROOT, text=True, capture_output=True)


def manifest(output, filename):
    marker = f"# Source: retool/templates/{filename}\n"
    return output.split(marker, 1)[1].split("\n---\n", 1)[0]


def ingress_routes(output):
    document = manifest(output, "ingress.yaml")
    return re.findall(
        r"(?m)^\s+- path: (\S+)\n\s+pathType: (\S+)\n\s+backend:\n\s+service:\n\s+name: (\S+)\n\s+port:\n\s+number: (\d+)",
        document,
    )


def http_routes(output):
    document = manifest(output, "httproute.yaml")
    return re.findall(
        r"(?m)^\s+- matches:\n\s+- path:\n\s+type: (\S+)\n\s+value: (\S+)\n\s+backendRefs:\n\s+- name: (\S+)\n\s+port: (\d+)",
        document,
    )


INGRESS_DIRECT = [
    ("/.well-known/oauth-authorization-server", "Exact", BACKEND_API, "3001"),
    ("/.well-known/oauth-protected-resource", "Exact", MCP, "4010"),
    ("/mcp", "Prefix", MCP, "4010"),
    ("/", "ImplementationSpecific", MAIN, "3000"),
]
HTTP_DIRECT = [
    ("Exact", "/.well-known/oauth-authorization-server", BACKEND_API, "3001"),
    ("Exact", "/.well-known/oauth-protected-resource", MCP, "4010"),
    ("PathPrefix", "/mcp", MCP, "4010"),
    ("PathPrefix", "/", MAIN, "3000"),
]


class RoutingTests(unittest.TestCase):
    def assert_rendered(self, *settings):
        result = render(*settings)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def assert_rejected(self, message, *settings):
        result = render(*settings)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(message, result.stderr)

    def test_default_backend_relay_uses_main_service_for_both_route_types(self):
        output = self.assert_rendered()
        self.assertEqual(ingress_routes(output), [INGRESS_DIRECT[-1]])
        self.assertEqual(http_routes(output), [HTTP_DIRECT[-1]])
        self.assertIn('value: "http://routing-retool-mcp:4010"', manifest(output, "deployment_backend.yaml"))
        self.assertIn("- name: MCP_SERVICE_INGRESS_DOMAIN", manifest(output, "deployment_backend.yaml"))

    def test_direct_renders_legacy_mappings_for_both_route_types(self):
        output = self.assert_rendered("mcp.routing.mode=direct")
        self.assertEqual(ingress_routes(output), INGRESS_DIRECT)
        self.assertEqual(http_routes(output), HTTP_DIRECT)
        self.assertIn("- name: MCP_SERVICE_INGRESS_DOMAIN", manifest(output, "deployment_backend.yaml"))

    def test_hostname_ingress_branch_follows_mode(self):
        output = self.assert_rendered("ingress.hostName=retool.example.com")
        self.assertEqual(ingress_routes(output), [INGRESS_DIRECT[-1]])
        output = self.assert_rendered("ingress.hostName=retool.example.com", "mcp.routing.mode=direct")
        self.assertEqual(ingress_routes(output), INGRESS_DIRECT)

    def test_explicit_true_legacy_flags_work_in_direct_mode(self):
        output = self.assert_rendered("mcp.routing.mode=direct", "mcp.ingress.enabled=true", "mcp.httpRoute.enabled=true")
        self.assertEqual(ingress_routes(output), INGRESS_DIRECT)
        self.assertEqual(http_routes(output), HTTP_DIRECT)

    def test_disabled_mcp_has_only_main_routes(self):
        output = self.assert_rendered("mcp.enabled=false", "mcp.routing.mode=direct", "mcp.ingress.enabled=true", "mcp.httpRoute.enabled=true")
        self.assertEqual(ingress_routes(output), [INGRESS_DIRECT[-1]])
        self.assertEqual(http_routes(output), [HTTP_DIRECT[-1]])
        self.assertNotIn("- name: MCP_SERVICE_INGRESS_DOMAIN", manifest(output, "deployment_backend.yaml"))

    def test_explicit_false_skips_direct_rules_on_that_surface(self):
        output = self.assert_rendered("mcp.routing.mode=direct", "mcp.ingress.enabled=false")
        self.assertEqual(ingress_routes(output), [INGRESS_DIRECT[-1]])
        self.assertEqual(http_routes(output), HTTP_DIRECT)
        output = self.assert_rendered("mcp.routing.mode=direct", "mcp.httpRoute.enabled=false")
        self.assertEqual(ingress_routes(output), INGRESS_DIRECT)
        self.assertEqual(http_routes(output), [HTTP_DIRECT[-1]])

    def test_custom_legacy_ports_survive_in_direct_mode(self):
        output = self.assert_rendered(
            "mcp.routing.mode=direct",
            "mcp.ingress.paths[0].path=/.well-known/oauth-authorization-server",
            "mcp.ingress.paths[0].pathType=Exact",
            "mcp.ingress.paths[0].target=backendInternal",
            "mcp.ingress.paths[0].port=3002",
            "mcp.httpRoute.rules[0].path=/mcp",
            "mcp.httpRoute.rules[0].pathType=PathPrefix",
            "mcp.httpRoute.rules[0].port=4020",
        )
        self.assertEqual(ingress_routes(output)[0], ("/.well-known/oauth-authorization-server", "Exact", BACKEND_API, "3002"))
        self.assertEqual(http_routes(output)[0], ("PathPrefix", "/mcp", MCP, "4020"))

    def test_explicit_false_is_accepted_in_backend_relay(self):
        output = self.assert_rendered("mcp.ingress.enabled=false", "mcp.httpRoute.enabled=false")
        self.assertEqual(ingress_routes(output), [INGRESS_DIRECT[-1]])
        self.assertEqual(http_routes(output), [HTTP_DIRECT[-1]])

    def test_old_explicit_true_flags_fail_with_migration_guidance(self):
        for surface in ("ingress", "httpRoute"):
            with self.subTest(surface=surface):
                self.assert_rejected(
                    f"mcp.{surface}.enabled=true conflicts with mcp.routing.mode=backendRelay",
                    f"mcp.{surface}.enabled=true",
                )

    def test_legacy_flags_reject_non_boolean_values(self):
        for surface in ("ingress", "httpRoute"):
            for value in ("0", ""):
                with self.subTest(surface=surface, value=value):
                    self.assert_rejected(
                        f"mcp.{surface}.enabled must be true, false, or null",
                        "mcp.routing.mode=direct",
                        f"mcp.{surface}.enabled={value}",
                    )

    def test_unknown_mode_fails_even_if_mcp_and_public_routes_are_disabled(self):
        self.assert_rejected('mcp.routing.mode must be "backendRelay" or "direct"', "mcp.routing.mode=other")
        self.assert_rejected(
            'mcp.routing.mode must be "backendRelay" or "direct"',
            "mcp.routing.mode=other", "mcp.enabled=false", "ingress.enabled=false", "httpRoute.enabled=false",
        )

    def test_missing_mode_gives_upgrade_guidance(self):
        self.assert_rejected(
            "mcp.routing.mode is missing: when upgrading from an older chart, use --reset-then-reuse-values",
            "mcp.routing=null",
        )


if __name__ == "__main__":
    unittest.main()
