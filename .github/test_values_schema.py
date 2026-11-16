"""Check that values.schema.json accepts valid values and rejects invalid ones.

Each annotated key should have at least one case here that the schema must
reject, so a later change can't loosen the schema without a test failing.
When you annotate a new section of values.yaml, add cases for it.
"""

import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASE = [
    "helm", "template", "schema", "charts/retool",
    "--values", "charts/retool/ci/test-install-values.yaml",
]
# Helm 3 and Helm 4 word schema errors differently but share this preamble.
SCHEMA_ERROR = "values don't meet the specifications of the schema"


def render(*args):
    return subprocess.run(BASE + list(args), cwd=ROOT, text=True, capture_output=True)


def supports_skip_schema_validation():
    help_text = subprocess.run(
        ["helm", "template", "--help"], text=True, capture_output=True
    ).stdout
    return "--skip-schema-validation" in help_text


class ValuesSchemaTests(unittest.TestCase):
    def assert_accepted(self, *args):
        result = render(*args)
        self.assertEqual(result.returncode, 0, result.stderr)

    def assert_rejected(self, key, *args):
        """Assert that the schema, not a template, rejects `key`."""
        result = render(*args)
        self.assertNotEqual(result.returncode, 0, "rendered, but the schema should have rejected it")
        self.assertIn(SCHEMA_ERROR, result.stderr)
        # Helm 3 reports `image.tag`, Helm 4 reports `/image/tag`.
        pointer = "/" + key.replace(".", "/")
        self.assertTrue(
            key in result.stderr or pointer in result.stderr,
            f"expected an error about {key}, got:\n{result.stderr}",
        )

    # image

    def test_ci_values_are_accepted(self):
        self.assert_accepted()

    def test_empty_image_tag_is_rejected(self):
        self.assert_rejected("image.tag", "--set", "image.tag=")

    def test_unknown_pull_policy_is_rejected(self):
        self.assert_rejected("image.pullPolicy", "--set", "image.pullPolicy=Sometimes")

    def test_non_string_repository_is_rejected(self):
        self.assert_rejected("image.repository", "--set-json", "image.repository=123")

    def test_pull_secrets_accepts_a_list(self):
        self.assert_accepted("--set-json", 'image.pullSecrets=[{"name":"my-registry"}]')

    def test_pull_secrets_rejects_a_string(self):
        self.assert_rejected("image.pullSecrets", "--set", "image.pullSecrets=my-registry")

    @unittest.skipUnless(supports_skip_schema_validation(), "needs Helm 3.16+")
    def test_template_still_requires_image_tag_without_the_schema(self):
        result = render("--set", "image.tag=", "--skip-schema-validation")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("Please set a value for .Values.image.tag", result.stderr)

    # Sections not yet annotated, and unknown keys

    def test_unknown_keys_are_accepted(self):
        # Flips once unknown keys are rejected (strict mode).
        self.assert_accepted("--set", "backend.notAKey=1", "--set", "notATopLevelKey=1")


if __name__ == "__main__":
    unittest.main()
