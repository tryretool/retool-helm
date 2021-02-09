# retool-helm

This repository contains the Helm 2 chart for installing and configuring
Retool on Kubernetes. For full documentation on all the ways you can deploy
Retool on your own infrastructure, please see the [Setup
Guide](https://docs.retool.com/docs/setup-instructions).

## Prerequisites

- This chart requires **Helm 2.0** and **Kubernetes 1.16+**.
- Persistent volumes are not reliable - we recommend that a long-term
  installation of Retool host the database on an externally managed database
  like RDS. Please disable the included postgresql chart by setting
  postgresql.enabled to false and then specifying your external database
  through the config.postgresql.\* properties.

## Usage

1.  Clone this repo

        $ git clone git@github.com:tryretool/retool-helm.git

2.  Now you're all ready to install Retool:

        $ helm install my-retool ./

Please see the many options supported in the `values.yaml` file.
