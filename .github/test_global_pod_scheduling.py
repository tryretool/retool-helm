"""Every pod the chart renders must inherit the top-level nodeSelector and tolerations.

Renders each CI values file on its own and combined with each *option.yaml (the
same matrix as kubeconform.sh), with a sentinel top-level nodeSelector and
toleration, and fails if any workload's pod spec is missing either. This catches
new templates that forget the scheduling block, as happened for code-executor
(#169) and telemetry (#423).

If a new workload intentionally does not take the global placement, add it to
EXEMPT_SOURCES with the reason. If a CI option file deliberately overrides a
component's placement, add the workload to COMPONENT_OVERRIDES for that file.
"""

import re
import subprocess
import sys
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHART = ROOT / "charts" / "retool"
sys.dont_write_bytecode = True

RELEASE = "placement"
SENTINEL_NODE_SELECTOR = "sentinel.retool.com/global-node-selector"
SENTINEL_TOLERATION = "sentinel.retool.com/global-toleration"
GLOBAL_PLACEMENT = (
    f'nodeSelector={{"{SENTINEL_NODE_SELECTOR}": "placement-check"}}',
    f'tolerations=[{{"key": "{SENTINEL_TOLERATION}", "operator": "Exists", "effect": "NoSchedule"}}]',
)

WORKLOAD_KINDS = {"Deployment", "DaemonSet", "StatefulSet", "ReplicaSet", "Job", "CronJob", "Pod"}

# Templates whose pods are not expected to take the top-level values.
EXEMPT_SOURCES = {
    # Bitnami subchart: it only sees values under `postgresql:`, so users set
    # postgresql.primary.nodeSelector / tolerations themselves.
    "retool/charts/postgresql/templates/primary/statefulset.yaml",
}

# Option files that pin a component somewhere else on purpose. The component
# value wins over the top-level one, which test_isolated_pool_scheduling.py
# covers.
COMPONENT_OVERRIDES = {
    "test-apparmor-nsjail-isolated-pool-option.yaml": {
        f"Deployment/{RELEASE}-retool-js-executor",
        f"DaemonSet/{RELEASE}-retool-apparmor-nsjail",
    },
}


def combinations():
    values = sorted(CHART.glob("ci/**/*values.yaml"))
    options = sorted(CHART.glob("ci/**/*option.yaml"))
    for values_file in values:
        yield (values_file,)
        for option_file in options:
            yield (values_file, option_file)


def render(files):
    command = ["helm", "template", RELEASE, str(CHART)]
    for f in files:
        command.extend(("--values", str(f)))
    for setting in GLOBAL_PLACEMENT:
        command.extend(("--set-json", setting))
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    return result.returncode, result.stdout, result.stderr


def documents(output):
    for document in output.split("\n---\n"):
        kind = re.search(r"^kind: (\S+)$", document, re.M)
        if not kind or kind.group(1) not in WORKLOAD_KINDS:
            continue
        source = re.search(r"^# Source: (\S+)$", document, re.M)
        name = re.search(r"^metadata:\n(?:[ ]{2,}.*\n|\s*\n)*?[ ]{2}name: (\S+)$", document, re.M)
        yield (
            source.group(1) if source else "<unknown>",
            f"{kind.group(1)}/{name.group(1).strip(chr(34)) if name else '<unknown>'}",
            document,
        )


def pod_spec_field(document, field):
    """The text of `field` in the pod spec, or None if the pod spec does not set it.

    The pod spec is found by the indentation of its `containers:` key, so a
    matching string elsewhere (an env var, an annotation) is never mistaken for
    the pod's own nodeSelector or tolerations.
    """
    lines = document.splitlines()
    indent = None
    for line in lines:
        match = re.match(r"^( *)containers:\s*$", line)
        if match:
            indent = match.group(1)
            break
    if indent is None:
        return None
    for i, line in enumerate(lines):
        if line.startswith(f"{indent}{field}:"):
            block = [line]
            for following in lines[i + 1:]:
                if following.strip() and not following.startswith(indent + " ") and not following.startswith(indent + "- "):
                    break
                block.append(following)
            return "\n".join(block)
    return None


def missing_placement(document):
    missing = []
    node_selector = pod_spec_field(document, "nodeSelector")
    if node_selector is None or SENTINEL_NODE_SELECTOR not in node_selector:
        missing.append("nodeSelector")
    tolerations = pod_spec_field(document, "tolerations")
    if tolerations is None or SENTINEL_TOLERATION not in tolerations:
        missing.append("tolerations")
    return missing


class GlobalPodSchedulingTests(unittest.TestCase):
    def test_every_pod_inherits_global_placement(self):
        cases = list(combinations())
        self.assertTrue(cases, "no CI values files found")
        with ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(render, cases))

        failures = []
        for files, (returncode, output, stderr) in zip(cases, results):
            label = " + ".join(str(f.relative_to(CHART)) for f in files)
            if returncode != 0:
                failures.append(f"{label}: helm template failed:\n{stderr.strip()}")
                continue
            overridden = set().union(*(COMPONENT_OVERRIDES.get(f.name, set()) for f in files))
            for source, workload, document in documents(output):
                if source in EXEMPT_SOURCES or workload in overridden:
                    continue
                missing = missing_placement(document)
                if missing:
                    failures.append(f"{label}: {workload} ({source}) is missing the top-level {' and '.join(missing)}")

        if failures:
            self.fail(
                "Every pod should inherit the top-level nodeSelector and tolerations "
                "(see the docstring of this file for exemptions):\n  " + "\n  ".join(failures)
            )


if __name__ == "__main__":
    unittest.main()
