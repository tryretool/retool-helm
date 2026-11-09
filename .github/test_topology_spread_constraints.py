"""Render checks for topologySpreadConstraints selectors and override order."""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True

OPTION_FILE = "charts/retool/ci/test-topology-spread-constraints-option.yaml"
# Deployments that read the global list in the option file.
SPREAD_DEPLOYMENTS = (
    "retool",
    "retool-workflow-backend",
    "retool-workflow-worker",
    "retool-agent-worker",
    "retool-agent-eval-worker",
)
CODE_EXECUTOR = "retool-code-executor"
ZONE = "topology.kubernetes.io/zone"
HOSTNAME = "kubernetes.io/hostname"


def render(*extra_values):
    """Render the chart with the install values, the option file, and extra YAML snippets."""
    command = [
        "helm", "template", "retool", "charts/retool",
        "--values", "charts/retool/ci/test-install-values.yaml",
        "--values", OPTION_FILE,
    ]
    with tempfile.TemporaryDirectory() as tmp:
        for index, snippet in enumerate(extra_values):
            path = Path(tmp) / f"extra-{index}.yaml"
            path.write_text(snippet)
            command.extend(("--values", str(path)))
        return subprocess.check_output(command, cwd=ROOT, text=True)


def deployments(output):
    """Map Deployment name to its manifest text."""
    found = {}
    for document in output.split("\n---\n"):
        if "\nkind: Deployment\n" not in f"\n{document}\n":
            continue
        metadata = document.split("\nmetadata:\n", 1)[1]
        name = next(line.split(":", 1)[1].strip() for line in metadata.splitlines() if line.startswith("  name:"))
        found[name] = document
    return found


def block(text, header, indent):
    """Return the lines nested under `header` (deeper than `indent` spaces)."""
    lines = text.splitlines()
    start = lines.index(header) + 1
    nested = []
    for line in lines[start:]:
        if line.strip() and len(line) - len(line.lstrip()) <= indent:
            break
        nested.append(line)
    return nested


def labels(lines):
    return dict(line.strip().split(": ", 1) for line in lines if line.strip())


def selector(deployment):
    return labels(block(deployment, "    matchLabels:", 4))


def constraints(deployment):
    """Parse the pod's topologySpreadConstraints into dicts with a matchLabels entry."""
    if "      topologySpreadConstraints:" not in deployment.splitlines():
        return []
    entries = []
    for line in block(deployment, "      topologySpreadConstraints:", 6):
        if line.startswith("        - "):
            entries.append([])
            line = "          " + line[len("        - "):]
        entries[-1].append(line)
    parsed = []
    for entry in entries:
        text = "\n".join(entry)
        item = {
            line.strip().split(": ", 1)[0]: line.strip().split(": ", 1)[1]
            for line in entry
            if line.startswith("          ") and not line.startswith("           ") and ": " in line
        }
        item["matchLabels"] = labels(block(text, "            matchLabels:", 12)) if "matchLabels:" in text else {}
        parsed.append(item)
    return parsed


class TopologySpreadConstraintsTests(unittest.TestCase):
    def test_default_renders_no_constraints(self):
        output = subprocess.check_output(
            ["helm", "template", "retool", "charts/retool",
             "--values", "charts/retool/ci/test-install-values.yaml",
             "--set", "workflows.enabled=true", "--set", "agents.enabled=true",
             "--set", "codeExecutor.enabled=true"],
            cwd=ROOT, text=True,
        )
        self.assertNotIn("topologySpreadConstraints", output)

    def test_global_list_selects_each_component_own_pods(self):
        rendered = deployments(render())
        for name in SPREAD_DEPLOYMENTS:
            with self.subTest(deployment=name):
                deployment = rendered[name]
                spread = constraints(deployment)
                self.assertEqual([c["topologyKey"] for c in spread], [ZONE, HOSTNAME])
                self.assertEqual([c["whenUnsatisfiable"] for c in spread], ["DoNotSchedule", "ScheduleAnyway"])
                for constraint in spread:
                    self.assertEqual(constraint["matchLabels"], selector(deployment))
        selectors = [tuple(sorted(selector(rendered[name]).items())) for name in SPREAD_DEPLOYMENTS]
        self.assertEqual(len(set(selectors)), len(selectors), "components must not share a selector")

    def test_explicit_label_selector_is_kept(self):
        spread = constraints(deployments(render())[CODE_EXECUTOR])
        self.assertEqual(len(spread), 1)
        self.assertEqual(spread[0]["whenUnsatisfiable"], "ScheduleAnyway")
        self.assertEqual(spread[0]["matchLabels"], {"example.com/spread-group": "code-executor"})

    def test_worker_override_applies_to_that_worker_only(self):
        rendered = deployments(render(
            "agents:\n"
            "  evalWorker:\n"
            "    topologySpreadConstraints:\n"
            "      - maxSkew: 3\n"
            "        topologyKey: kubernetes.io/hostname\n"
            "        whenUnsatisfiable: ScheduleAnyway\n"
        ))
        eval_worker = constraints(rendered["retool-agent-eval-worker"])
        self.assertEqual([(c["topologyKey"], c["maxSkew"]) for c in eval_worker], [(HOSTNAME, "3")])
        self.assertEqual(eval_worker[0]["matchLabels"], selector(rendered["retool-agent-eval-worker"]))
        for name in ("retool-agent-worker", "retool-workflow-worker"):
            with self.subTest(deployment=name):
                self.assertEqual([c["topologyKey"] for c in constraints(rendered[name])], [ZONE, HOSTNAME])

    def test_parent_override_applies_to_its_workers(self):
        rendered = deployments(render(
            "agents:\n"
            "  topologySpreadConstraints:\n"
            "    - maxSkew: 4\n"
            "      topologyKey: topology.kubernetes.io/zone\n"
            "      whenUnsatisfiable: DoNotSchedule\n"
        ))
        for name in ("retool-agent-worker", "retool-agent-eval-worker"):
            with self.subTest(deployment=name):
                self.assertEqual([c["maxSkew"] for c in constraints(rendered[name])], ["4"])
        self.assertEqual([c["maxSkew"] for c in constraints(rendered["retool-workflow-worker"])], ["1", "2"])

    def test_empty_override_disables_constraints(self):
        rendered = deployments(render(
            "agents:\n"
            "  evalWorker:\n"
            "    topologySpreadConstraints: []\n"
            "codeExecutor:\n"
            "  topologySpreadConstraints: []\n"
        ))
        for name in ("retool-agent-eval-worker", CODE_EXECUTOR):
            with self.subTest(deployment=name):
                self.assertEqual(constraints(rendered[name]), [])
        self.assertEqual(len(constraints(rendered["retool-agent-worker"])), 2)


if __name__ == "__main__":
    unittest.main()
