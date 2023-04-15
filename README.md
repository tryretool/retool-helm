# retool-helm

[![Artifact HUB](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/retool)](https://artifacthub.io/packages/search?repo=retool)

This repository contains the official **Helm 3** chart for installing and configuring
Retool on Kubernetes. For full documentation on all the ways you can deploy
Retool on your own infrastructure, please see the [Setup
Guide](https://docs.retool.com/docs/setup-instructions).

## Prerequisites

- This chart requires **Helm 3.0**.
- A PostgreSQL database.
  - Persistent volumes are not reliable - we strongly recommend that a long-term
    installation of Retool host the database on an externally managed database (for example, AWS RDS).

## Usage

1.  Add the Retool Helm repository:

        $ helm repo add retool https://charts.retool.com
        "retool" has been added to your repositories

2.  Ensure you have access to the `retool` chart:

        $ helm search repo retool/retool
        NAME         	CHART VERSION	APP VERSION	DESCRIPTION
        retool/retool	4.0.0        	2.66.2     	A Helm chart for Kubernetes

3.  Run this command `git clone https://github.com/tryretool/retool-helm.git`

4.  Modify the `values.yaml` file:

- Set values for `config.encryptionKey` and `config.jwtSecret`. They should each be a different long, random string that you keep private. See our docs on [Environment Variables](https://docs.retool.com/docs/environment-variables) for more information on how they are used.

- Set `image.tag` with the version of Retool you want to install (i.e. a version in the format X.Y.Z). See our guide on [Retool Release Versions](https://docs.retool.com/docs/updating-retool-on-premise#retool-release-versions) to see our most recent version.

- Set `config.licenseKey` with your license key.

- To force Retool to send the auth cookies over HTTP, set `config.useInsecureCookies` to `true`. Leave the default value of `false` if you will use https to connect to the instance.

5.  Now you're all ready to install Retool:

        $ helm install my-retool retool/retool -f values.yaml

## Additional Configuration

### Externalize database

Modify `values.yaml`:

- Disable the included postgresql chart by setting `postgresql.enabled` to `false`. Then specify your external database through the `config.postgresql.\*` properties at the top of the file.

### gRPC

1.  Create a `configMap` of the directory which contains your `proto` files.

        $ kubectl create configmap protos --from-file=<protos-path>

2.  Modify `values.yaml`:

        extraVolumeMounts:
          - name: protos
          mountPath: /retool_backend/protos
          readOnly: true

        extraVolumes:
          - name: protos
          configMap:
            name: protos

        env:
          PROTO_DIRECTORY_PATH=/retool_backend/protos

### Ingress

Modify `values.yaml`:

- Uncomment `ingress.hosts` and change `ingress.hosts.host` to be the hostname where you will access Retool.
- If you are implementing TLS for your Retool instance, uncomment `ingress.tls` and:
  - Specify the name of the SSL certificate to use as the value of `ingress.tls.secretName`.
  - Specify an array containing the hostname where you will access Retool (the same value you configured for `ingress.hosts.host`).

GKE-specific configurations:

- Specify `/*` as the value of `ingress.hosts.paths.path`.
- Comment out `ingress.tls.servicePort` as it is not required.

## Parameters

### Retool Configuration Parameters

##### These parameters are used to configure your Retool instance

| Name                              | Description                                                                                                                                                                        | Value                       |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------- |
| `config.licenseKey`               | The raw Retool license key                                                                                                                                                         | `EXPIRED-LICENSE-KEY-TRIAL` |
| `config.useInsecureCookies`       | Whether to send authentication requests using insecure cookies. Set COOKIE_INSECURE to true if your Retool deployment uses a non-HTTPS URL or IP address                           | `false`                     |
| `config.auth.google.clientId`     | A Google OAuth client app ID for OAuth-based authentication with Google (e.g., Google SSO or using a Google Sheets resource).                                                      | `nil`                       |
| `config.auth.google.clientSecret` | A Google OAuth client app secret for OAuth-based authentication with Google (e.g., Google SSO or using a Google Sheets resource).                                                  | `nil`                       |
| `config.auth.google.domain`       | Restrict users from logging in unless they use SSO for the specified domain. This value must match your email domain. Specify comma-separated values for multiple domains.         | `nil`                       |
| `config.encryptionKey`            | Encrypts data stored in the PostgreSQL database (e.g., database credentials, SSH keys, etc). Make sure to keep track of this key in a location outside of your Retool instance(s). | `nil`                       |
| `config.jwtSecret`                | Secret token to sign requests for authentication with Retool's backend API server. If changed, all active user login sessions are invalidated.                                     | `nil`                       |
| `config.postgresql`               | The Postgres parameters to use for Retools internal Database                                                                                                                       | `{}`                        |

### Image Parameters

##### These parameters specify your image and image configuration

| Name               | Description                                                                                                | Value               |
| ------------------ | ---------------------------------------------------------------------------------------------------------- | ------------------- |
| `image.repository` | Retool image repository. You need to pick a specific tag here, this chart will not make a decision for you | `tryretool/backend` |
| `image.tag`        | Retool image tag                                                                                           | `""`                |
| `image.pullPolicy` | Retool image pull policy                                                                                   | `IfNotPresent`      |

### Environment Variable Parameters

##### These parameters are used to pass envrionment variables to your containers

| Name                   | Description                                                                                                         | Value |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------- | ----- |
| `env`                  | Specify envrionment variables to be passed to the container when it is started. These values should be key:value    | `{}`  |
| `environmentSecrets`   | Optionally specify additional environment variables to be populated from Kubernetes secrets.                        | `[]`  |
| `environmentVariables` | Optionally specify environmental variables. Useful for variables that are not key-value, as env: {} above requires. | `[]`  |

### Other Parameters

| Name                                                  | Description                                                                                                                                                                                                                                | Value                    |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------ |
| `commandline.args`                                    | Specify command line arguments to be passed to a container when it is started.                                                                                                                                                             | `[]`                     |
| `extraConfigMapMounts`                                | An array of objects, where each object specifies the ConfigMap to mount and the corresponding volume mount path                                                                                                                            | `[]`                     |
| `initContainers`                                      | Adds additional init containers to the Retool pods                                                                                                                                                                                         | `{}`                     |
| `extraManifests`                                      | Adds additional Kubernetes objects to the cluster                                                                                                                                                                                          | `[]`                     |
| `priorityClassName`                                   | Specify the name of a Kubernetes PriorityClass that will be assigned to the Pods created by the chart.                                                                                                                                     | `""`                     |
| `tolerations`                                         | Tolerations for pod assignment                                                                                                                                                                                                             | `[]`                     |
| `nodeSelector`                                        | Node labels for pod assignment                                                                                                                                                                                                             | `{}`                     |
| `podAnnotations`                                      | Common annotations for all pods (backend and job runner).                                                                                                                                                                                  | `{}`                     |
| `replicaCount`                                        | The number of Retool backend replicas                                                                                                                                                                                                      | `2`                      |
| `revisionHistoryLimit`                                | Specifies the maximum number of old ReplicaSets to retain for a Deployment.                                                                                                                                                                | `3`                      |
| `extraContainers`                                     | Specify list of additional containers for the Retool pods                                                                                                                                                                                  | `[]`                     |
| `extraVolumeMounts`                                   | Specify list of additional volumeMounts for the Retool pods                                                                                                                                                                                | `[]`                     |
| `extraVolumes`                                        | Specify list of additional volumes for the Retool pods                                                                                                                                                                                     | `[]`                     |
| `podLabels`                                           | Common labels for all pods (backend and job runner) for pod assignment                                                                                                                                                                     | `{}`                     |
| `files`                                               | Configuration parameter that allows you to specify additional files to include in the chart's packaged release.                                                                                                                            | `{}`                     |
| `deployment.annotations`                              | Used to define annotations for the Kubernetes Deployment resource created by the chart.                                                                                                                                                    | `{}`                     |
| `backend.annotations`                                 | Annotations for Retool backend pods                                                                                                                                                                                                        | `{}`                     |
| `backend.labels`                                      | Labels for Retool backend pods                                                                                                                                                                                                             | `{}`                     |
| `jobRunner.annotations`                               | Annotations for Retool job runner pods                                                                                                                                                                                                     | `{}`                     |
| `jobRunner.labels`                                    | Labels for Retool job runner pods                                                                                                                                                                                                          | `{}`                     |
| `securityGroupPolicy.enabled`                         | Specifies whether to enable Security Groups for pods or not. If set to true, pods created by the chart will be assigned to a security group. If set to false, pods will not be assigned to a security group.                               | `false`                  |
| `securityGroupPolicy.groupIds`                        | Specifies a list of security group IDs to assign to pods created by the chart. Security groups are used to control inbound and outbound traffic to and from pods.                                                                          | `[]`                     |
| `persistentVolumeClaim.enabled`                       | Specifies whether to create a PVC resource or not. If set to true, the PVC resource is created. If set to false, the PVC resource is not created.                                                                                          | `false`                  |
| `persistentVolumeClaim.existingClaim`                 | Specifies whether to use an existing PVC or create a new one. If set to true, the chart will use an existing PVC. If set to false, the chart will create a new PVC.                                                                        | `false`                  |
| `persistentVolumeClaim.annotations`                   | Specifies a set of annotations to apply to the PVC resource. Annotations are used to add metadata to the resource that can be used by tools or scripts that interact with the resource.                                                    | `{}`                     |
| `persistentVolumeClaim.accessModes`                   | Specifies the access modes to use for the PVC resource. Access modes determine how the PVC can be accessed by pods, and can be set to ReadWriteOnce, ReadWriteMany, or ReadOnlyMany.                                                       | `["ReadWriteOnce"]`      |
| `persistentVolumeClaim.size`                          | Specifies the size of the PVC in bytes or with a unit suffix (e.g. 1Gi). This determines how much storage is allocated for the PVC.                                                                                                        | `15Gi`                   |
| `securityContext.enabled`                             | Specifies whether to enable the security context for the containers or not. If set to true, the security context is enabled for the containers. If set to false, the security context is disabled.                                         | `false`                  |
| `securityContext.allowPrivilegeEscalation`            | Specifies whether to allow privilege escalation for the containers or not. If set to true, the containers can escalate privileges. If set to false, the containers cannot escalate privileges.                                             | `false`                  |
| `securityContext.runAsUser`                           | Specifies the user ID to run the containers as. This is useful for setting a non-root user ID to run the containers for security reasons.                                                                                                  | `1000`                   |
| `securityContext.fsGroup`                             | Specifies the group ID that owns the files created by the containers. This is useful for setting a non-root group ID for security reasons.                                                                                                 | `2000`                   |
| `serviceAccount.create`                               | Specifies whether to create a service account or not. If set to true, the service account is created. If set to false, the service account is not created.                                                                                 | `true`                   |
| `serviceAccount.name`                                 | The name of the service account to use. If not set and create is true, a name is generated using the fullname template. If set and create is false, the service account must be existing.                                                  | `nil`                    |
| `serviceAccount.annotations`                          | Specifies a map of annotations to attach to the service account. Annotations are used to add metadata to the resource that can be used by tools or scripts that interact with the resource.                                                | `{}`                     |
| `externalSecrets.enabled`                             | Specifies whether external secrets are enabled or not. If set to true, the chart will use external secrets to manage sensitive data.                                                                                                       | `false`                  |
| `externalSecrets.name`                                | Specifies the name of the external secret resource to use. This resource will contain the mappings between environment variables and secret keys.                                                                                          | `retool-config`          |
| `externalSecrets.externalSecretsOperator.enabled`     | Specifies whether to use the External Secrets Operator to manage external secrets. This operator provides a more modern and flexible way to manage external secrets compared to the legacy method.                                         | `false`                  |
| `externalSecrets.externalSecretsOperator.backendType` | Specifies the backend type for the External Secrets Operator. The backend type determines where the secrets are stored, such as in a Kubernetes Secret or an external secrets management system like AWS Secrets Manager.                  | `secretsManager`         |
| `externalSecrets.externalSecretsOperator.secretRef`   | Specifies the reference to the external secret resource to use with the External Secrets Operator. This allows the operator to retrieve the secret mappings and create Kubernetes Secrets based on them.                                   | `[]`                     |
| `service.type`                                        | Specifies the type of Service to create, such as ClusterIP, NodePort, or LoadBalancer. The type determines how the Service is exposed to the network.                                                                                      | `ClusterIP`              |
| `service.externalPort`                                | Specifies the port number to use for external traffic to the Service. This is the port that other services or clients use to access the Service.                                                                                           | `3000`                   |
| `service.internalPort`                                | Specifies the port number to use for internal traffic to the Service. This is the port that the Service uses to communicate with its associated Pods.                                                                                      | `3000`                   |
| `service.annotations`                                 | Specifies a map of annotations to attach to the Service resource. Annotations are used to add metadata to the resource that can be used by tools or scripts that interact with the resource.                                               | `{}`                     |
| `service.labels`                                      | Specifies a set of labels to apply to the Service resource. Labels are used to organize and filter resources in Kubernetes.                                                                                                                | `{}`                     |
| `service.selector`                                    | Specifies the label selector used to associate the Service with its associated Pods. The selector determines which Pods are included in the Service.                                                                                       | `{}`                     |
| `livenessProbe.enabled`                               | Specifies whether to enable liveness probe or not. If set to true, the liveness probe is enabled. If set to false, the liveness probe is disabled.                                                                                         | `true`                   |
| `livenessProbe.path`                                  | Specifies the HTTP endpoint to use for the liveness probe. This is the endpoint that Kubernetes will use to determine whether the container is still alive and should continue to receive traffic.                                         | `/api/checkHealth`       |
| `livenessProbe.initialDelaySeconds`                   | Specifies the number of seconds to wait before performing the first liveness probe. This delay allows time for the container to initialize and start accepting traffic.                                                                    | `30`                     |
| `livenessProbe.timeoutSeconds`                        | Specifies the number of seconds to wait for a response from the liveness probe endpoint. If a response is not received within this time, the container is considered to have failed the liveness probe.                                    | `10`                     |
| `livenessProbe.failureThreshold`                      | Specifies the number of consecutive failures that must occur before the container is considered to have failed the liveness probe. If the container fails the liveness probe this many times in a row, it will be restarted by Kubernetes. | `3`                      |
| `resources.limits.cpu`                                | Specifies the maximum amount of CPU that the deployment can use. This is a hard limit that cannot be exceeded.                                                                                                                             | `4096m`                  |
| `resources.limits.memory`                             | Specifies the maximum amount of memory that the deployment can use. This is a hard limit that cannot be exceeded.                                                                                                                          | `8192Mi`                 |
| `resources.requests.cpu`                              | Specifies the minimum amount of CPU that the deployment requires to run.                                                                                                                                                                   | `2048m`                  |
| `resources.requests.memory`                           | Specifies the minimum amount of memory that the deployment requires to run.                                                                                                                                                                | `4096Mi`                 |
| `ingress.enabled`                                     | Specifies whether to create an Ingress resource or not. If set to true, the Ingress resource is created. If set to false, the Ingress resource is not created.                                                                             | `true`                   |
| `ingress.labels`                                      | Specifies a set of labels to apply to the Ingress resource. Labels are used to organize and filter resources in Kubernetes.                                                                                                                | `{}`                     |
| `ingress.annotations`                                 | Specifies a map of annotations to attach to the Ingress resource. Annotations are used to add metadata to the resource that can be used by tools or scripts that interact with the resource.                                               | `{}`                     |
| `ingress.hosts`                                       | Specifies a list of hostnames to associate with the Ingress resource. Each hostname is associated with a set of rules that determine how traffic is routed to the appropriate Service or endpoint.                                         | `nil`                    |
| `ingress.tls`                                         | Specifies a list of TLS certificates to use for secure communication with the Ingress resource. Each TLS certificate is associated with a set of rules that determine how traffic is routed to the appropriate Service or endpoint.        | `nil`                    |
| `ingress.pathType`                                    | Specifies the path type to use for the Ingress resource. Path type determines how path-based routing is performed, and can be set to Exact, Prefix, or ImplementationSpecific.                                                             | `ImplementationSpecific` |

### Additional Parameters

##### These parameters are not defined in the values.yaml file by default

| Name                                        | Description                                                                                                                                                                               | Value |
| ------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----- |
| `nameOverride`                              | Replaces the name of the chart when this is used to construct Kubernetes object names                                                                                                     |       |
| `fullnameOverride`                          | ReplacesCompletely replaces the generated name                                                                                                                                            |       |
| `config.licenseKeySecretName`               | The name of the secret where the Retool license key is stored (can be used instead of licenseKey)                                                                                         |       |
| `config.licenseKeySecretKey`                | The key in the k8s secret, default: license-key                                                                                                                                           |       |
| `config.auth.google.clientSecretSecretName` | The name of the secret where the google client secret is stored (can be used instead of clientSecret)                                                                                     |       |
| `config.auth.google.clientSecretSecretKey`  | The key in the k8s secret, default: google-client-secret                                                                                                                                  |       |
| `config.encryptionKeySecretName`            | The name of the secret where the encryption key is stored (can be used instead of encryptionKey)                                                                                          |       |
| `config.encryptionKeySecretKey`             | The key in the k8s secret, default: encryption-key                                                                                                                                        |       |
| `config.jwtSecretSecretName`                | The name of the secret where the jwt secret is stored (can be used instead of jwtSecret)                                                                                                  |       |
| `config.jwtSecretSecretKey`                 | config.jwtSecretSecretKey The key in the k8s secret, default: jwt-secret                                                                                                                  |       |
| `service.externalIPs`                       | Specifies a list of external IP addresses to assign to the Service. This is useful when you want to assign a static IP address to the Service.                                            |       |
| `service.portName`                          | Specifies a name for the Service port. This can be useful when you want to refer to the port by a more descriptive name than the port number.                                             |       |
| `ingress.ingressClassName`                  | Specifies a set of labels to apply to the Ingress resource. Labels are used to organize and filter resources in Kubernetes. (For k8s 1.18+)                                               |       |
| `affinity`                                  | Affinity for pod assignment.                                                                                                                                                              |       |
| `maxUnavailable`                            | Specifies the maximum number of replicas that can be unavailable during a Deployment or StatefulSet update.                                                                               |       |
| `persistentVolumeClaim.storageClass`        | Specifies the name of the storage class to use for the PVC resource. Storage classes are used to define different classes of storage with different performance and cost characteristics. |       |

### Postgresql Parameters

##### These parameters are used to configure your Retool internal database

| Name                                   | Description                                                                                                                                                                        | Value |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----- |
| `config.postgresql.host`               | Specifies the host or server name where the PostgreSQL database is located. This could be an IP address or a domain name.                                                          |       |
| `config.postgresql.port`               | Specifies the port number on which the PostgreSQL server is listening for incoming connections. The default port for PostgreSQL is 5432.                                           |       |
| `config.postgresql.db`                 | Specifies the name of the database to be used.                                                                                                                                     |       |
| `config.postgresql.user`               | Specifies the username to be used to connect to the PostgreSQL database.                                                                                                           |       |
| `config.postgresql.password`           | Specifies the password associated with the username for connecting to the PostgreSQL database. This password is typically encrypted or hashed for security purposes.               |       |
| `config.postgresql.ssl_enabled`        | Specifies whether SSL/TLS encryption is enabled for the PostgreSQL connection. SSL/TLS encryption is used to secure communication between the application and the database server. |       |
| `config.postgresql.passwordSecretName` | the name of the secret where the pg password is stored (can be used instead of password)                                                                                           |       |
| `config.postgresql.passwordSecretKey`  | the key in the k8s secret, default: postgresql-password                                                                                                                            |       |

### Postgresql Subchart Parameters

##### These parameters are used when using the Postgres subchart for your Retool internal database

| Name                                       | Description                                                                                                                                                                                                   | Value                   |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------- |
| `postgresql.enabled`                       | Specifies whether to enable the PostgreSQL subchart or not. If set to true, the subchart is enabled and a PostgreSQL instance is deployed as part of the chart. If set to false, the subchart is not enabled. | `true`                  |
| `postgresql.ssl_enabled`                   | Specifies whether SSL should be enabled or not for PostgreSQL connections.                                                                                                                                    | `false`                 |
| `postgresql.auth.database`                 | Specifies the name of the database to be used.                                                                                                                                                                | `hammerhead_production` |
| `postgresql.auth.username`                 | Specifies the username to be used for accessing the database.                                                                                                                                                 | `retool`                |
| `postgresql.auth.postgresPassword`         | Specifies the password to be used for accessing the database.                                                                                                                                                 | `retool`                |
| `postgresql.service.port`                  | Specifies the port on which PostgreSQL should listen for connections.                                                                                                                                         | `5432`                  |
| `postgresql.image.repository`              | Specifies the Docker image repository to use for the PostgreSQL container.                                                                                                                                    | `postgres`              |
| `postgresql.image.tag`                     | Specifies the Docker image tag to use for the PostgreSQL container.                                                                                                                                           | `11`                    |
| `postgresql.postgresqlDataDir`             | Specifies the directory where PostgreSQL data is stored.                                                                                                                                                      | `/data/pgdata`          |
| `postgresql.primary.persistence.enabled`   | Specifies whether to use persistent storage for PostgreSQL data.                                                                                                                                              | `true`                  |
| `postgresql.primary.persistence.mountPath` | Specifies the path where persistent storage is mounted.                                                                                                                                                       | `/data/`                |
