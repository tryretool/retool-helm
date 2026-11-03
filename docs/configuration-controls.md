# Database, Temporal, and public route selection

Choose whether this release deploys PostgreSQL and Temporal, then choose who
manages the application's public routes. These controls are available starting
with chart 6.14.0:

```yaml
database:
  bundled: false
  external:
    host: postgres.example.com
    port: 5432
    database: retool
    user: retool
    ssl_enabled: true
    passwordSecretName: retool-database
    passwordSecretKey: password

temporal:
  bundled: false
  external:
    host: temporal-frontend.temporal.svc.cluster.local
    port: 7233
    namespace: workflows

exposure:
  mode: external
```

This replaces the separate dependency and route enablement switches for new
configurations. It does not provision an external database, Temporal cluster,
load balancer, Gateway, DNS, TLS certificate, or Kubernetes Secrets. Workflows,
RR, MCP, and other product features retain their existing controls.

## Select infrastructure

| Control | Behavior |
| --- | --- |
| `database.bundled: true` | Deploy the PostgreSQL dependency and connect Retool to it. Tune that dependency under `postgresql`. Suitable for evaluation. |
| `database.bundled: false` plus `database.external` | Omit PostgreSQL and connect Retool to the supplied database. The sandbox controller/proxy inherit the same connection unless separately configured. |
| `temporal.bundled: true` | Deploy the Temporal dependency and connect Retool to its frontend. Configure persistence, resources, and advanced settings under `retool-temporal-services-helm`. |
| `temporal.bundled: false` plus `temporal.external` | Omit Temporal and connect its consumers to the supplied cluster. |
| `temporal.bundled: false` without an external connection | Omit Temporal. This is appropriate only for configurations that do not need Temporal; enabling Workflows still requires a working Temporal cluster. Existing supported RR Postgres orchestration fallback remains unchanged. |

`database.external` retains the connection field names from `config.postgresql`,
using `database` for the database name. Its host, port, database, and user are
required. Use `passwordSecretName` and optionally `passwordSecretKey` (default:
`postgresql-password`), or an inline `password` for development. The referenced
Secret must be in the release namespace. Deployments that inject credentials
through the chart's external-secrets mode may omit the password fields when
chart-managed configuration secrets are disabled.

`temporal.external` takes host, port, namespace, and the existing TLS options:
`sslEnabled`, `sslCert`, `sslKey`, `sslKeySecretName`, and `sslKeySecretKey`.
Client certificates and keys use the same base64 representation as the legacy
configuration. For mTLS with an existing Secret, set `sslEnabled`, `sslCert`, and
`sslKeySecretName`; `sslKeySecretKey` defaults to `temporal-tls-key`.

Bundled Temporal still needs default and visibility persistence configured;
selecting it does not infer database credentials. See the complete
[bundled evaluation example](../examples/bundled-services-values.yaml).

Bundled dependencies use booleans because Helm evaluates dependency conditions
before rendering templates. The chart mirrors those selections in its connection
helpers, without mutating values or requiring a preprocessing command. This also
works with `helm dependency build` and ordinary Helm/GitOps rendering.

## Select public route ownership

| `exposure.mode` | Resources created for the main application |
| --- | --- |
| `ingress` | Ingress; configure hosts, TLS, class, and annotations under `ingress`. |
| `gateway` | HTTPRoute; configure Gateway parent references, hostnames, annotations, and optional custom rules under `httpRoute`. The chart does not create a Gateway. |
| `external` | Neither Ingress nor HTTPRoute. Configure your existing ALB or another external route owner. |

This selector includes the chart's sandbox-proxy HTTPRoute. The separately
opted-in `rr.appServingLayer.ingress` remains independent because it serves a
different wildcard domain. Existing per-feature path overrides remain available.

MCP routes follow the existing `mcp.routing.mode`. In `direct` mode the selected
Ingress or HTTPRoute includes MCP and OAuth discovery paths. In `backendRelay`
mode the main backend relays requests and only the main catchall route is needed.
For externally managed routing, configure these destinations yourself:

| Public path in direct mode | Service and default port |
| --- | --- |
| `/.well-known/oauth-authorization-server` | `<fullname>-backend-internal:3001` |
| `/.well-known/oauth-protected-resource` | `<fullname>-mcp:4010` |
| `/mcp` and its subpaths | `<fullname>-mcp:4010` |
| Remaining requests | `<fullname>:3000` |

In `backendRelay` mode, the external catchall must match `/mcp` and both discovery
URLs. Retain any additional feature-specific routes, including multiplayer and
browser sandbox access. Installation notes show the selected infrastructure and
MCP destinations. Port overrides in the corresponding service blocks apply.

## Migrate an existing release

When the new controls are omitted, existing selection behavior is preserved,
including configurations that intentionally enable both legacy route types.
The new selectors take precedence over legacy enablement flags. Do not mix old
and new external connection blocks; the chart rejects that ambiguity.

| Existing setting | Replacement |
| --- | --- |
| `postgresql.enabled` | `database.bundled` |
| `config.postgresql` | `database.external`; rename `db` to `database` if used |
| `retool-temporal-services-helm.enabled` | `temporal.bundled` |
| `temporal.enabled: true` plus connection fields | Remove `enabled`; move connection fields to `temporal.external` |
| `workflows.temporal` | Move its connection fields to `temporal.external` and remove its `enabled` field |
| `ingress.enabled` / `httpRoute.enabled` | One `exposure.mode` |

Keep advanced bundled dependency settings under their existing chart keys.
Move all connection fields together, including TLS and secret references.
Switching to the new database selector while still using legacy
`config.postgresql` is supported as an intermediate migration step.

Render a complete desired values file and review changes before upgrading:

```sh
helm dependency build charts/retool
helm lint charts/retool -f my-values.yaml
helm template retool charts/retool -n retool -f my-values.yaml
```

For the upgrade, use the complete desired values file with `--reset-values` so
saved legacy connection blocks are not merged back in:

```sh
helm upgrade retool charts/retool -n retool --reset-values -f my-values.yaml
```

Preserve the existing release name, namespace, database, persistent volumes, and
application encryption/JWT secret references. Changing selectors does not migrate
data or reverse database migrations. Take the database backup required by your
upgrade procedure. This guide does not require an upgrade of the application
images or a change to the database destination.
