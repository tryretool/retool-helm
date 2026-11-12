"""Render checks for the js-executor NET_ADMIN/NET_RAW capabilities and iptables env var.

kubeconform (via kubeconform.sh + ci/test-js-executor-*-option.yaml) only validates the
schema of whatever Helm emits, so it would still pass if the version gating in
retool.jsExecutor.requiresNetAdmin / retool.jsExecutor.skipIptablesEnv were reversed.
These assertions pin the behavior on both sides of each cutoff:

  < 4.34.0 and non-semver tags: NET_ADMIN, NET_RAW, no DISABLE_IPTABLES_SECURITY_CONFIGURATION
  4.34.0 up to 4.58.0:          no NET_ADMIN/NET_RAW, DISABLE_IPTABLES_SECURITY_CONFIGURATION=true
  4.58.0 and later:             no NET_ADMIN/NET_RAW, no DISABLE_IPTABLES_SECURITY_CONFIGURATION
"""

import subprocess
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True

SOURCE = "# Source: retool/templates/deployment_js_executor.yaml"
LEGACY_CAPS = 'add: ["NET_ADMIN", "NET_RAW", "SETUID", "SETGID"]'
REDUCED_CAPS = 'add: ["SETUID", "SETGID"]'
IPTABLES_ENV = "- name: DISABLE_IPTABLES_SECURITY_CONFIGURATION\n            value: \"true\""


def render(*settings, option_file=None):
    command = [
        "helm", "template", "jsecaps", "charts/retool",
        "--values", "charts/retool/ci/test-install-values.yaml",
    ]
    if option_file:
        command.extend(("--values", f"charts/retool/ci/{option_file}"))
    for setting in settings:
        command.extend(("--set", setting))
    return subprocess.check_output(command, cwd=ROOT, text=True)


def js_executor_container(output):
    """Return the rendered js-executor container (not the init containers)."""
    for document in output.split("\n---\n"):
        if document.lstrip().startswith(SOURCE) and "\nkind: Deployment\n" in document:
            return document.split("      - name: js-executor\n", 1)[1]
    raise AssertionError("no js-executor Deployment rendered")


def render_tag(tag):
    return js_executor_container(render("rr.jsExecutor.enabled=true", f"rr.jsExecutor.image.tag={tag}"))


class JsExecutorCapabilityTests(unittest.TestCase):
    def assert_legacy(self, container):
        self.assertIn(LEGACY_CAPS, container)
        self.assertNotIn("DISABLE_IPTABLES_SECURITY_CONFIGURATION", container)

    def assert_skips_iptables(self, container):
        self.assertIn(REDUCED_CAPS, container)
        self.assertNotIn(LEGACY_CAPS, container)
        self.assertIn(IPTABLES_ENV, container)

    def assert_no_iptables_step(self, container):
        self.assertIn(REDUCED_CAPS, container)
        self.assertNotIn(LEGACY_CAPS, container)
        self.assertNotIn("DISABLE_IPTABLES_SECURITY_CONFIGURATION", container)

    def test_ci_option_files(self):
        legacy = js_executor_container(render(option_file="test-js-executor-enabled-option.yaml"))
        self.assert_legacy(legacy)
        self.assert_skips_iptables(js_executor_container(render(option_file="test-js-executor-no-net-admin-option.yaml")))
        self.assert_no_iptables_step(js_executor_container(render(option_file="test-js-executor-no-iptables-option.yaml")))

    def test_below_4_34_keeps_capabilities(self):
        for tag in ("3.123.4", "4.33.9", "4.33.99"):
            with self.subTest(tag=tag):
                self.assert_legacy(render_tag(tag))

    def test_non_semver_tags_are_treated_as_legacy(self):
        for tag in ("latest", "edge", "stable"):
            with self.subTest(tag=tag):
                self.assert_legacy(render_tag(tag))

    def test_4_34_up_to_4_58_drops_capabilities_and_skips_iptables(self):
        for tag in ("4.34.0", "4.34.17", "4.40.1", "4.57.9"):
            with self.subTest(tag=tag):
                self.assert_skips_iptables(render_tag(tag))

    def test_4_58_and_later_has_no_iptables_step(self):
        for tag in ("4.58.0", "4.62.0", "5.0.0-stable"):
            with self.subTest(tag=tag):
                self.assert_no_iptables_step(render_tag(tag))

    def test_inherits_top_level_image_tag(self):
        cases = {
            "3.123.4": self.assert_legacy,
            "4.33.9": self.assert_legacy,
            "4.34.0": self.assert_skips_iptables,
            "4.40.1": self.assert_skips_iptables,
            "4.58.0": self.assert_no_iptables_step,
        }
        for tag, check in cases.items():
            with self.subTest(tag=tag):
                check(js_executor_container(render("rr.jsExecutor.enabled=true", f"image.tag={tag}")))


if __name__ == "__main__":
    unittest.main()
