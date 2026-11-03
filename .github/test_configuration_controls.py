"""Exercise dependency selection, connection migration, and exposure ownership."""

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PG = {
    "host": "postgres.example.com", "port": 5432, "database": "retool",
    "user": "retool", "ssl_enabled": True,
    "passwordSecretName": "database-credentials", "passwordSecretKey": "password",
}
TEMPORAL = {"host": "temporal.example.com", "port": 7233, "namespace": "workflows"}
PERSISTENCE = {
    store: {"sql": {"host": "postgres.example.com", "port": 5432,
                    "database": database, "user": "temporal",
                    "existingSecret": "temporal-database", "secretKey": "password"}}
    for store, database in [("default", "temporal"), ("visibility", "temporal_visibility")]
}
BUNDLE = {"server": {"config": {"persistence": PERSISTENCE}}}


def render(values, *fixtures):
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "values.json"
        path.write_text(json.dumps(values))
        command = ["helm", "template", "controls", "charts/retool",
                   "-f", "charts/retool/ci/test-install-values.yaml"]
        for fixture in fixtures:
            command.extend(["-f", f"charts/retool/ci/{fixture}"])
        command.extend(["-f", str(path), "--set", "postgresql.auth.postgresPassword=fixed-test-password", "--set", "jobRunner.enabled=true"])
        return subprocess.run(command, cwd=ROOT, text=True, capture_output=True)


def manifest(output, filename):
    marker = f"# Source: retool/templates/{filename}\n"
    return "\n---\n".join(document for document in output.split("\n---\n") if marker in document)


