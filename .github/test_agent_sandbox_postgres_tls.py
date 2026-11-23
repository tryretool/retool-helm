"""Check the agent sandbox controller/proxy Postgres TLS options.

The chart assembles the controller and proxy DSN itself on the host and inherit
paths, and used to hardcode sslmode=no-verify when inheriting a backend with SSL,
with no way to mount a CA bundle. These assertions pin postgres.sslMode,
postgres.sslRootCert and rr.agentSandbox.extraVolumes / extraVolumeMounts.
"""

import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = "# Source: retool/templates/deployment_agent_sandbox.yaml\n"
CA = "/etc/ssl/rds/ca.pem"
# ci/test-install-values.yaml uses the postgresql subchart, whose ssl_enabled
# takes precedence; set both so the tests hold either way.
SSL_ON = ("postgresql.ssl_enabled=true", "config.postgresql.ssl_enabled=true")
SSL_OFF = ("postgresql.ssl_enabled=false", "config.postgresql.ssl_enabled=false")


def render(*settings):
    command = [
        "helm", "template", "pgtls", "charts/retool",
        "--values", "charts/retool/ci/test-install-values.yaml",
        "--set", "rr.enabled=true",
        "--set", "rr.gitServer.skipBlobStorageValidation=true",
        "--set", "rr.agentSandbox.externalSecret.name=sandbox-keys",
    ]
    for setting in settings:
        command.extend(("--set", setting))
    return subprocess.run(command, cwd=ROOT, text=True, capture_output=True)


def deployments(output):
    return [d for d in output.split("\n---\n") if SOURCE in d and "\nkind: Deployment\n" in d]


def dsns(output):
    found = []
    for document in deployments(output):
        lines = document.splitlines()
        for i, line in enumerate(lines):
            if line.strip() == "- name: AGENT_SANDBOX_POSTGRES_URL":
                found.append(lines[i + 1].split("value:", 1)[1].strip().strip('"'))
    return found


class AgentSandboxPostgresTlsTest(unittest.TestCase):
    def assert_rendered(self, *settings):
        result = render(*settings)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(deployments(result.stdout)), 2)
        return result.stdout

    def assert_rejected(self, message, *settings):
        result = render(*settings)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(message, result.stderr)

    def test_inherit_keeps_no_verify_by_default(self):
        out = self.assert_rendered(*SSL_ON)
        found = dsns(out)
        self.assertEqual(len(found), 2)
        for dsn in found:
            self.assertTrue(dsn.endswith("?sslmode=no-verify"), dsn)

    def test_inherit_without_ssl_adds_nothing(self):
        out = self.assert_rendered(*SSL_OFF)
        found = dsns(out)
        self.assertEqual(len(found), 2)
        for dsn in found:
            self.assertNotIn("?", dsn)

    def test_inherit_verify_full_with_root_cert(self):
        out = self.assert_rendered(
            *SSL_ON,
            "rr.agentSandbox.postgres.sslMode=verify-full",
            f"rr.agentSandbox.postgres.sslRootCert={CA}",
        )
        found = dsns(out)
        self.assertEqual(len(found), 2)
        for dsn in found:
            self.assertTrue(dsn.endswith(f"?sslmode=verify-full&sslrootcert={CA}"), dsn)

    def test_host_path_appends_params(self):
        out = self.assert_rendered(
            "rr.agentSandbox.postgres.host=db.example",
            "rr.agentSandbox.postgres.user=agent",
            "rr.agentSandbox.postgres.database=retool",
            "rr.agentSandbox.postgres.password=secret",
            "rr.agentSandbox.postgres.sslMode=verify-full",
            f"rr.agentSandbox.postgres.sslRootCert={CA}",
        )
        found = dsns(out)
        self.assertEqual(len(found), 2)
        for dsn in found:
            self.assertEqual(dsn, f"postgres://agent@db.example:5432/retool?sslmode=verify-full&sslrootcert={CA}")

    def test_host_path_unchanged_by_default(self):
        out = self.assert_rendered(
            *SSL_ON,
            "rr.agentSandbox.postgres.host=db.example",
            "rr.agentSandbox.postgres.user=agent",
            "rr.agentSandbox.postgres.database=retool",
            "rr.agentSandbox.postgres.password=secret",
        )
        found = dsns(out)
        self.assertEqual(len(found), 2)
        for dsn in found:
            self.assertEqual(dsn, "postgres://agent@db.example:5432/retool")

    def test_extra_volumes_on_controller_and_proxy(self):
        out = self.assert_rendered(
            "rr.agentSandbox.extraVolumes[0].name=rds-ca",
            "rr.agentSandbox.extraVolumes[0].configMap.name=rds-ca",
            "rr.agentSandbox.extraVolumeMounts[0].name=rds-ca",
            "rr.agentSandbox.extraVolumeMounts[0].mountPath=/etc/ssl/rds",
            "rr.agentSandbox.extraVolumeMounts[0].readOnly=true",
        )
        for document in deployments(out):
            self.assertIn("        - configMap:\n            name: rds-ca\n          name: rds-ca\n", document)
            self.assertIn("            - mountPath: /etc/ssl/rds\n              name: rds-ca\n              readOnly: true\n", document)
            self.assertIn("            - name: tmp\n              mountPath: /tmp\n", document)

    def test_rejects_ssl_options_with_verbatim_dsn(self):
        message = "only apply when the chart assembles the DSN"
        self.assert_rejected(message, "rr.agentSandbox.postgres.url=postgres://a@b/c", "rr.agentSandbox.postgres.sslMode=verify-full")
        self.assert_rejected(message, "rr.agentSandbox.postgres.urlSecretName=pg", f"rr.agentSandbox.postgres.sslRootCert={CA}")

    def test_rejects_unknown_ssl_mode(self):
        self.assert_rejected("sslMode must be one of", "rr.agentSandbox.postgres.sslMode=verify")

    def test_rejects_unsafe_root_cert_path(self):
        for path in ("relative/ca.pem", "/etc/ca.pem&sslmode=disable", "/etc/my ca.pem"):
            self.assert_rejected("sslRootCert must be an absolute file path", f"rr.agentSandbox.postgres.sslRootCert={path}")


if __name__ == "__main__":
    unittest.main()
