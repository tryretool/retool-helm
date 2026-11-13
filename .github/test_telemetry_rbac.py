"""Render checks for the telemetry ClusterRole and ClusterRoleBinding names."""

import subprocess
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True

RBAC = "# Source: retool/templates/telemetry_rbac.yaml"


def render(release, namespace, *settings):
    command = [
        "helm", "template", release, "charts/retool",
        "--namespace", namespace,
        "--values", "charts/retool/ci/test-install-values.yaml",
        "--set", "telemetry.enabled=true",
    ]
    for setting in settings:
        command.extend(("--set", setting))
    return subprocess.check_output(command, cwd=ROOT, text=True)


def manifest(output, kind):
    for document in output.split("\n---\n"):
        if document.lstrip().startswith(RBAC) and f"\nkind: {kind}\n" in document:
            return document
    raise AssertionError(f"no {kind} rendered from {RBAC}")


def name(document):
    metadata = document.split("\nmetadata:\n", 1)[1]
    return metadata.split("name: ", 1)[1].split("\n", 1)[0].strip()


class TelemetryRbacTests(unittest.TestCase):
    def test_names_include_the_release_namespace(self):
        output = render("retool", "team-a")
        self.assertEqual(name(manifest(output, "ClusterRole")), "team-a-retool-telemetry")
        self.assertEqual(name(manifest(output, "ClusterRoleBinding")), "team-a-retool-telemetry")

    def test_binding_refers_to_its_own_cluster_role(self):
        binding = manifest(render("retool", "team-a"), "ClusterRoleBinding")
        self.assertIn("roleRef:\n  apiGroup: rbac.authorization.k8s.io\n  kind: ClusterRole\n  name: team-a-retool-telemetry\n", binding)
        self.assertIn("namespace: team-a\n", binding)

    def test_same_release_name_in_two_namespaces_does_not_collide(self):
        names = {
            kind: {name(manifest(render("retool", namespace), kind)) for namespace in ("team-a", "team-b")}
            for kind in ("ClusterRole", "ClusterRoleBinding")
        }
        for kind, rendered in names.items():
            with self.subTest(kind=kind):
                self.assertEqual(len(rendered), 2, rendered)

    def test_name_override_is_kept(self):
        output = render("retool", "team-a", "telemetry.nameOverride=metrics")
        self.assertEqual(name(manifest(output, "ClusterRole")), "team-a-retool-metrics")

    def test_disabled_rbac_renders_no_cluster_role(self):
        output = render("retool", "team-a", "telemetry.rbac.create=false")
        self.assertNotIn("\nkind: ClusterRole\n", output)


if __name__ == "__main__":
    unittest.main(verbosity=2)