class ConfigurationTests(unittest.TestCase):
    def rendered(self, values, *fixtures):
        result = render(values, *fixtures)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("Warning:", result.stderr)
        return result.stdout

    def rejected(self, values, message):
        result = render(values)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(message, result.stderr)

    def test_unset_controls_preserve_bundled_database_and_legacy_routes(self):
        output = self.rendered({})
        self.assertIn("kind: StatefulSet", output)
        self.assertIn("kind: Ingress", output)
        self.assertNotIn("kind: HTTPRoute", output)
        self.assertNotIn("/retool-temporal-services-helm/templates/", output)
        self.assertEqual(output, self.rendered({"database": {"bundled": True}}))

    def test_external_database_matches_legacy_configuration_for_all_consumers(self):
        fixtures = (
            "standalone-dbconnector-enabled-option.yaml",
            "test-agents-enabled-option.yaml",
            "test-retoolos-enabled-option.yaml",
            "test-rr-app-serving-layer-separate-option.yaml",
        )
        common = {"multiplayer": {"enabled": True}}
        legacy = {**common, "postgresql": {"enabled": False}, "config": {"postgresql": PG}}
        canonical = {**common, "database": {"bundled": False, "external": PG}}
        output = self.rendered(canonical, *fixtures)
        self.assertEqual(output, self.rendered(legacy, *fixtures))
        self.assertNotIn("kind: StatefulSet", output)
        for filename in ("deployment_backend.yaml", "deployment_jobs.yaml",
                         "deployment_workflows.yaml", "deployment_dbconnector.yaml",
                         "deployment_multiplayer_ws.yaml", "deployment_git_server.yaml",
                         "deployment_rr_app_serving_layer.yaml", "deployment_workers.yaml"):
            document = manifest(output, filename)
            if filename != "deployment_dbconnector.yaml":
                self.assertIn('value: "postgres.example.com"', document)
            self.assertIn("name: database-credentials", document)
        sandbox = manifest(output, "deployment_agent_sandbox.yaml")
        self.assertIn("postgres://retool@postgres.example.com:5432/retool?sslmode=no-verify", sandbox)
        self.assertIn("name: database-credentials", sandbox)

    def test_plaintext_database_password_is_stored_in_the_existing_secret(self):
        pg = {k: v for k, v in PG.items() if not k.startswith("passwordSecret")}
        pg["password"] = "test-only-password"
        canonical = {"database": {"bundled": False, "external": pg}}
        legacy = {"postgresql": {"enabled": False}, "config": {"postgresql": pg}}
        self.assertEqual(self.rendered(canonical), self.rendered(legacy))

    def test_database_selector_overrides_legacy_switch_in_both_directions(self):
        output = self.rendered({"database": {"bundled": True}, "postgresql": {"enabled": False}})
        self.assertIn("kind: StatefulSet", output)
        self.assertIn('value: "controls-postgresql"', output)
        output = self.rendered({"database": {"bundled": False, "external": PG},
                                "postgresql": {"enabled": True}})
        self.assertNotIn("kind: StatefulSet", output)
        self.assertIn('value: "postgres.example.com"', output)

    def test_external_temporal_matches_both_legacy_connection_locations(self):
        canonical = {"temporal": {"bundled": False, "external": TEMPORAL}}
        output = self.rendered(canonical)
        self.assertEqual(output, self.rendered({"temporal": {"enabled": True, **TEMPORAL}}))
        self.assertEqual(output, self.rendered({"workflows": {"temporal": {"enabled": True, **TEMPORAL}}}))
        self.assertNotIn("/retool-temporal-services-helm/templates/", output)
        for filename in ("deployment_backend.yaml", "deployment_jobs.yaml",
                         "deployment_workflows.yaml", "deployment_workers.yaml"):
            self.assertIn('value: "temporal.example.com"', manifest(output, filename))

    def test_bundled_temporal_matches_legacy_and_controls_actual_dependency(self):
        legacy_bundle = {**BUNDLE, "enabled": True}
        legacy = {"retool-temporal-services-helm": legacy_bundle}
        canonical = {"temporal": {"bundled": True}, "retool-temporal-services-helm": BUNDLE}
        output = self.rendered(canonical)
        self.assertEqual(output, self.rendered(legacy))
        self.assertIn("/retool-temporal-services-helm/templates/server-deployment.yaml", output)
        self.assertIn("controls-retool-wf-temporal-temporal-frontend", output)
        # Saved legacy enabled=true must not leave an unused Temporal cluster running.
        output = self.rendered({"temporal": {"bundled": False, "external": TEMPORAL},
                                "retool-temporal-services-helm": legacy_bundle})
        self.assertNotIn("/retool-temporal-services-helm/templates/", output)
        self.assertIn('value: "temporal.example.com"', output)

    def test_no_temporal_preserves_postgres_orchestration_fallback(self):
        output = self.rendered({"image": {"tag": "4.87.0-edge"}, "temporal": {"bundled": False}},
                               "test-agent-sandbox-inherit-postgres-option.yaml")
        self.assertNotIn("/retool-temporal-services-helm/templates/", output)
        self.assertNotIn("name: WORKFLOW_TEMPORAL_CLUSTER_FRONTEND_HOST", output)
        self.assertIn("name: R2_ORCHESTRATION_BACKEND", output)

    def test_secret_backed_temporal_mtls_reaches_every_caller(self):
        temporal = {**TEMPORAL, "sslEnabled": True, "sslCert": "dGVzdC1jZXJ0",
                    "sslKeySecretName": "temporal-client", "sslKeySecretKey": "private-key"}
        output = self.rendered({"temporal": {"bundled": False, "external": temporal}})
        for filename in ("deployment_backend.yaml", "deployment_jobs.yaml",
                         "deployment_workflows.yaml", "deployment_workers.yaml"):
            document = manifest(output, filename)
            self.assertIn("name: WORKFLOW_TEMPORAL_TLS_KEY", document)
            self.assertIn("name: temporal-client", document)
            self.assertIn("key: private-key", document)

    def test_exposure_selects_one_route_owner_despite_legacy_switches(self):
        for mode, ingress, gateway in [("ingress", True, False), ("gateway", False, True),
                                        ("external", False, False)]:
            with self.subTest(mode=mode):
                output = self.rendered({"exposure": {"mode": mode}}, "test-mcp-enabled-option.yaml")
                self.assertEqual("kind: Ingress" in output, ingress)
                self.assertEqual("kind: HTTPRoute" in output, gateway)
                self.assertIn("name: controls-retool-mcp", output)
                if mode != "external":
                    self.assertIn("/.well-known/oauth-authorization-server", output)
                    self.assertIn("/.well-known/oauth-protected-resource", output)

    def test_exposure_preserves_mcp_relay_and_separate_apps_domain(self):
        for mode, filename in [("ingress", "ingress.yaml"), ("gateway", "httproute.yaml")]:
            output = self.rendered({"exposure": {"mode": mode}, "mcp": {"routing": {"mode": "backendRelay"}}},
                                   "test-mcp-enabled-option.yaml")
            self.assertNotIn("/mcp", manifest(output, filename))
        output = self.rendered({"exposure": {"mode": "external"}},
                               "test-rr-app-serving-layer-separate-option.yaml")
        self.assertIn("# Source: retool/templates/ingress_rr_app_serving_layer.yaml", output)
        self.assertNotIn("# Source: retool/templates/ingress.yaml", output)

    def test_legacy_can_still_create_both_route_types(self):
        output = self.rendered({}, "test-mcp-enabled-option.yaml")
        self.assertIn("kind: Ingress", output)
        self.assertIn("kind: HTTPRoute", output)

    def test_documented_examples_render_and_select_the_expected_dependencies(self):
        for example, bundled in [("aws-external-values.yaml", False),
                                  ("bundled-services-values.yaml", True)]:
            with self.subTest(example=example):
                result = subprocess.run(
                    ["helm", "template", "retool", "charts/retool", "-f", f"examples/{example}"],
                    cwd=ROOT, text=True, capture_output=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual("kind: StatefulSet" in result.stdout, bundled)
                self.assertEqual("/retool-temporal-services-helm/templates/" in result.stdout, bundled)
                self.assertEqual("kind: Ingress" in result.stdout, bundled)

    def test_new_controls_reject_bad_types_typos_and_incomplete_connections(self):
        for values, message in [
            ({'database': {'bundled': 'false'}}, 'bundled'),
            ({'database': {'mode': 'external'}}, 'mode'),
            ({'database': {'bundled': False}}, 'requires database.external'),
            ({'database': {'bundled': False, 'external': {k: v for k, v in PG.items() if not k.startswith('passwordSecret')}}}, 'requires passwordSecretName'),
            ({'database': {'external': PG}}, 'requires database.bundled=false'),
            ({'database': {'bundled': False, 'external': {'host': 'db'}}}, 'database'),
            ({'database': {'bundled': False, 'external': {**PG, 'port': 0}}}, 'port'),
            ({'temporal': {'bundled': 'false'}}, 'bundled'),
            ({'temporal': {'external': {'host': 'temporal'}}}, 'namespace'),
            ({'temporal': {'external': {**TEMPORAL, 'enabled': True}}}, 'enabled'),
            ({'exposure': {'mode': 'loadbalancer'}}, 'mode'),
            ({'exposure': {'enabled': True}}, 'enabled'),
        ]:
            with self.subTest(values=values):
                self.rejected(values, message)

    def test_new_and_legacy_connection_blocks_cannot_silently_override_each_other(self):
        self.rejected({"database": {"bundled": False, "external": PG},
                       "config": {"postgresql": PG}}, "cannot be combined")
        self.rejected({"database": {"bundled": True}, "config": {"postgresql": PG}},
                      "cannot be combined")
        for legacy in [{"enabled": True}, {"host": "other-temporal"}, {"sslKey": "old-key"}]:
            self.rejected({"temporal": {"external": TEMPORAL, **legacy}}, "cannot be combined")
        self.rejected({"temporal": {"external": TEMPORAL},
                       "workflows": {"temporal": {"enabled": True, **TEMPORAL}}}, "cannot be combined")
        self.rejected({"temporal": {"bundled": True, "external": TEMPORAL},
                       "retool-temporal-services-helm": BUNDLE}, "cannot be combined")


if __name__ == "__main__":
    unittest.main()
