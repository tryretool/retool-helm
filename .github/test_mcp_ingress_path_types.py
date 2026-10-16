"""Check MCP ingress path types in rendered Helm manifests."""

import re
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASE = [
    "helm", "template", "mcp-ingress", "charts/retool",
    "--values", "charts/retool/ci/test-install-values.yaml",
    "--values", "charts/retool/ci/test-mcp-enabled-option.yaml",
]


def ingress_paths(*settings):
    command = BASE.copy()
    for setting in settings:
        command.extend(("--set", setting))
    output = subprocess.check_output(command, cwd=ROOT, text=True)
    ingress = output.split("# Source: retool/templates/ingress.yaml\n", 1)[1].split("\n---\n", 1)[0]
    return re.findall(r"(?m)^\s+- path: (\S+)\n\s+pathType: (\S+)", ingress)


class MCPIngressPathTypesTests(unittest.TestCase):
    def test_well_known_defaults_pass_nginx_strict_path_validation(self):
        self.assertEqual(ingress_paths()[:3], [
            ("/.well-known/oauth-authorization-server", "ImplementationSpecific"),
            ("/.well-known/oauth-protected-resource", "ImplementationSpecific"),
            ("/mcp", "Prefix"),
        ])

    def test_backend_internal_path_without_type_uses_compatible_default(self):
        paths = ingress_paths(
            "mcp.ingress.paths[0].path=/.well-known/oauth-authorization-server",
            "mcp.ingress.paths[0].target=backendInternal",
        )
        self.assertEqual(paths[0], ("/.well-known/oauth-authorization-server", "ImplementationSpecific"))

    def test_explicit_path_type_override_is_preserved(self):
        paths = ingress_paths(
            "mcp.ingress.paths[0].path=/.well-known/oauth-authorization-server",
            "mcp.ingress.paths[0].pathType=Exact",
            "mcp.ingress.paths[0].target=backendInternal",
        )
        self.assertEqual(paths[0], ("/.well-known/oauth-authorization-server", "Exact"))


if __name__ == "__main__":
    unittest.main()
