"""Check that every AppArmor-related container honours the initImage override.

The wait-for-apparmor init containers on the code executor and JS executor,
and the AppArmor profile installer DaemonSet, used to hardcode busybox from
Docker Hub, so installs that mirror every image (private registries,
air-gapped clusters, GCP Marketplace) couldn't run them.
"""

import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PINNED = "busybox:1.37.0@sha256:b3255e7dfbcd10cb367af0d409747d511aeb66dfac98cf30e97e87e4207dd76f"


def render(*settings):
    command = [
        "helm", "template", "aa", "charts/retool",
        "--values", "charts/retool/ci/test-install-values.yaml",
        "--set", "workflows.enabled=true",
        "--set", "codeExecutor.useSeccompProfile=true",
        "--set", "codeExecutor.appArmorProfileInstaller=cos",
        "--set", "rr.enabled=true",
        "--set", "rr.gitServer.skipBlobStorageValidation=true",
        "--set", "rr.agentSandbox.externalSecret.name=sandbox-keys",
    ]
    for setting in settings:
        command.extend(("--set", setting))
    return subprocess.check_output(command, cwd=ROOT, text=True)


def images(output, source, container=None):
    found = []
    for document in output.split("\n---\n"):
        if f"# Source: retool/templates/{source}" not in document[:200]:
            continue
        lines = document.splitlines()
        for i, line in enumerate(lines):
            if container and line.strip() == f"- name: {container}":
                found.append(lines[i + 1].split("image:", 1)[1].strip())
            elif not container and line.strip().startswith("image:"):
                found.append(line.split("image:", 1)[1].strip())
    return found


class AppArmorImagesTest(unittest.TestCase):
    def test_defaults_stay_pinned(self):
        out = render()
        for source in ("deployment_code_executor.yaml", "deployment_js_executor.yaml"):
            self.assertEqual(images(out, source, "wait-for-apparmor"), [PINNED], source)
        self.assertTrue(images(out, "apparmor_nsjail_daemonset.yaml"))
        for image in images(out, "apparmor_nsjail_daemonset.yaml"):
            self.assertEqual(image, PINNED)

    def test_init_image_override_reaches_every_apparmor_container(self):
        out = render("initImage.repository=mirror.example/busybox", "initImage.digest=sha256:" + "c" * 64)
        expected = "mirror.example/busybox:1.37.0@sha256:" + "c" * 64
        for source in ("deployment_code_executor.yaml", "deployment_js_executor.yaml"):
            self.assertEqual(images(out, source, "wait-for-apparmor"), [expected], source)
        for image in images(out, "apparmor_nsjail_daemonset.yaml"):
            self.assertEqual(image, expected)

    def test_installer_image_still_overrides_the_daemonset(self):
        out = render("codeExecutor.appArmorInstallerImage=registry.example/tools:1")
        for image in images(out, "apparmor_nsjail_daemonset.yaml"):
            self.assertEqual(image, "registry.example/tools:1")

    def test_installer_gets_the_image_pull_secrets(self):
        # initImage may point at a registry that needs credentials; the installer
        # must get the same pullSecrets as the executors or it never starts.
        installer = "# Source: retool/templates/apparmor_nsjail_daemonset.yaml"
        default = [d for d in render().split("\n---\n") if installer in d]
        self.assertEqual(len(default), 1)
        self.assertNotIn("imagePullSecrets", default[0])
        out = render("image.pullSecrets[0].name=regcred")
        docs = [d for d in out.split("\n---\n") if installer in d]
        self.assertEqual(len(docs), 1)
        self.assertIn("      imagePullSecrets:\n        - name: regcred\n", docs[0])
        for source in ("deployment_code_executor.yaml", "deployment_js_executor.yaml"):
            (doc,) = [d for d in out.split("\n---\n")
                      if f"# Source: retool/templates/{source}" in d and "\nkind: Deployment\n" in d]
            self.assertIn("      imagePullSecrets:\n        - name: regcred\n", doc, source)


if __name__ == "__main__":
    unittest.main()
