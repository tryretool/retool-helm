"""Render checks for js-executor, nsjail AppArmor installer and telemetry node placement."""

import subprocess
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True

JS_EXECUTOR = ("# Source: retool/templates/deployment_js_executor.yaml", "Deployment")
INSTALLER = ("# Source: retool/templates/apparmor_nsjail_daemonset.yaml", "DaemonSet")
TELEMETRY = ("# Source: retool/templates/deployment_telemetry.yaml", "Deployment")
GLOBAL_PLACEMENT = ("nodeSelector.pool=shared", "tolerations[0].key=shared", "tolerations[0].operator=Exists")


def render(option_file, *settings, json_settings=()):
    command = [
        "helm", "template", "placement", "charts/retool",
        "--values", "charts/retool/ci/test-install-values.yaml",
        "--values", f"charts/retool/ci/{option_file}",
    ]
    for setting in settings:
        command.extend(("--set", setting))
    for setting in json_settings:
        command.extend(("--set-json", setting))
    return subprocess.check_output(command, cwd=ROOT, text=True)


def manifest(output, source, kind):
    for document in output.split("\n---\n"):
        if document.lstrip().startswith(source) and f"\nkind: {kind}\n" in document:
            return document
    raise AssertionError(f"no {kind} rendered from {source}")


class PlacementTests(unittest.TestCase):
    def test_component_overrides_win_over_global(self):
        output = render("test-apparmor-nsjail-isolated-pool-option.yaml", *GLOBAL_PLACEMENT)
        for workload in (JS_EXECUTOR, INSTALLER):
            with self.subTest(workload=workload[1]):
                rendered = manifest(output, *workload)
                self.assertIn("nodeSelector:\n        kubernetes.io/os: linux", rendered)
                self.assertIn("key: retool.com/isolated", rendered)
                self.assertNotIn("pool: shared", rendered)
                self.assertNotIn("key: shared", rendered)

    def test_empty_overrides_fall_back_to_global(self):
        output = render("test-apparmor-nsjail-option.yaml", *GLOBAL_PLACEMENT)
        for workload in (JS_EXECUTOR, INSTALLER):
            with self.subTest(workload=workload[1]):
                rendered = manifest(output, *workload)
                self.assertIn("pool: shared", rendered)
                self.assertIn("key: shared", rendered)
                self.assertNotIn("retool.com/isolated", rendered)

    def test_installer_annotations_and_resources(self):
        installer = manifest(render("test-apparmor-nsjail-isolated-pool-option.yaml"), *INSTALLER)
        self.assertIn('sidecar.istio.io/inject: "false"', installer)
        install = installer.split("- name: install\n", 1)[1].split("- name: pause", 1)[0]
        self.assertIn("cpu: 200m\n              memory: 192Mi", install)

    def test_installer_default_resources(self):
        installer = manifest(render("test-apparmor-nsjail-option.yaml"), *INSTALLER)
        install = installer.split("- name: install\n", 1)[1].split("- name: pause", 1)[0]
        self.assertIn("limits:\n              cpu: 100m\n              memory: 128Mi", install)
        self.assertIn("requests:\n              cpu: 10m\n              memory: 32Mi", install)

    def test_telemetry_uses_global_placement(self):
        telemetry = manifest(render("test-telemetry-placement-option.yaml"), *TELEMETRY)
        self.assertIn("kubernetes.io/os: linux", telemetry)
        self.assertIn("key: example.com/dedicated", telemetry)

    def test_telemetry_extra_pod_spec_overrides_only_its_own_field(self):
        cases = {
            "custom nodeSelector": ('{"nodeSelector": {"pool": "telemetry"}}', "pool: telemetry", None),
            "empty nodeSelector": ('{"nodeSelector": {}}', "nodeSelector: {}", None),
            "custom tolerations": ('{"tolerations": [{"key": "telemetry", "operator": "Exists"}]}', None, "key: telemetry"),
            "empty tolerations": ('{"tolerations": []}', None, "tolerations: []"),
        }
        for name, (extra_pod_spec, node_selector, tolerations) in cases.items():
            with self.subTest(name):
                output = render(
                    "test-telemetry-placement-option.yaml",
                    json_settings=(f"telemetry.extraPodSpec={extra_pod_spec}",),
                )
                telemetry = manifest(output, *TELEMETRY)
                self.assertEqual(telemetry.count("nodeSelector:"), 1)
                self.assertEqual(telemetry.count("tolerations:"), 1)
                if node_selector:
                    self.assertIn(node_selector, telemetry)
                    self.assertNotIn("kubernetes.io/os: linux", telemetry)
                else:
                    self.assertIn("kubernetes.io/os: linux", telemetry)
                if tolerations:
                    self.assertIn(tolerations, telemetry)
                    self.assertNotIn("key: example.com/dedicated", telemetry)
                else:
                    self.assertIn("key: example.com/dedicated", telemetry)

if __name__ == "__main__":
    unittest.main()
