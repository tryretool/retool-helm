#!/usr/bin/env python3
"""Renders the chart and checks the env vars each container gets.

1. No container gets the same env var twice. Helm 4's server-side apply rejects the
   upgrade, and client-side apply keeps one copy, not always the same one. Checked for
   every ci values file, alone and with each ci option file, like kubeconform.sh.
2. R2_ORCHESTRATION_BACKEND: the chart sets "postgres" when it can't see a Temporal
   cluster, and a value set in env, environmentVariables or environmentSecrets
   replaces it.

Needs helm, PyYAML and the chart's dependencies (helm dep up charts/retool).

Usage:
  .github/test-env-vars.py
  HELM=/path/to/helm CHART_DIR=/path/to/chart .github/test-env-vars.py
"""

import os
import subprocess
import sys
import tempfile
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import yaml

SCRIPT_DIR = Path(__file__).resolve().parent
CHART_DIR = Path(os.environ.get("CHART_DIR", SCRIPT_DIR.parent / "charts" / "retool")).resolve()
CI_DIR = CHART_DIR / "ci"
HELM = os.environ.get("HELM", "helm")

# R² on, a Retool version with the pg-boss fallback, and no Temporal cluster.
# replicaCount 2 also renders the separate jobs-runner.
R2_BASE_FILES = [CI_DIR / "test-install-values.yaml", CI_DIR / "test-rr-enabled-option.yaml"]
R2_BASE_VALUES = {"image": {"tag": "4.51.0"}, "replicaCount": 2, "workflows": {"enabled": True}}

TEMPORAL = {"enabled": True, "host": "temporal.example.com", "port": 7233, "namespace": "workflows"}
TEMPORAL_SQL = {"host": "postgres.example.com", "port": 5432, "user": "temporal", "password": "temporal"}
TEMPORAL_SUBCHART = {
    "enabled": True,
    "server": {
        "config": {
            "persistence": {
                "default": {"sql": {**TEMPORAL_SQL, "database": "temporal"}},
                "visibility": {"sql": {**TEMPORAL_SQL, "database": "temporal_visibility"}},
            }
        }
    },
}
SECRET_REF = {"name": "retool-r2", "key": "orchestration-backend"}

# (case, values layered on the R² base, the R2_ORCHESTRATION_BACKEND entries each R² container
# must have: a value, or "secretKeyRef" for one read from a secret)
R2_CASES = [
    ("no Temporal cluster", {}, ["postgres"]),
    ("set in env", {"env": {"R2_ORCHESTRATION_BACKEND": "temporal"}}, ["temporal"]),
    (
        "set in env from a secret",
        {"env": {"R2_ORCHESTRATION_BACKEND": {"valueFrom": {"secretKeyRef": SECRET_REF}}}},
        ["secretKeyRef"],
    ),
    (
        "set in environmentVariables",
        {"environmentVariables": [{"name": "R2_ORCHESTRATION_BACKEND", "value": "temporal"}]},
        ["temporal"],
    ),
    (
        "set in environmentSecrets",
        {"environmentSecrets": [{"name": "R2_ORCHESTRATION_BACKEND", "secretKeyRef": SECRET_REF}]},
        ["secretKeyRef"],
    ),
    ("external Temporal in temporal", {"temporal": TEMPORAL}, []),
    ("external Temporal in workflows.temporal", {"workflows": {"temporal": TEMPORAL}}, []),
    ("Temporal subchart", {"retool-temporal-services-helm": TEMPORAL_SUBCHART}, []),
    ("Retool before 4.47.0", {"image": {"tag": "4.46.0"}}, []),
]


def render(files, values=()):
    """Runs helm template with the values files, then the values dicts, in that order."""
    with tempfile.TemporaryDirectory() as tmp:
        args = [HELM, "template", "test", str(CHART_DIR)]
        for path in files:
            args += ["--values", str(path)]
        for i, extra in enumerate(values):
            path = Path(tmp, f"values-{i}.yaml")
            path.write_text(yaml.safe_dump(extra))
            args += ["--values", str(path)]
        result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip())
    return [doc for doc in yaml.safe_load_all(result.stdout) if isinstance(doc, dict) and "kind" in doc]


def pod_specs(node):
    if isinstance(node, dict):
        if "containers" in node:
            yield node
            return
        for value in node.values():
            yield from pod_specs(value)
    elif isinstance(node, list):
        for item in node:
            yield from pod_specs(item)


def containers(docs):
    """Yields (label, container) for every container and init container in every workload."""
    for doc in docs:
        for spec in pod_specs(doc):
            for container in (spec.get("initContainers") or []) + (spec.get("containers") or []):
                yield f"{doc['kind']}/{doc['metadata']['name']}/{container['name']}", container


def env_names(container):
    return [entry["name"] for entry in container.get("env") or []]


def duplicate_env_problems(docs):
    problems = []
    for label, container in containers(docs):
        duplicates = sorted(name for name, count in Counter(env_names(container)).items() if count > 1)
        if duplicates:
            problems.append(f"{label} sets {', '.join(duplicates)} more than once")
    return problems


def r2_backend_entries(container):
    return [
        next(iter(entry["valueFrom"])) if "valueFrom" in entry else entry.get("value")
        for entry in container.get("env") or []
        if entry["name"] == "R2_ORCHESTRATION_BACKEND"
    ]


def check_ci_renders():
    values_files = sorted(CI_DIR.rglob("*values.yaml"))
    option_files = sorted(CI_DIR.rglob("*option.yaml"))
    combos = [[v] for v in values_files] + [[v, o] for v in values_files for o in option_files]

    def problems_for(files):
        try:
            return duplicate_env_problems(render(files))
        except RuntimeError as err:
            return [f"helm template failed: {err}"]

    with ThreadPoolExecutor() as pool:
        results = list(pool.map(problems_for, combos))
    failed = [(files, problems) for files, problems in zip(combos, results) if problems]
    status = "FAIL" if failed else "PASS"
    print(f"  {status}: no container gets the same env var twice in {len(combos)} ci renders")
    for files, problems in failed:
        print(f"    {' + '.join(str(f.relative_to(CI_DIR)) for f in files)}:")
        for problem in problems:
            print(f"      {problem}")
    return len(failed)


def check_r2_case(case, values, expected):
    docs = render(R2_BASE_FILES, [R2_BASE_VALUES, values])
    # Containers that get the chart's R² env vars (retool.agentSandbox.backendEnvVars).
    r2_containers = [
        (label, container) for label, container in containers(docs) if "RR_AGENT_PUBSUB_BACKEND" in env_names(container)
    ]
    problems = duplicate_env_problems(docs)
    if not r2_containers:
        problems.append("no container got the R² env vars")
    for label, container in r2_containers:
        entries = r2_backend_entries(container)
        if entries != expected:
            problems.append(f"{label} has {entries}")
    status = "FAIL" if problems else "PASS"
    print(f"  {status}: {case}: {expected or 'not set'} in {len(r2_containers)} R² containers")
    for problem in problems:
        print(f"      {problem}")
    return 1 if problems else 0


def main():
    print(f"Chart: {CHART_DIR}")
    print("Duplicate env vars:")
    failures = check_ci_renders()
    print("R2_ORCHESTRATION_BACKEND:")
    for case, values, expected in R2_CASES:
        failures += check_r2_case(case, values, expected)
    if failures:
        print(f"{failures} check(s) failed")
        sys.exit(1)
    print("All checks passed")


if __name__ == "__main__":
    main()
