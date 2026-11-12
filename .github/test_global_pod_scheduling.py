"""Every rendered pod must inherit the top-level nodeSelector and tolerations.

Renders the same values/option matrix as kubeconform.sh. Intentional exceptions
go in EXEMPT_WORKLOADS or COMPONENT_OVERRIDES.
"""

import subprocess
import sys
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import yaml


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

EXEMPT_WORKLOADS = {
    # Subchart; configured via postgresql.primary.nodeSelector / tolerations.
    f"StatefulSet/{RELEASE}-postgresql",
}

# Component-level placement wins over the top-level values (see
# test_isolated_pool_scheduling.py).
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


def pod_spec(manifest):
    spec = manifest.get("spec") or {}
    if manifest["kind"] == "Pod":
        return spec
    if manifest["kind"] == "CronJob":
        spec = (spec.get("jobTemplate") or {}).get("spec") or {}
    return ((spec.get("template") or {}).get("spec")) or {}


def missing_placement(pod):
    missing = []
    if (pod.get("nodeSelector") or {}).get(SENTINEL_NODE_SELECTOR) is None:
        missing.append("nodeSelector")
    if not any(t.get("key") == SENTINEL_TOLERATION for t in pod.get("tolerations") or []):
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
            for manifest in yaml.safe_load_all(output):
                if not manifest or manifest.get("kind") not in WORKLOAD_KINDS:
                    continue
                workload = f"{manifest['kind']}/{manifest['metadata']['name']}"
                if workload in EXEMPT_WORKLOADS or workload in overridden:
                    continue
                missing = missing_placement(pod_spec(manifest))
                if missing:
                    failures.append(f"{label}: {workload} is missing the top-level {' and '.join(missing)}")

        if failures:
            self.fail(
                "Pods missing the top-level nodeSelector/tolerations:\n  " + "\n  ".join(failures)
            )


if __name__ == "__main__":
    unittest.main()
