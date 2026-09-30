<p align="center">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://docs.retool.com/brand/icons/logo-light.svg">
      <img alt="Retool Logo" height="100" src="https://docs.retool.com/brand/icons/logo-dark.svg">
    </picture>
</p>
<h3 align="center">The best way to build internal software</h3>




# Deploying Retool on Helm

Find deployment instructions in the [official Helm deployment guide](https://docs.retool.com/docs/deploy-with-helm) hosted on docs.retool.com.

This is the repository for the official Retool Helm chart. For release notes, see the [releases section](https://github.com/tryretool/retool-helm/releases) of this repo.

For any inquiries regarding deploying Retool on Helm, please feel free to reach out to us at support@retool.com or search our [Community Forums](https://community.retool.com/) and post your question there.

## MCP public URL smoke test

When MCP is enabled, set `mcp.test.publicUrl` to the public Retool origin to add an optional `helm test` Job:

```yaml
mcp:
  enabled: true
  test:
    publicUrl: https://retool.example.com
    image: python:3.12-alpine # Override with a Python 3 image from your registry if needed.
```

The Job pod must be able to resolve and reach that URL through the public ingress, and trust its TLS certificate. This may require egress access or hairpin routing from the cluster. The URL must be an HTTP(S) origin without a path. The image must provide Python 3 and its standard library; the Job uses the chart's `image.pullSecrets` for private registries. With an empty `publicUrl`, or when `mcp.enabled` is false, the hook is omitted.

After installing or upgrading the release, run:

```sh
helm test <release> --namespace <namespace>
```

The test sends unauthenticated requests to `/mcp`, the advertised `resource_metadata` URL, `/.well-known/oauth-protected-resource`, and `/.well-known/oauth-authorization-server`. It expects a 401 Bearer challenge and valid, consistent JSON discovery metadata. A failed Job is retained: find it with `kubectl get jobs --namespace <namespace>`, then read `kubectl logs job/<job-name> --namespace <namespace>`. A successful Job is removed. Some Helm versions, including 4.2.0, try to read Job logs from a Pod with the Job's name when `--logs` is used, so that flag can report an error even after the test succeeds. Each failure names the URL, expected result, and observed status or missing field. Redirects, HTML login pages, malformed JSON, and connection errors fail the test. It does not authenticate a user or exercise MCP tools.
