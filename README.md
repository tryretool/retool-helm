# retool-helm

[![Artifact HUB](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/retool)](https://artifacthub.io/packages/search?repo=retool)

This repository contains the official **Helm 3** chart for installing and configuring
Retool on Kubernetes. For full documentation on all the ways you can deploy
Retool on your own infrastructure, please see the [Setup
Guide](https://docs.retool.com/docs/setup-instructions).

## Prerequisites

* This chart requires **Helm 3.0**.
* A PostgreSQL database.
  * Persistent volumes are not reliable - we strongly recommend that a long-term
  installation of Retool host the database on an externally managed database (for example, AWS RDS).

## Usage
1. Add the Retool Helm repository:

        $ helm repo add retool https://charts.retool.com
        "retool" has been added to your repositories

2. Ensure you have access to the `retool` chart:

        $ helm search repo retool/retool
        NAME         	CHART VERSION	APP VERSION	DESCRIPTION                
        retool/retool	4.0.0        	2.66.2     	A Helm chart for Kubernetes

2. In the `values.yaml` file, disable the included postgresql chart by setting `postgresql.enabled` to `false`. Then specify your external database through the `config.postgresql.\*` properties at the top of the file.

3. In the `values.yaml` file, set the version of Retool you want to install in the `image.tag` field. See our guide on [Retool Release Versions](https://docs.retool.com/docs/updating-retool-on-premise#retool-release-versions) to see your options, and [Docker Hub](https://hub.docker.com/r/tryretool/backend/tags) for the latest version numbers. To prevent issues while upgrading Retool, set a specific semver version number (i.e. a version in the format X.Y.Z) instead of a tag name.
    * If you're not sure which version to install, we recommend starting with the "release-candidate". To find out the specific version number of the "release-candidate", visit [Retool Release Versions](https://docs.retool.com/docs/updating-retool-on-premise#retool-release-versions). (As of early April 2021 the "release-candidate" version is "2.65.3".)

4. Please see the many other options supported in the `values.yaml` file.

5. Now you're all ready to install Retool:

        $ helm install my-retool retool/retool
