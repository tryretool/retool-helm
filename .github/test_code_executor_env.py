"""Check codeExecutor.env / codeExecutor.environmentVariables.

They let an install set environment that only the code executor reads without
putting it on every Retool pod via the top-level env.
"""

import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def render(*settings):
    command = [
        "helm", "template", "ce", "charts/retool",
        "--values", "charts/retool/ci/test-install-values.yaml",
        "--set", "workflows.enabled=true",
    ]
    for setting in settings:
        command.extend(("--set", setting))
    return subprocess.check_output(command, cwd=ROOT, text=True)


def env_names(output, source):
    for document in output.split("\n---\n"):
        if f"# Source: retool/templates/{source}" in document[:200] and "\nkind: Deployment\n" in document:
            return [line.split("- name:", 1)[1].strip().strip('"')
                    for line in document.splitlines() if line.strip().startswith("- name:")]
    raise AssertionError(f"no Deployment rendered from {source}")


def deployment(output, source):
    (document,) = [d for d in output.split("\n---\n")
                   if f"# Source: retool/templates/{source}\n" in d and "\nkind: Deployment\n" in d]
    return document


class CodeExecutorEnvTest(unittest.TestCase):
    def test_map_env_reaches_only_the_code_executor(self):
        out = render("codeExecutor.env.CODE_EXECUTOR_ONLY_SETTING=true")
        self.assertIn("CODE_EXECUTOR_ONLY_SETTING", env_names(out, "deployment_code_executor.yaml"))
        self.assertNotIn("CODE_EXECUTOR_ONLY_SETTING", env_names(out, "deployment_backend.yaml"))

    def test_list_env_reaches_the_code_executor(self):
        out = render("codeExecutor.environmentVariables[0].name=CE_ONLY",
                     "codeExecutor.environmentVariables[0].value=1")
        self.assertIn("CE_ONLY", env_names(out, "deployment_code_executor.yaml"))
        self.assertNotIn("CE_ONLY", env_names(out, "deployment_backend.yaml"))

    def test_secret_backed_list_entry_renders_in_full(self):
        out = render("codeExecutor.environmentVariables[0].name=CE_SECRET",
                     "codeExecutor.environmentVariables[0].valueFrom.secretKeyRef.name=ce-secrets",
                     "codeExecutor.environmentVariables[0].valueFrom.secretKeyRef.key=token")
        entry = ("- name: CE_SECRET\n"
                 "            valueFrom:\n"
                 "              secretKeyRef:\n"
                 "                key: token\n"
                 "                name: ce-secrets\n")
        self.assertIn(entry, deployment(out, "deployment_code_executor.yaml"))
        self.assertNotIn("CE_SECRET", deployment(out, "deployment_backend.yaml"))

    def test_code_executor_value_comes_after_the_shared_one(self):
        out = render("env.SHARED=global", "codeExecutor.env.SHARED=local")
        names = env_names(out, "deployment_code_executor.yaml")
        self.assertEqual(names.count("SHARED"), 2)
        for document in out.split("\n---\n"):
            if "deployment_code_executor.yaml" in document[:200] and "\nkind: Deployment\n" in document:
                self.assertLess(document.index('"global"'), document.index('"local"'))

    def test_defaults_add_nothing(self):
        self.assertEqual(env_names(render(), "deployment_code_executor.yaml"),
                         env_names(render("codeExecutor.env=null"), "deployment_code_executor.yaml"))


if __name__ == "__main__":
    unittest.main()
