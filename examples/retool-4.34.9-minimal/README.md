# Minimal self-hosted Retool 4.34.9-stable with R2 (React Retool)

Plain Kubernetes manifests for a single-namespace deployment of Retool with the R2 stack
enabled. They are intentionally small: one Secret, one Ingress, and one Deployment per
service, with every environment variable inlined where it is used.

| File                    | What it deploys                                                                                  |
| ----------------------- | ------------------------------------------------------------------------------------------------ |
| `secrets.yaml`          | One Secret with every Retool secret: license, JWT, encryption key, DB password, agent-sandbox keys, S3 keys |
| `backend.yaml`          | `SERVICE_TYPE=MAIN_BACKEND,DB_CONNECTOR,DB_SSH_CONNECTOR,RR_GIT_SERVER` + Service `retool:3000`  |
| `jobs-runner.yaml`      | `SERVICE_TYPE=JOBS_RUNNER`                                                                       |
| `code-executor.yaml`    | Code executor (nsjail, seccomp) + the shared `retool-nsjail-seccomp` ConfigMap                   |
| `js-executor.yaml`      | JS executor for R2 serverless functions (nsjail)                                                |
| `agent-sandbox.yaml`    | Agent Sandbox: controller, proxy, sandbox Job template, headless Service, node DaemonSets, RBAC  |
| `agent-worker.yaml`     | R2 agent Temporal worker (`SERVICE_TYPE=R2_AGENT_TEMPORAL_WORKER`)                              |
| `ingress.yaml`          | One ingress for the main backend; every other hop is in-cluster                                  |

## Assumptions

### Database: external Postgres on Amazon RDS

The manifests do not run Postgres. Every Retool process connects to the same RDS instance
through the `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_DB`, `POSTGRES_USER` and
`POSTGRES_SSL_ENABLED` env vars inlined in each Deployment, with the password read from the
`postgresql-password` key of `retool-secrets`. The placeholder host is
`retool-db.abc123.us-east-1.rds.amazonaws.com`.

The Agent Sandbox controller and proxy use the same RDS instance and database as their state
store (`STATE_BACKEND=postgres`), in a separate `agent_executor` schema, so no Redis is
deployed. They connect with `AGENT_SANDBOX_POSTGRES_URL`, a DSN without a password, and read
the password from `PGPASSWORD`. The DSN ends in `?sslmode=no-verify` to match
`POSTGRES_SSL_ENABLED=true` on the backend. The Retool database user must be allowed to
create that schema.

### Temporal: Retool-managed cluster

R2 sandbox orchestration runs on Temporal, but no Temporal cluster is deployed and no
`WORKFLOW_TEMPORAL_*` env vars are set anywhere. The deployment is expected to use a
Retool-managed Temporal namespace, enabled from the Retool admin UI under Settings >
Advanced. Once enabled, the R2 agent worker reads the namespace and its TLS credentials from
the database and connects to `<namespace>.tmprl.cloud`, so that pod needs outbound HTTPS to
`*.tmprl.cloud`. It polls the `r2-agent` task queue.

No Retool Workflows worker is deployed, so Workflows will not execute. Adding one is a copy of
the R2 agent worker Deployment with `SERVICE_TYPE=WORKFLOW_TEMPORAL_WORKER`, no
`WORKER_TEMPORAL_TASKQUEUE`, and health checks on port 3005.

Because Retool 4.34 has no Postgres-backed R2 orchestration, Temporal is required for R2;
the R2 agent worker will not pick up sandbox work until Retool-managed Temporal is enabled.

### Blob storage: external bucket on AWS S3

The RR git server stores every git object and pack in blob storage, and R2 snapshots are
written to the same store. The manifests assume a pre-existing S3 bucket, configured with
`RR_BLOB_STORAGE_PROVIDER=s3`, `RR_DEFAULT_S3_BUCKET` and `RR_DEFAULT_S3_REGION` on the main
backend (which runs the git server in-process) and on the R2 agent worker (which mints the
presigned snapshot URLs). The placeholder bucket is `my-retool-rr-bucket` in `us-east-1`.
Static credentials are read from the `rr-s3-access-key-id` and `rr-s3-secret-access-key`
keys of `retool-secrets`. If the pods carry an IAM role instead (IRSA or an instance
profile), delete those two env vars and the Secret keys and the AWS default credential chain
is used.

Sandbox pods never hold S3 credentials. The R2 agent worker gives each sandbox presigned
PUT/GET URLs, so the sandbox pods only need HTTPS egress to the bucket.

### Topology

- Everything lives in the `retool` namespace and talks over ClusterIP Services. The only
  external entry point is the ingress for `retool.example.com`, which fronts the main
  backend Service on port 3000. `BASE_DOMAIN` on the backend and jobs runner must match
  that host.
- The main backend serves the API, runs the DB connectors and the RR git server in-process,
  and also answers the workflow-backend calls from the R2 agent worker
  (`WORKFLOW_BACKEND_HOST` points back at `retool:3000`), so there is no separate
  workflow-backend Deployment.
- The browser never talks to the agent-sandbox proxy directly. The main backend relays
  `/sandbox/*` WebSocket and Vite traffic to the proxy Service via
  `AGENT_SANDBOX_PROXY_INGRESS_DOMAIN`, so the proxy needs no public hostname, certificate or
  ingress of its own.
- All sandbox egress goes through the proxy. Sandbox pods reach the backend at
  `SANDBOX_BACKEND_URL=http://retool:3000`, which the proxy recognises as `BACKEND_URL` and
  swaps the sandbox's facade token for real credentials.
- The `AGENT_SANDBOX_*` secrets (ES256 keypair, 64-hex encryption key) are shared by the
  main backend, the R2 agent worker, the controller, the proxy and the sandbox pods through
  the same Secret keys.

### Cluster and node requirements

- The code executor and JS executor run nsjail under the attached `nsjail-seccomp.json`
  profile instead of a privileged container. `code-executor.yaml` as written needs
  Kubernetes 1.33+ for `hostUsers: false` and `procMount: Unmasked`; the comment at the top of
  that file lists the privileged fallback for older clusters.
- Agent sandboxes run gVisor (`runsc`, rootless, systrap platform) under the attached
  `gvisor-seccomp.json` profile. Both seccomp profiles are shipped as ConfigMaps and copied
  to `/var/lib/kubelet/seccomp` on every node by init containers or the node-installer
  DaemonSet.
- Sandbox networking uses pasta and needs `/dev/net/tun`. The smarter-device-manager
  DaemonSet registers it with the kubelet as `smarter-devices/net_tun`, which each sandbox
  pod requests in its resource limits.
- Images are pulled from Docker Hub (`tryretool/backend`, `tryretool/code-executor-service`,
  `tryretool/js-executor-service`, `tryretool/agent-sandbox-service`) at tag `4.34.9-stable`;
  no pull secret is configured.

### Not included

NetworkPolicies, AppArmor profiles, PodDisruptionBudgets, autoscaling and telemetry are left
out. The Helm chart in this repository is the reference for each of them.
