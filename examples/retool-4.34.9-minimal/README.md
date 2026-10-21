# Minimal self-hosted Retool 4.34.9-stable with R2 (React Retool)

Plain Kubernetes manifests for a single-namespace deployment with the R2 stack enabled.
Postgres is external (RDS or similar) and Temporal is Retool-managed.

| File                    | What it deploys                                                                                  |
| ----------------------- | ------------------------------------------------------------------------------------------------ |
| `secrets.yaml`          | One Secret with every Retool secret: license, JWT, encryption key, DB password, agent-sandbox keys, S3 keys |
| `backend.yaml`          | `SERVICE_TYPE=MAIN_BACKEND,DB_CONNECTOR,DB_SSH_CONNECTOR,RR_GIT_SERVER` + Service `retool:3000`  |
| `jobs-runner.yaml`      | `SERVICE_TYPE=JOBS_RUNNER`                                                                       |
| `workflows-worker.yaml` | `SERVICE_TYPE=WORKFLOW_TEMPORAL_WORKER`                                                          |
| `code-executor.yaml`    | Code executor (nsjail, seccomp) + the shared `retool-nsjail-seccomp` ConfigMap                   |
| `r2.yaml`               | JS executor, agent-sandbox controller / proxy / Job template / DaemonSets, R2 agent worker      |
| `ingress.yaml`          | One ingress for the main backend; every other hop is in-cluster                                  |

## Before applying

1. Create the namespace: `kubectl create namespace retool`.
2. Fill in `secrets.yaml` (generation commands are in the file).
3. Replace the placeholders that appear in several files: `retool.example.com`, the
   `POSTGRES_*` values and the `AGENT_SANDBOX_POSTGRES_URL` DSN, `my-retool-rr-bucket`
   and `us-east-1`.
4. The Retool Postgres user must be allowed to create the `agent_executor` schema.
5. Nodes need gVisor-compatible kernels (sandboxes run `runsc` rootless with the systrap
   platform) and, for `code-executor.yaml` as written, Kubernetes 1.33+ (`hostUsers: false`,
   `procMount: Unmasked`). The comment at the top of that file lists the privileged fallback.
6. Enable Retool-managed Temporal in the Retool UI (Settings > Advanced) after the backend is
   up. The workers read the connection from the database, so no `WORKFLOW_TEMPORAL_*` env vars
   are set. Allow egress from the worker pods to `*.tmprl.cloud`.

## Apply order

```sh
kubectl apply -f secrets.yaml
kubectl apply -f backend.yaml -f jobs-runner.yaml -f code-executor.yaml
kubectl apply -f r2.yaml -f workflows-worker.yaml
kubectl apply -f ingress.yaml
```

## Deliberate omissions

- No NetworkPolicies. The Helm chart's `rr.agentSandbox.networkPolicy` block is the reference
  if you need to lock down sandbox egress at the CNI level; the proxy still enforces its own
  CIDR blocklist.
- No AppArmor profiles (executors run `unconfined`), no PodDisruptionBudgets, no autoscaling,
  no telemetry.
- No separate workflow-backend Deployment. `WORKFLOW_BACKEND_HOST` on the workers points at
  the main backend, which serves the same routes. Split it out (Helm's
  `deployment_workflows.yaml`) once workflow load should not share the API pods.
