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

2. In the `values.yaml` file, disable the included postgresql chart by setting
`postgresql.enabled` to `false`. Then specify your external database
through the `config.postgresql.\*` properties at the top of the file.

3. In the `values.yaml` file, set the version of Retool you want to install in the `image.tag` field. See our guide on [Retool Release Versions](https://docs.retool.com/docs/updating-retool-on-premise#retool-release-versions) to see your options, and [Docker Hub](https://hub.docker.com/r/tryretool/backend/tags) for the latest version numbers. To prevent issues while upgrading Retool, set a specific semver version number (i.e. a version in the format X.Y.Z) instead of a tag name.

4. Please see the many other options supported in the `values.yaml` file.

5. Now you're all ready to install Retool:

        $ helm install my-retool ./
