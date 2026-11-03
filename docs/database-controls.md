# Database controls

Starting with chart 6.14.0, select PostgreSQL and its connection settings under
one `database` block:

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
```

`bundled: true` deploys the PostgreSQL dependency and connects Retool to it.
Continue to configure its storage, resources, and authentication under
`postgresql`. Bundled PostgreSQL is suitable for evaluation; use an external
database for production. This selector does not create an external database.

`bundled: false` omits the dependency and connects Retool to `external`. The
sandbox controller/proxy inherit this connection unless separately configured.
The host, port, database, and user are required. Use `passwordSecretName` and
optionally `passwordSecretKey` (default: `postgresql-password`), or an inline
`password` for development. The Secret must be in the release namespace.
Deployments that inject credentials through the chart's external-secrets mode
may omit password fields when chart-managed configuration secrets are disabled.

Helm evaluates dependency conditions before rendering templates, so `bundled`
is a boolean. It selects the actual dependency and the connection consumers
without a preprocessing command or value mutation. Installation notes show
whether the effective database is bundled or external.

To migrate, replace `postgresql.enabled` with `database.bundled` and move
`config.postgresql` into `database.external`. Rename `db` to `database` if used;
other connection field names stay the same. Keep advanced bundled settings under
`postgresql`. Move TLS and secret references with the connection fields.

Omitting the new controls preserves legacy behavior. `database.bundled` takes
precedence over the legacy enabled flag. The chart rejects mixing
`database.external` with `config.postgresql`, and rejects an external connection
when the bundled database is selected. Migrating the selector first while
retaining legacy `config.postgresql` is supported as an intermediate step.

See the [AWS external-services example](../examples/aws-external-values.yaml),
the [bundled evaluation example](../examples/bundled-services-values.yaml), and
the [shared upgrade guidance](configuration-controls.md).
