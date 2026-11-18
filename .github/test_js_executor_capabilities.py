"""Render checks for the js-executor NET_ADMIN/NET_RAW capabilities and iptables env var.

kubeconform (via kubeconform.sh + ci/test-js-executor-*-option.yaml) only validates the
schema of whatever Helm emits, so it would still pass if the gating in
retool.jsExecutor.requiresNetAdmin / retool.jsExecutor.skipIptablesEnv were reversed.
These assertions pin the behavior on both sides of each cutoff and of the
rr.jsExecutor.netAdmin tri-state flag:

  netAdmin null on < 4.58.0 or non-semver tags: NET_ADMIN, NET_RAW, no DISABLE_IPTABLES_SECURITY_CONFIGURATION
  netAdmin null on >= 4.58.0:                   no NET_ADMIN/NET_RAW, no DISABLE_IPTABLES_SECURITY_CONFIGURATION
  netAdmin false:                                no NET_ADMIN/NET_RAW; DISABLE_IPTABLES_SECURITY_CONFIGURATION=true on 4.34.0-4.58.0 only
  netAdmin true:                                 NET_ADMIN, NET_RAW (overrides version detection)
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


def render_tag(tag, net_admin=None):
    settings = ["rr.jsExecutor.enabled=true", f"rr.jsExecutor.image.tag={tag}"]
    if net_admin is not None:
        settings.append(f"rr.jsExecutor.netAdmin={str(net_admin).lower()}")
    return js_executor_container(render(*settings))


class JsExecutorCapabilityTests(unittest.TestCase):
    def assert_legacy(self, container):
        self.assertIn(LEGACY_CAPS, container)
        self.assertNotIn(IPTABLES_ENV, container)

    def assert_skips_iptables(self, container):
        self.assertIn(REDUCED_CAPS, container)
        self.assertNotIn(LEGACY_CAPS, container)
        self.assertIn(IPTABLES_ENV, container)

    def assert_no_iptables_step(self, container):
        self.assertIn(REDUCED_CAPS, container)
        self.assertNotIn(LEGACY_CAPS, container)
        self.assertNotIn(IPTABLES_ENV, container)

    def test_ci_option_files(self):
        legacy = js_executor_container(render(option_file="test-js-executor-enabled-option.yaml"))
        self.assert_legacy(legacy)
        # netAdmin: false on 4.34.0 -> no capabilities, iptables env set
        self.assert_skips_iptables(js_executor_container(render(option_file="test-js-executor-no-net-admin-option.yaml")))
        # default (null) on 4.58.0 -> no capabilities, no iptables env
        self.assert_no_iptables_step(js_executor_container(render(option_file="test-js-executor-no-iptables-option.yaml")))

    def test_below_4_58_keeps_capabilities_by_default(self):
        for tag in ("3.123.4", "4.33.9", "4.33.99", "4.34.0", "4.40.1", "4.57.9"):
            with self.subTest(tag=tag):
                self.assert_legacy(render_tag(tag))

    def test_non_semver_tags_are_treated_as_legacy(self):
        for tag in ("latest", "edge", "stable"):
            with self.subTest(tag=tag):
                self.assert_legacy(render_tag(tag))

    def test_4_58_and_later_drops_capabilities_by_default(self):
        for tag in ("4.58.0", "4.62.0", "5.0.0-stable"):
            with self.subTest(tag=tag):
                self.assert_no_iptables_step(render_tag(tag))

    def test_netadmin_false_drops_capabilities_and_skips_iptables_on_4_34_to_4_57(self):
        self.assert_skips_iptables(render_tag("4.34.0", net_admin=False))
        self.assert_skips_iptables(render_tag("4.40.1", net_admin=False))
        self.assert_skips_iptables(render_tag("4.57.9", net_admin=False))

    def test_netadmin_false_drops_capabilities_without_iptables_env_elsewhere(self):
        # Below 4.34 the iptables env var is not meaningful (iptables is the only
        # isolation), and on 4.58+ start.sh ignores the env var.
        self.assert_no_iptables_step(render_tag("3.123.4", net_admin=False))
        self.assert_no_iptables_step(render_tag("4.58.0", net_admin=False))

    def test_netadmin_true_forces_capabilities_on_any_version(self):
        for tag in ("3.123.4", "4.34.0", "4.58.0"):
            with self.subTest(tag=tag):
                self.assert_legacy(render_tag(tag, net_admin=True))

    def test_inherits_top_level_image_tag(self):
        cases = {
            "3.123.4": self.assert_legacy,
            "4.33.9": self.assert_legacy,
            "4.34.0": self.assert_legacy,
            "4.40.1": self.assert_legacy,
            "4.58.0": self.assert_no_iptables_step,
        }
        for tag, check in cases.items():
            with self.subTest(tag=tag):
                check(js_executor_container(render("rr.jsExecutor.enabled=true", f"image.tag={tag}")))


if __name__ == "__main__":
    unittest.main()
