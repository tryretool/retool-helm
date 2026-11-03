# Temporal controls

Starting with chart 6.15.0, select Temporal and its connection settings under one
`temporal` block:

```yaml
temporal:
  bundled: false
  external:
    host: temporal-frontend.temporal.svc.cluster.local
    port: 7233
    namespace: workflows
```

`bundled: true` deploys the Temporal dependency and connects its consumers to
the bundled frontend. Continue configuring persistence and resources under
`retool-temporal-services-helm`. Default and visibility persistence still need
database names and credentials, even when sharing the Retool PostgreSQL instance.
The [bundled evaluation example](../examples/bundled-services-values.yaml)
shows those settings.

`bundled: false` omits the dependency. Supply `external` to connect to an existing
cluster; host, port, and namespace are required. This control does not create an
external cluster. With no effective external connection, Temporal is unconfigured:
Workflows still require a working Temporal cluster. Existing supported RR Postgres
orchestration fallback remains unchanged.

External connections retain the existing TLS options: `sslEnabled`, `sslCert`,
`sslKey`, `sslKeySecretName`, and `sslKeySecretKey`. Certificates and keys use the
same base64 representation as the legacy configuration. For mTLS using an existing
Secret in the release namespace, set `sslEnabled`, `sslCert`, and
`sslKeySecretName`; `sslKeySecretKey` defaults to `temporal-tls-key`. This reference
now works without supplying a redundant inline private key.

Helm evaluates dependency conditions before rendering templates, so `bundled`
is a boolean. It controls both dependency creation and connection consumers.
Installation notes show whether Temporal is bundled, external, or unconfigured.

To migrate, replace `retool-temporal-services-helm.enabled` with
`temporal.bundled`. Move connection fields from legacy `temporal` or
`workflows.temporal` into `temporal.external`, removing their `enabled` field.
Keep advanced bundled chart settings under `retool-temporal-services-helm`.

Omitting the new controls preserves legacy behavior. The new bundled selector
takes precedence over the old dependency enabled flag. The chart rejects mixing
the new external block with old connection fields, or selecting both bundled and
external Temporal. Moving only the bundled selector while retaining a legacy
external connection is supported as an intermediate migration step.

See the [AWS external-services example](../examples/aws-external-values.yaml)
and [shared upgrade guidance](configuration-controls.md).
