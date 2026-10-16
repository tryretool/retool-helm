# retool

Deploy self-hosted Retool on Kubernetes.

Release notes are on the [releases page](https://github.com/tryretool/retool-helm/releases).

## Installing

```bash
helm repo add retool https://charts.retool.com
helm repo update
helm install my-retool retool/retool -f values.yaml
```

`image.tag` has no default and must be set to a specific Retool version. Start from the chart's [values.yaml](values.yaml), which documents every option inline.

## Validating your values

The chart ships a [`values.schema.json`](values.schema.json). Helm checks your values against it on every `helm install`, `helm upgrade`, `helm template` and `helm lint`, so a mistyped value fails before anything reaches the cluster. To check a values file without installing:

```bash
helm lint retool/retool -f values.yaml
```

Editors that understand JSON Schema can use the same file for completion and inline docs. For example, with the VS Code YAML extension, add this to the top of your values file:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/tryretool/retool-helm/main/charts/retool/values.schema.json
```

## Values

This table and `values.schema.json` are generated from the comments in [values.yaml](values.yaml). Sections not listed here yet are still documented by the comments in `values.yaml`, and are not validated by the schema.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| nameOverride | string | `nil` | Override the chart name used in resource names. |
| fullnameOverride | string | `nil` | Override the full name used for resource names. Truncated to 63 characters. |
| config.licenseKey | string | `"EXPIRED-LICENSE-KEY-TRIAL"` | Retool license key. Ignored when `config.licenseKeySecretName` is set. |
| config.licenseKeySecretName | string | `nil` | Name of an existing Secret holding the license key. Use instead of `config.licenseKey`. |
| config.licenseKeySecretKey | string | `license-key` | Key in `config.licenseKeySecretName` holding the license key. |
| config.useInsecureCookies | bool | `false` | Serve the session cookie without the `Secure` flag. Only enable this when Retool is served over plain HTTP. |
| config.dbConnectorTimeout | int | Retool's built-in default (120000) | Query timeout in milliseconds. Sets `DBCONNECTOR_QUERY_TIMEOUT_MS`. |
| config.postgresPoolMaxSize | int | `10` | Maximum Postgres pool connections for the backend. Sets `DBCONNECTOR_POSTGRES_POOL_MAX_SIZE`. |
| config.auth.google.enabled | bool | `true` | Set the `CLIENT_ID` and `CLIENT_SECRET` env vars for Google SSO. Defaults to true for backwards compatibility. |
| config.auth.google.clientId | string | `nil` | Google OAuth client ID. |
| config.auth.google.clientSecret | string | `nil` | Google OAuth client secret. Ignored when `clientSecretSecretName` is set. |
| config.auth.google.clientSecretSecretName | string | `nil` | Name of an existing Secret holding the Google client secret. Use instead of `clientSecret`. |
| config.auth.google.clientSecretSecretKey | string | `google-client-secret` | Key in `clientSecretSecretName` holding the Google client secret. |
| config.encryptionKey | string | `nil` | Key used to encrypt secrets stored in the Retool database. Required on first install unless `config.encryptionKeySecretName` is set. Never change it after install, or stored credentials become unreadable. |
| config.encryptionKeySecretName | string | `nil` | Name of an existing Secret holding the encryption key. Use instead of `config.encryptionKey`. |
| config.encryptionKeySecretKey | string | `encryption-key` | Key in `config.encryptionKeySecretName` holding the encryption key. |
| config.jwtSecret | string | `nil` | Secret used to sign session JWTs. When unset, one is generated on first install and reused on upgrade. Reuse relies on Helm `lookup`, so set it explicitly with tools that render via `helm template`, such as Argo CD. |
| config.jwtSecretSecretName | string | `nil` | Name of an existing Secret holding the JWT secret. Use instead of `config.jwtSecret`. |
| config.jwtSecretSecretKey | string | `jwt-secret` | Key in `config.jwtSecretSecretName` holding the JWT secret. |
| config.postgresql.host | string | `nil` | Hostname of the external Postgres database. |
| config.postgresql.port | int | `nil` | Port of the external Postgres database. |
| config.postgresql.db | string | `nil` | Database name. |
| config.postgresql.database | string | `nil` | Alias for `config.postgresql.db`, used when `db` is unset. |
| config.postgresql.user | string | `nil` | Database user. |
| config.postgresql.password | string | `nil` | Database password. Ignored when `passwordSecretName` is set. |
| config.postgresql.passwordSecretName | string | `nil` | Name of an existing Secret holding the database password. Use instead of `password`. |
| config.postgresql.passwordSecretKey | string | `postgresql-password` | Key in `passwordSecretName` holding the database password. |
| config.postgresql.ssl_enabled | bool | `nil` | Connect to Postgres over SSL. Sets `POSTGRES_SSL_ENABLED`; set it here rather than in `env`. |
| image.repository | string | `"tryretool/backend"` | Retool backend image repository. |
| image.tag | string | `""` | Retool version to deploy, e.g. `3.148.12-stable`. Required: the chart does not pick a version for you. |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy for Retool containers. |
| image.pullSecrets | list | `nil` | Image pull secrets for Retool pods, e.g. `[{name: my-registry}]`. |
| initImage.repository | string | `"busybox"` | Utility image for the initContainers that install the nsjail seccomp profile on the host, used by the code executor and JS executor. Override it to pull from a private mirror, an air-gapped registry, or GCP Marketplace. |
| initImage.tag | string | `"1.37.0"` | Tag of the init image. |
| initImage.digest | string | `""` | Digest to pin a mirrored init image by, e.g. `sha256:...`. |
| env | object | `{}` | Environment variables for Retool containers, as `NAME: value`. A value can also be a map with `value` and/or `valueFrom`. |
| environmentSecrets | list | `[]` | Environment variables populated from Kubernetes Secrets. Each item has `name` and `secretKeyRef` (`name`, `key`). |
| environmentVariables | list | `[]` | Environment variables in Kubernetes `EnvVar` form, for values `env` cannot express such as `valueFrom.fieldRef`. |
| externalSecrets.enabled | bool | `false` | Read env vars from the legacy [kubernetes-external-secrets](https://github.com/godaddy/kubernetes-external-secrets) controller. Deprecated in favour of `externalSecrets.externalSecretsOperator`. |
| externalSecrets.includeConfigSecrets | bool | `false` | Also create the chart's config Secret while external secrets are enabled. It is skipped by default so it can't clobber keys supplied by the external secret. |
| externalSecrets.name | string | `"retool-config"` | Name of the legacy external secret to read env vars from. |
| externalSecrets.secrets | list | `[]` | Additional legacy external secrets to read env vars from. Each item has a `name`. |
| externalSecrets.externalSecretsOperator.enabled | bool | `false` | Read env vars through [External Secrets Operator](https://github.com/external-secrets/external-secrets). |
| externalSecrets.externalSecretsOperator.refreshInterval | string | `"1m"` | How often to re-read secrets from the provider, as a Go duration (`1m`, `1h`). `0` fetches once. |
| externalSecrets.externalSecretsOperator.secretStoreRef.name | string | `"aws-secretsmanager"` | Name of the SecretStore to read from. |
| externalSecrets.externalSecretsOperator.secretStoreRef.kind | string | `"SecretStore"` | Kind of the store. |
| externalSecrets.externalSecretsOperator.secretRef | list | `[]` | ExternalSecrets to create, each also added to pod `envFrom`. Each item needs `name` and `path`; `creationPolicy`, `deletionPolicy` and `optional` are optional. |
| externalSecrets.externalSecretsOperator.useLegacyCR | bool | `true` | Create `kubernetes-client.io/v1` (legacy) ExternalSecret resources instead of `external-secrets.io` ones. |
| externalSecrets.externalSecretsOperator.backendType | string | `"secretsManager"` | Backend type for legacy ExternalSecret resources. |
| postgresql.enabled | bool | `true` | Deploy the bundled Postgres subchart. Not suitable for production. |
| postgresql.ssl_enabled | bool | `false` | Connect to the bundled Postgres over SSL. Sets `POSTGRES_SSL_ENABLED`. |
| postgresql.auth.database | string | `"hammerhead_production"` | Database name. |
| postgresql.auth.username | string | `"postgres"` | Database user. With `postgres`, a random admin password is generated unless `postgresPassword` is set. |
| postgresql.auth.password | string | `"retool"` | Database password. |
| postgresql.service.port | int | `5432` | Postgres service port. |
| postgresql.image.repository | string | `"postgres"` | Postgres image repository. |
| postgresql.image.tag | string | `"13"` | Postgres image tag. |
| postgresql.postgresqlDataDir | string | `"/data/pgdata"` | Postgres data directory. |
| postgresql.primary.persistence.enabled | bool | `true` | Persist Postgres data in a PersistentVolumeClaim. |
| postgresql.primary.persistence.mountPath | string | `"/data/"` | Mount path of the Postgres volume. |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
