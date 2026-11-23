"""Check the code executor and JS executor service account options.

Every Retool workload used to share one service account, so a cloud identity
annotation on it (EKS IRSA, GKE Workload Identity) reached the executors that
run user code. codeExecutor.serviceAccount and rr.jsExecutor.serviceAccount let
them use a dedicated or existing account instead.
"""

import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CODE = "deployment_code_executor.yaml"
JS = "deployment_js_executor.yaml"
BACKEND = "deployment_backend.yaml"
SA_TEMPLATE = "serviceaccount_executors.yaml"


def render(*settings):
    command = [
        "helm", "template", "sa", "charts/retool",
        "--values", "charts/retool/ci/test-install-values.yaml",
        "--set", "workflows.enabled=true",
        "--set", "rr.enabled=true",
        "--set", "rr.gitServer.skipBlobStorageValidation=true",
        "--set", "rr.agentSandbox.externalSecret.name=sandbox-keys",
    ]
    for setting in settings:
        command.extend(("--set", setting))
    return subprocess.check_output(command, cwd=ROOT, text=True)


def documents(output, source):
    return [d for d in output.split("\n---\n") if f"# Source: retool/templates/{source}\n" in d]


def pod_account(output, source):
    for document in documents(output, source):
        if "\nkind: Deployment\n" in document:
            for line in document.splitlines():
                if line.strip().startswith("serviceAccountName:"):
                    return line.split(":", 1)[1].strip()
    raise AssertionError(f"no Deployment in {source}")


class ExecutorServiceAccountsTest(unittest.TestCase):
    def test_defaults_share_the_top_level_account(self):
        out = render()
        for source in (CODE, JS, BACKEND):
            self.assertEqual(pod_account(out, source), "sa-retool")
        self.assertEqual(documents(out, SA_TEMPLATE), [])

    def test_create_makes_a_dedicated_account(self):
        out = render(
            "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=arn:aws:iam::1:role/retool",
            "codeExecutor.serviceAccount.create=true",
            "rr.jsExecutor.serviceAccount.create=true",
            "rr.jsExecutor.serviceAccount.name=js-runner",
        )
        self.assertEqual(pod_account(out, CODE), "sa-retool-code-executor")
        self.assertEqual(pod_account(out, JS), "js-runner")
        self.assertEqual(pod_account(out, BACKEND), "sa-retool")
        accounts = documents(out, SA_TEMPLATE)
        self.assertEqual(len(accounts), 2)
        for document in accounts:
            self.assertIn("kind: ServiceAccount\nautomountServiceAccountToken: false\n", document)
            self.assertNotIn("role-arn", document)
        self.assertIn("  name: sa-retool-code-executor\n", accounts[0])
        self.assertIn("  name: js-runner\n", accounts[1])

    def test_created_account_annotations_and_automount(self):
        out = render(
            "codeExecutor.serviceAccount.create=true",
            "codeExecutor.serviceAccount.annotations.example\\.com/team=data",
            "codeExecutor.serviceAccount.automountToken=true",
        )
        (document,) = documents(out, SA_TEMPLATE)
        self.assertIn("automountServiceAccountToken: true\n", document)
        self.assertIn("  annotations:\n    example.com/team: data\n", document)

    def test_existing_account_is_used_without_creating_one(self):
        out = render("codeExecutor.serviceAccount.name=existing-runner")
        self.assertEqual(pod_account(out, CODE), "existing-runner")
        self.assertEqual(documents(out, SA_TEMPLATE), [])

    def test_no_account_when_the_executor_is_disabled(self):
        out = render(
            "workflows.enabled=false",
            "codeExecutor.enabled=false",
            "codeExecutor.serviceAccount.create=true",
            "rr.jsExecutor.enabled=false",
            "rr.jsExecutor.serviceAccount.create=true",
        )
        self.assertEqual(documents(out, SA_TEMPLATE), [])


if __name__ == "__main__":
    unittest.main()
