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
            # The last document has no trailing newline; restore it so
            # line-anchored assertions hold wherever the document lands.
            return document.rstrip("\n") + "\n"
    raise AssertionError(f"no {kind} rendered from {RBAC}")


def name(document):
    metadata = document.split("\nmetadata:\n", 1)[1]
    return metadata.split("name: ", 1)[1].split("\n", 1)[0].strip()


class TelemetryRbacTests(unittest.TestCase):
    def test_names_include_the_release_namespace(self):
        output = render("retool", "team-a")
        self.assertEqual(name(manifest(output, "ClusterRole")), "team-a.retool-telemetry")
        self.assertEqual(name(manifest(output, "ClusterRoleBinding")), "team-a.retool-telemetry")

    def test_binding_refers_to_its_own_cluster_role(self):
        binding = manifest(render("retool", "team-a"), "ClusterRoleBinding")
        self.assertIn("roleRef:\n  apiGroup: rbac.authorization.k8s.io\n  kind: ClusterRole\n  name: team-a.retool-telemetry\n", binding)
        self.assertIn("namespace: team-a\n", binding)

    def test_same_release_name_in_two_namespaces_does_not_collide(self):
        names = {
            kind: {name(manifest(render("retool", namespace), kind)) for namespace in ("team-a", "team-b")}
            for kind in ("ClusterRole", "ClusterRoleBinding")
        }
        for kind, rendered in names.items():
            with self.subTest(kind=kind):
                self.assertEqual(len(rendered), 2, rendered)

    def test_hyphens_in_namespace_and_release_do_not_collide(self):
        pairs = (("retool", "team-a"), ("a-retool", "team"))
        names = {
            kind: {name(manifest(render(release, namespace), kind)) for release, namespace in pairs}
            for kind in ("ClusterRole", "ClusterRoleBinding")
        }
        for kind, rendered in names.items():
            with self.subTest(kind=kind):
                self.assertEqual(len(rendered), 2, rendered)

    def test_name_override_is_kept(self):
        output = render("retool", "team-a", "telemetry.nameOverride=metrics")
        self.assertEqual(name(manifest(output, "ClusterRole")), "team-a.retool-metrics")

    def test_disabled_rbac_renders_no_cluster_role(self):
        output = render("retool", "team-a", "telemetry.rbac.create=false")
        self.assertNotIn("\nkind: ClusterRole\n", output)



TELEMETRY = "# Source: retool/templates/deployment_telemetry.yaml"


def telemetry_image(*settings):
    output = render("retool", "default", *settings)
    for document in output.split("\n---\n"):
        if document.lstrip().startswith(TELEMETRY) and "\nkind: Deployment\n" in document:
            return document.split("image: '", 1)[1].split("'", 1)[0]
    raise AssertionError(f"no Deployment rendered from {TELEMETRY}")


class TelemetryImageTagTest(unittest.TestCase):
    def test_inherits_plain_image_tag(self):
        self.assertTrue(telemetry_image("image.tag=3.284.0").endswith(":3.284.0"))

    def test_drops_backend_digest_from_inherited_tag(self):
        digest = "sha256:" + "a" * 64
        image = telemetry_image(f"image.tag=3.284.0@{digest}")
        self.assertTrue(image.endswith(":3.284.0"), image)
        self.assertNotIn("sha256", image)

    def test_explicit_telemetry_tag_wins(self):
        image = telemetry_image("image.tag=3.284.0@sha256:" + "a" * 64, "telemetry.image.tag=1.2.3@sha256:" + "b" * 64)
        self.assertTrue(image.endswith(":1.2.3@sha256:" + "b" * 64), image)

if __name__ == "__main__":
    unittest.main(verbosity=2)
