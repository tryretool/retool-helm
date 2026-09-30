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
    return output.rsplit(marker, 1)[1].split("\n---\n", 1)[0]


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
    ("/.well-known/oauth-authorization-server", "ImplementationSpecific", BACKEND_API, "3001"),
    ("/.well-known/oauth-protected-resource", "ImplementationSpecific", MCP, "4010"),
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

    def test_default_direct_preserves_legacy_routes_for_both_route_types(self):
        output = self.assert_rendered()
        self.assertEqual(ingress_routes(output), INGRESS_DIRECT)
        self.assertEqual(http_routes(output), HTTP_DIRECT)
        self.assertIn('value: "http://routing-retool-mcp:4010"', manifest(output, "deployment_backend.yaml"))
        self.assertIn("- name: MCP_SERVICE_INGRESS_DOMAIN", manifest(output, "deployment_backend.yaml"))

    def test_backend_relay_uses_main_service_for_both_route_types(self):
        output = self.assert_rendered("mcp.routing.mode=backendRelay")
        self.assertEqual(ingress_routes(output), [INGRESS_DIRECT[-1]])
        self.assertEqual(http_routes(output), [HTTP_DIRECT[-1]])
        self.assertIn("- name: MCP_SERVICE_INGRESS_DOMAIN", manifest(output, "deployment_backend.yaml"))

    def test_hostname_ingress_branch_follows_mode(self):
        output = self.assert_rendered("ingress.hostName=retool.example.com")
        self.assertEqual(ingress_routes(output), INGRESS_DIRECT)
        output = self.assert_rendered("ingress.hostName=retool.example.com", "mcp.routing.mode=backendRelay")
        self.assertEqual(ingress_routes(output), [INGRESS_DIRECT[-1]])

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

    def test_backend_internal_path_without_type_uses_nginx_compatible_default(self):
        output = self.assert_rendered(
            "mcp.ingress.paths[0].path=/.well-known/oauth-authorization-server",
            "mcp.ingress.paths[0].target=backendInternal",
        )
        self.assertEqual(ingress_routes(output)[0], INGRESS_DIRECT[0])

    def test_explicit_false_is_accepted_in_backend_relay(self):
        output = self.assert_rendered("mcp.routing.mode=backendRelay", "mcp.ingress.enabled=false", "mcp.httpRoute.enabled=false")
        self.assertEqual(ingress_routes(output), [INGRESS_DIRECT[-1]])
        self.assertEqual(http_routes(output), [HTTP_DIRECT[-1]])

    def test_old_explicit_true_flags_fail_with_migration_guidance(self):
        for surface in ("ingress", "httpRoute"):
            with self.subTest(surface=surface):
                self.assert_rejected(
                    f"mcp.{surface}.enabled=true conflicts with mcp.routing.mode=backendRelay",
                    "mcp.routing.mode=backendRelay",
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

    def test_unknown_mode_fails_when_public_routes_are_enabled(self):
        self.assert_rejected('mcp.routing.mode must be "backendRelay" or "direct"', "mcp.routing.mode=other")

    def test_mode_is_not_validated_without_chart_managed_public_routes(self):
        for routing in ("mcp.routing.mode=other", "mcp.routing=null"):
            with self.subTest(routing=routing):
                self.assert_rendered(routing, "ingress.enabled=false", "httpRoute.enabled=false")

    def test_missing_mode_gives_upgrade_guidance(self):
        self.assert_rejected(
            "mcp.routing.mode is missing: when upgrading from an older chart, use --reset-then-reuse-values",
            "mcp.routing=null",
        )

    def test_missing_mode_is_ignored_when_mcp_is_disabled(self):
        output = self.assert_rendered("mcp.routing=null", "mcp.enabled=false")
        self.assertEqual(ingress_routes(output), [INGRESS_DIRECT[-1]])
        self.assertEqual(http_routes(output), [HTTP_DIRECT[-1]])

    def test_base_domain_is_the_mcp_public_fallback_in_both_modes(self):
        for mode in ("backendRelay", "direct"):
            with self.subTest(mode=mode):
                output = self.assert_rendered(
                    f"mcp.routing.mode={mode}",
                    "env.BASE_DOMAIN=https://retool.example.com",
                    "mcp.config.mcpServiceExternalUrl=",
                    "mcp.config.oauthMainDomain=",
                )
                mcp = manifest(output, "deployment_mcp.yaml")
                self.assertIn('name: "BASE_DOMAIN"\n            value: "https://retool.example.com"', mcp)
                self.assertIn('name: OAUTH_MAIN_DOMAIN\n            value: "retool.example.com"', mcp)
                self.assertNotIn("- name: MCP_SERVICE_EXTERNAL_URL", mcp)

    def test_explicit_external_url_is_shared_and_normalized(self):
        for settings in (
            ("mcp.config.mcpServiceExternalUrl=retool.example.com",),
            ("mcp.environmentVariables[0].name=MCP_SERVICE_EXTERNAL_URL",
             "mcp.environmentVariables[0].value=retool.example.com"),
        ):
            with self.subTest(settings=settings):
                output = self.assert_rendered(*settings)
                for deployment in ("deployment_mcp.yaml", "deployment_backend.yaml"):
                    self.assertRegex(manifest(output, deployment),
                                     r'name: MCP_SERVICE_EXTERNAL_URL\n            value: "?https://retool.example.com"?')

    def test_explicit_backend_external_url_is_not_duplicated(self):
        output = self.assert_rendered(
            "env.MCP_SERVICE_EXTERNAL_URL=https://retool.example.com",
            "mcp.environmentVariables[0].name=MCP_SERVICE_EXTERNAL_URL",
            "mcp.environmentVariables[0].value=retool.example.com",
        )
        for deployment in ("deployment_backend.yaml", "deployment_mcp.yaml"):
            self.assertEqual(len(re.findall(r'name: "?MCP_SERVICE_EXTERNAL_URL"?',
                                    manifest(output, deployment))), 1)

    def test_public_origin_can_match_either_managed_route(self):
        output = self.assert_rendered(
            "env.BASE_DOMAIN=https://retool.example.com",
            "ingress.hosts[0].host=other.example.com",
            "httpRoute.enabled=true",
            "httpRoute.hostnames[0]=retool.example.com",
        )
        self.assertIn("kind: HTTPRoute", output)
        self.assert_rejected(
            'BASE_DOMAIN host "retool.example.com" does not match any chart-managed Ingress or HTTPRoute host',
            "env.BASE_DOMAIN=https://retool.example.com",
            "ingress.hosts[0].host=other.example.com",
            "httpRoute.enabled=true",
            "httpRoute.hostnames[0]=other.example.com",
        )

    def test_secret_backed_base_domain_requires_explicit_oauth_host(self):
        secret = 'env.BASE_DOMAIN={"valueFrom":{"secretKeyRef":{"name":"public-origin","key":"url"}}}'
        command = BASE.copy()
        command.extend(("--set-json", secret, "--set", "mcp.config.oauthMainDomain="))
        result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("a secret-backed BASE_DOMAIN requires an explicit OAuth host", result.stderr)

        command.extend(("--set", "mcp.config.oauthMainDomain=retool.example.com"))
        result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("name: public-origin", manifest(result.stdout, "deployment_mcp.yaml"))

    def test_mcp_base_domain_environment_variable_derives_oauth_host(self):
        output = self.assert_rendered(
            "mcp.config.oauthMainDomain=",
            "mcp.environmentVariables[0].name=BASE_DOMAIN",
            "mcp.environmentVariables[0].value=https://retool.example.com",
        )
        self.assertIn('name: OAUTH_MAIN_DOMAIN\n            value: "retool.example.com"',
                      manifest(output, "deployment_mcp.yaml"))


if __name__ == "__main__":
    unittest.main()
