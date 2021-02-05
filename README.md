# retool-helm

This repository contains the official Helm chart for installing and configuring
Retool on Kubernetes. For full documentation on all the ways you can deploy
Retool on your own infrastructure, please see the [Setup
Guide](https://docs.retool.com/docs/setup-instructions).

## Prerequisites

* This chart requires **Helm 3.0**.
* Persistent volumes are not reliable - we recommend that a long-term
  installation of Retool host the database on an externally managed database
  like RDS. Please disable the included postgresql chart by setting
  postgresql.enabled to false and then specifying your external database
  through the config.postgresql.* properties.

## Usage

1. Add the Retool Helm repository:
    
        $ helm repo add retool https://charts.retool.com
        "retool" has been added to your repositories
    
2. Ensure you have access to the `retool` chart: 

        $ helm search repo retool/retool
        NAME         	CHART VERSION	APP VERSION	DESCRIPTION                
        retool/retool	4.0.0        	2.66.2     	A Helm chart for Kubernetes

3. Now you're all ready to install Retool:

        $ helm install my-retool retool/retool

Please see the many options supported in the `values.yaml` file.
