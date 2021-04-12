# retool-helm

This repository contains the **Helm 2** chart for installing and configuring
Retool on Kubernetes. For full documentation on all the ways you can deploy
Retool on your own infrastructure, please see the [Setup
Guide](https://docs.retool.com/docs/setup-instructions).

## Prerequisites

- This chart requires **Helm 2.0** and **Kubernetes 1.16+**.
- A PostgreSQL database.
  - Persistent volumes are not reliable - we strongly recommend that a long-term
  installation of Retool host the database on an externally managed database (for example, AWS RDS).

## Usage
1.  Clone this repo

        $ git clone git@github.com:tryretool/retool-helm.git

1. In the `values.yaml` file, disable the included postgresql chart by setting
`postgresql.enabled` to `false`. Then specify your external database
through the `config.postgresql.\*` properties at the top of the file.

1. In the `values.yaml` file, set values for `encryptionKey` and `jwtSecret`. They should each be a different long, random string that you keep private. See our docs on [Environment Variables](https://docs.retool.com/docs/environment-variables) for more information on how they are used.

1. In the `values.yaml` file, set the version of Retool you want to install in the `image.tag` field. See our guide on [Retool Release Versions](https://docs.retool.com/docs/updating-retool-on-premise#retool-release-versions) to see your options, and [Docker Hub](https://hub.docker.com/r/tryretool/backend/tags) for the latest version numbers. To prevent issues while upgrading Retool, set a specific semver version number (i.e. a version in the format X.Y.Z) instead of a tag name.
    * If you're not sure which version to install, we recommend starting with the "release-candidate". To find out the specific version number of the "release-candidate", visit [Retool Release Versions](https://docs.retool.com/docs/updating-retool-on-premise#retool-release-versions). (As of early April 2021 the "release-candidate" version is "2.65.3".)

1. Please see the many other options supported in the `values.yaml` file.

1. Now you're all ready to install Retool:

        $ helm install my-retool ./
