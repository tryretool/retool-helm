<p align="center">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://docs.retool.com/brand/icons/logo-light.svg">
      <img alt="Retool Logo" height="100" src="https://docs.retool.com/brand/icons/logo-dark.svg">
    </picture>
</p>
<h3 align="center">The best way to build internal software</h3>




# Deploying Retool on Helm

Find deployment instructions in the [official Helm deployment guide](https://docs.retool.com/docs/deploy-with-helm) hosted on docs.retool.com.

This is the repository for the official Retool Helm chart. For release notes, see the [releases section](https://github.com/tryretool/retool-helm/releases) of this repo.

For any inquiries regarding deploying Retool on Helm, please feel free to reach out to us at support@retool.com or search our [Community Forums](https://community.retool.com/) and post your question there.

## MCP public routing

### One public origin

For a single-host installation, set `env.BASE_DOMAIN` to the public Retool
origin, including `https://`, and serve that host through the chart-managed
Ingress or HTTPRoute (or your external ingress). The chart passes this value to
the backend and MCP process. The server uses it when a request reaches an
internal Service host; it keeps a valid public request host for custom Space
domains. `RETOOL_BACKEND_URL` remains an internal destination and is never a
client-facing URL.

The chart derives `OAUTH_MAIN_DOMAIN` from `BASE_DOMAIN` when its value is
available at render time. A secret-backed `BASE_DOMAIN` is passed through but
cannot be checked against route hosts during rendering. Explicit
`mcp.config.oauthMainDomain`, `mcp.config.mcpServiceExternalUrl` (or its legacy
`retoolUrl` alias), and `mcp.environmentVariables` take precedence. An explicit
`MCP_SERVICE_EXTERNAL_URL` pins the advertised origin, including on custom
Space domains; omit it when those domains should be advertised per request.
The chart copies an explicit MCP external URL to the backend unless the
backend has its own explicit value. Keep explicit values equal across both
workloads so discovery and upload links agree.

If your proxy changes the Host or scheme before forwarding, set
`env.MCP_TRUSTED_PROXY_CIDRS` to the comma-separated CIDRs of the immediate
trusted proxy peers. The chart passes it to the MCP process too. Only requests
from those peers may use `X-Forwarded-Host` and `X-Forwarded-Proto` for MCP
advertised URLs. Include every relevant proxy peer range when custom Space
domains reach Retool through an internal Host. Otherwise the server falls back
to `BASE_DOMAIN` for an internal Host.

When the chart knows the Ingress host or HTTPRoute hostnames, MCP rendering
checks that `BASE_DOMAIN` and any explicit MCP external URL match a managed
host. Multiple hosts are allowed for custom domains. With externally managed
ingress, disable the chart-managed route and provide equivalent public paths.

With `mcp.enabled: true`, `mcp.routing.mode` defaults to `backendRelay` for Retool 4.0.7 and later. The normal `/` Ingress or HTTPRoute sends all public paths to the main Retool Service, and its backend relays `/mcp` to the MCP Service using the chart-provided `MCP_SERVICE_INGRESS_DOMAIN`. For Retool before 4.0.7, set `mcp.routing.mode: direct`; those versions need dedicated MCP and OAuth discovery routes. Choose the mode explicitly for your server version, including builds with PR or custom image tags.

| Mode | Public path | Service |
| --- | --- | --- |
| `backendRelay` | All paths, including `/mcp` and `/.well-known/*` | Main Retool Service, port 3000 |
| `direct` | `/.well-known/oauth-authorization-server` (exact) | Backend API Service, port 3001 |
| `direct` | `/.well-known/oauth-protected-resource` (exact) and `/mcp` (prefix) | MCP Service, port 4010 |
| `direct` | `/` (prefix) | Main Retool Service, port 3000 |

These are also the mappings to use when ingress is managed outside the chart. In `direct` mode, place the dedicated paths before the main `/` path. The service names are `<fullname>`, `<fullname>-backend-internal`, and `<fullname>-mcp`, where `<fullname>` is the chart release's full name.

When upgrading existing values files, remove `mcp.ingress.enabled: true` and `mcp.httpRoute.enabled: true` to use `backendRelay`, or set `mcp.routing.mode: direct` for an older server. An explicit legacy `true` setting conflicts with `backendRelay` and stops chart rendering with migration guidance. Both flags now default to `null`, which follows the mode. An explicit `false` keeps the corresponding chart-managed direct routes off when you supply them externally.

## MCP public URL smoke test

When MCP is enabled, set `mcp.test.publicUrl` to the public Retool origin to add an optional `helm test` Job:

```yaml
mcp:
  enabled: true
  test:
    publicUrl: https://retool.example.com
    image: python:3.12-alpine # Override with a Python 3 image from your registry if needed.
```

The Job pod must be able to resolve and reach that URL through the public ingress, and trust its TLS certificate. This may require egress access or hairpin routing from the cluster. The URL must be an HTTP(S) origin without a path. The image must provide Python 3 and its standard library; the Job uses the chart's `image.pullSecrets` for private registries. With an empty `publicUrl`, or when `mcp.enabled` is false, the hook is omitted.

After installing or upgrading the release, run:

```sh
helm test <release> --namespace <namespace>
```

The test sends unauthenticated requests to `/mcp`, the advertised `resource_metadata` URL, `/.well-known/oauth-protected-resource`, and `/.well-known/oauth-authorization-server`. It expects a 401 Bearer challenge and valid, consistent JSON discovery metadata. A failed Job is retained: find it with `kubectl get jobs --namespace <namespace>`, then read `kubectl logs job/<job-name> --namespace <namespace>`. A successful Job is removed. Some Helm versions, including 4.2.0, try to read Job logs from a Pod with the Job's name when `--logs` is used, so that flag can report an error even after the test succeeds. Each failure names the URL, expected result, and observed status or missing field. Redirects, HTML login pages, malformed JSON, and connection errors fail the test. It does not authenticate a user or exercise MCP tools.
