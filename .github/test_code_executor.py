"""Check code-executor enablement in rendered Helm manifests.

kubeconform (via kubeconform.sh + ci/test-code-executor-enabled-option.yaml)
only validates the schema of whatever Helm emits, so it cannot catch a
regression that stops emitting the code-executor at all. These assertions pin
the actual behavior of codeExecutor.enabled: the standalone executor renders
with workflows off, the backend is wired to it, workflow workloads stay absent,
and the inherit / override / validation paths behave as documented.
"""

import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASE = [
    "helm", "template", "codeexec", "charts/retool",
    "--values", "charts/retool/ci/test-install-values.yaml",
]

CE_DEPLOYMENT = "deployment_code_executor.yaml"
CE_CONFIGMAP = "configmap_code_executor.yaml"
BACKEND = "deployment_backend.yaml"
WORKFLOW_DEPLOYMENT = "deployment_workflows.yaml"
APPARMOR_DAEMONSET = "apparmor_nsjail_daemonset.yaml"

CODE_EXECUTOR_ENV = "- name: CODE_EXECUTOR_INGRESS_DOMAIN"
WORKFLOW_BACKEND_ENV = "- name: WORKFLOW_BACKEND_HOST"


def render(*settings):
    command = BASE.copy()
    for setting in settings:
        command.extend(("--set", setting))
    return subprocess.run(command, cwd=ROOT, text=True, capture_output=True)


def has_source(output, filename):
    return f"# Source: retool/templates/{filename}\n" in output


def manifest(output, filename):
    marker = f"# Source: retool/templates/{filename}\n"
    return output.split(marker, 1)[1].split("\n---\n", 1)[0]


class CodeExecutorEnabledTests(unittest.TestCase):
    def assert_rendered(self, *settings):
        result = render(*settings)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def assert_rejected(self, message, *settings):
        result = render(*settings)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(message, result.stderr)

    def test_standalone_renders_with_workflows_off(self):
        # workflows disabled, code executor explicitly enabled: the executor
        # workload + its ConfigMap render and the backend is wired to it, while
        # the workflows stack stays absent. This is the regression Greptile
        # flagged -- restoring the old workflows-only gate would fail here.
        output = self.assert_rendered(
            "workflows.enabled=false",
            "codeExecutor.enabled=true",
            "codeExecutor.useSeccompProfile=true",
        )
        self.assertTrue(has_source(output, CE_DEPLOYMENT))
        self.assertTrue(has_source(output, CE_CONFIGMAP))
        self.assertIn("name: codeexec-retool-code-executor", manifest(output, CE_DEPLOYMENT))
        self.assertIn(CODE_EXECUTOR_ENV, manifest(output, BACKEND))
        # workflows are off, so the workflow workloads and their backend host
        # must not render.
        self.assertFalse(has_source(output, WORKFLOW_DEPLOYMENT))
        self.assertNotIn(WORKFLOW_BACKEND_ENV, manifest(output, BACKEND))

    def test_null_inherits_workflows_off(self):
        # Default (enabled: null) with workflows off -> no code executor.
        output = self.assert_rendered("workflows.enabled=false")
        self.assertFalse(has_source(output, CE_DEPLOYMENT))
        self.assertFalse(has_source(output, CE_CONFIGMAP))
        self.assertNotIn(CODE_EXECUTOR_ENV, manifest(output, BACKEND))

    def test_null_inherits_workflows_on(self):
        # Default (enabled: null) with workflows on (base enables via image.tag)
        # -> code executor renders and the backend is wired to it. Back-compat.
        output = self.assert_rendered()
        self.assertTrue(has_source(output, CE_DEPLOYMENT))
        self.assertIn(CODE_EXECUTOR_ENV, manifest(output, BACKEND))
        self.assertIn(WORKFLOW_BACKEND_ENV, manifest(output, BACKEND))

    def test_explicit_false_with_workflows_off_disables(self):
        output = self.assert_rendered("workflows.enabled=false", "codeExecutor.enabled=false")
        self.assertFalse(has_source(output, CE_DEPLOYMENT))
        self.assertNotIn(CODE_EXECUTOR_ENV, manifest(output, BACKEND))

    def test_workflows_on_with_code_executor_off_is_rejected(self):
        # Workflows need the code executor; this combination would ship a broken
        # workflows stack, so it must fail loudly.
        self.assert_rejected(
            "workflows are enabled but codeExecutor.enabled is false",
            "codeExecutor.enabled=false",
        )

    def test_non_boolean_enabled_is_rejected(self):
        for value in ("notabool", "1", "yes"):
            with self.subTest(value=value):
                self.assert_rejected(
                    "codeExecutor.enabled must be true, false, or unset/null",
                    f"codeExecutor.enabled={value}",
                )

    def test_apparmor_installer_renders_for_standalone_executor(self):
        # The shared nsjail AppArmor installer must still render for a standalone
        # code executor (workflows off), otherwise its wait-for-apparmor init
        # container would hang on a DaemonSet that never gets created.
        output = self.assert_rendered(
            "workflows.enabled=false",
            "codeExecutor.enabled=true",
            "codeExecutor.useSeccompProfile=true",
            "codeExecutor.appArmorProfileInstaller=true",
        )
        self.assertTrue(has_source(output, APPARMOR_DAEMONSET))


if __name__ == "__main__":
    unittest.main()
