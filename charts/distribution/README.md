# distribution

A Helm chart for [distribution/distribution](https://github.com/distribution/distribution)
(OCI registry v3, formerly known as `registry:2`).

One release = one registry instance. Storage defaults to a filesystem-backed
PVC; set `config.storage` to switch drivers.

```sh
helm repo add 0ekk https://0ekk.github.io/helm-charts
helm install my-registry 0ekk/distribution
```

## Values

| Key | Default | Description |
|---|---|---|
| `replicaCount` | `1` | Must stay `1` when `gc.enabled` is `true`. |
| `image.repository` | `docker.io/library/registry` | |
| `image.tag` | `""` | Defaults to `.Chart.AppVersion`. |
| `config` | `{}` | Raw registry config, deep-merged over the chart's defaults. See below. |
| `auth.htpasswd.enabled` | `false` | Adds HTTP basic auth from an existing htpasswd Secret. |
| `auth.htpasswd.existingSecret` | `""` | Secret name containing the htpasswd file. |
| `auth.htpasswd.secretKey` | `htpasswd` | Key inside that Secret. |
| `persistence.enabled` | `true` | Provisions a PVC when filesystem storage is used. |
| `persistence.size` | `10Gi` | |
| `persistence.existingClaim` | `""` | Use an existing PVC instead of provisioning one. |
| `service.port` | `5000` | |
| `metrics.enabled` | `false` | Exposes the registry's debug/metrics port and enables Prometheus metrics in config. |
| `metrics.serviceMonitor.enabled` | `false` | Requires the Prometheus Operator CRDs. |
| `ingress.enabled` | `false` | |
| `gc.enabled` | `false` | See "Garbage collection" below. |
| `gc.schedule` | `0 3 * * *` | |
| `gc.deleteUntagged` | `false` | |
| `extraEnv` / `extraVolumes` / `extraVolumeMounts` | `[]` | |

## Config passthrough

`config:` is deep-merged over the chart's own defaults (HTTP addresses,
delete/storagedriver health checks, and — unless you set any of
`config.storage.{filesystem,s3,gcs,azure,inmemory}` yourself — a filesystem
default rooted at `/var/lib/registry`). Put secrets (S3 keys, etc.) in
`extraEnv` as `REGISTRY_*` environment variables instead of in `config`,
since `config` ends up in a Secret manifest but is not itself encrypted at
rest by Kubernetes any more than env vars are — the split just keeps
credentials out of `helm get values` / `helm template` output.

### S3 storage via extraEnv

```yaml
config:
  storage:
    s3:
      region: us-east-1
      bucket: my-registry-bucket
extraEnv:
  - name: REGISTRY_STORAGE_S3_ACCESSKEY
    valueFrom: { secretKeyRef: { name: registry-s3, key: access-key } }
  - name: REGISTRY_STORAGE_S3_SECRETKEY
    valueFrom: { secretKeyRef: { name: registry-s3, key: secret-key } }
```

### Pull-through proxy

```yaml
config:
  proxy:
    remoteurl: https://registry-1.docker.io
    ttl: 168h
```

### htpasswd auth

```yaml
auth:
  htpasswd:
    enabled: true
    existingSecret: my-registry-htpasswd
```

## Garbage collection

`gc.enabled: true` adds an initContainer that runs `registry garbage-collect`
before the registry starts on every pod (re)start — the Deployment strategy
is forced to `Recreate` so there is never a second writer during the run —
and a CronJob that restarts the Deployment on `gc.schedule` to trigger this
periodically. The registry is unavailable for the duration of each GC run.
A failed GC only logs to stderr; it never blocks the registry from starting.
Requires `replicaCount: 1`.

## Ingress

When fronting the registry with an nginx Ingress, large image layers need:

```yaml
ingress:
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
```
