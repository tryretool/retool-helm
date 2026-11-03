# Public route ownership

Starting with chart 6.16.0, select who manages the main application's routes:

```yaml
exposure:
  mode: external
```

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

To migrate, replace `ingress.enabled` and `httpRoute.enabled` with one
`exposure.mode`. Keep hosts, TLS, parent references, annotations, and custom
rules under their existing blocks. The new mode takes precedence over the
legacy enablement flags. When omitted, legacy behavior is preserved, including
configurations that intentionally create both resource types.

See the [AWS external-services example](../examples/aws-external-values.yaml),
[bundled evaluation example](../examples/bundled-services-values.yaml), and
[shared upgrade guidance](configuration-controls.md).
