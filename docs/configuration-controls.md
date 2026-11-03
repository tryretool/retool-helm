# Infrastructure controls

- [Database controls](database-controls.md)

Start with the [AWS external-services example](../examples/aws-external-values.yaml)
or the [bundled evaluation example](../examples/bundled-services-values.yaml).
Each guide covers its control's precedence, legacy migration, and prerequisites.

When migrating saved Helm values, use a complete desired values file and
`helm upgrade --reset-values -f my-values.yaml` so removed legacy connection
blocks are not merged back in. Preserve the existing release name, namespace,
database, persistent volumes, and application encryption/JWT secret references.
Selecting a dependency does not migrate data or reverse database migrations.
Take the database backup required by your upgrade procedure.
