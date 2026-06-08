# sg-cosi-driver

![Version](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2Fscaleoutsean%2Fsg-cosi-driver%2Fmaster%2Fdeploy%2Fhelm%2Fsg-cosi-driver%2FChart.yaml&query=%24.version&label=Chart&color=blue)
![AppVersion](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2Fscaleoutsean%2Fsg-cosi-driver%2Fmaster%2Fdeploy%2Fhelm%2Fsg-cosi-driver%2FChart.yaml&query=%24.appVersion&label=App&color=green)

Helm chart for the [SG COSI Driver](https://github.com/scaleoutsean/sg-cosi-driver). Deploys a [COSI](https://github.com/kubernetes-sigs/container-object-storage-interface-spec) driver that manages S3 buckets and per-app credentials on NetApp StorageGRID through Kubernetes custom resources (`Bucket`, `BucketAccess`).

See the [project README](https://github.com/scaleoutsean/sg-cosi-driver) for architecture, features, and troubleshooting.

## Prerequisites

- Kubernetes >=1.35
- Helm >= 3
- [COSI Controller 0.2.2](https://github.com/kubernetes-sigs/container-object-storage-interface) installed in the cluster
- A running NetApp StorageGRID with Tenant Admin API accessible and enabled
- A tenant admin (or equivalent) credentials Secret in the target namespace

## Installing the Chart

```bash
# 1. Install the COSI controller (if not already installed)
kubectl create -k 'https://github.com/kubernetes-sigs/container-object-storage-interface//?ref=v0.2.2'

# 2. Install the chart

```bash
kubectl create secret generic sg-tenant-credentials \
  --from-literal=username=YOUR_TENANT_USERNAME \
  --from-literal=password=YOUR_TENANT_PASSWORD

helm install sg-cosi-driver \
  oci://docker.io/scaleoutsean/charts/sg-cosi-driver \
  --set driver.name=sg.cosi.scaleoutsean.github.io \
  --set storagegrid.credentials.secretName=sg-tenant-credentials
```

## Uninstalling the Chart

```bash
helm uninstall sg-cosi-driver
```

This does not delete BucketClass, BucketAccessClass, or any provisioned Bucket/BucketAccess resources. Clean those up separately if needed.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `driver.name` | string | `""` | COSI driver name (**required**). Must be unique per driver instance. |
| `driver.image.repository` | string | `docker.io/scaleoutsean/sg-cosi-driver` | Driver container image |
| `driver.image.tag` | string | `""` | Image tag (defaults to chart appVersion) |
| `driver.image.pullPolicy` | string | `IfNotPresent` | Image pull policy |
| `driver.resources` | object | `{}` | Resource requests/limits for driver container |
| `driver.securityContext` | object | see `values.yaml` | Security context for driver container |
| `sidecar.image.repository` | string | `registry.k8s.io/sig-storage/objectstorage-sidecar` | COSI sidecar image |
| `sidecar.image.tag` | string | `v0.2.2` | Sidecar image tag |
| `sidecar.extraArgs` | list | `[]` | Extra arguments for sidecar (e.g. `["--v=5"]`) |
| `sidecar.resources` | object | `{}` | Resource requests/limits for sidecar container |
| `sidecar.securityContext` | object | see `values.yaml` | Security context for sidecar container |
| `storagegrid.serviceName` | string | `s3` | StorageGRID service name for endpoint derivation |
| `storagegrid.s3Endpoint` | string | `""` | S3 API endpoint (derived from serviceName if empty) |
| `storagegrid.s3Port` | int | `10443` | S3 API port (used when s3Endpoint is empty) |
| `storagegrid.adminEndpoint` | string | `""` | Admin API endpoint (derived from serviceName if empty) |
| `storagegrid.adminPort` | int | `9443` | Tenant Admin API port (used when adminEndpoint is empty) |
| `storagegrid.region` | string | `us-east-1` | S3 region |
| `storagegrid.credentials.secretName` | string | `storagegrid-tenant-credentials` | Tenant Admin credentials Secret name |
| `storagegrid.credentials.accessKeyField` | string | `rootAccessKeyId` | Access key field name in Secret |
| `storagegrid.credentials.secretKeyField` | string | `rootSecretAccessKey` | Secret key field name in Secret |
| `serviceAccount.create` | bool | `true` | Create a ServiceAccount |
| `serviceAccount.name` | string | `""` | ServiceAccount name (generated if empty) |
| `serviceAccount.annotations` | object | `{}` | ServiceAccount annotations |
| `rbac.create` | bool | `true` | Create ClusterRole and ClusterRoleBinding |
| `bucketClass.create` | bool | `true` | Create a default BucketClass |
| `bucketClass.name` | string | `""` | BucketClass name (defaults to `storagegrid`) |
| `bucketClass.deletionPolicy` | string | `Delete` | Bucket deletion policy |
| `bucketAccessClass.create` | bool | `true` | Create a default BucketAccessClass |
| `bucketAccessClass.name` | string | `""` | BucketAccessClass name (defaults to `storagegrid`) |
| `bucketAccessClass.authenticationType` | string | `KEY` | Authentication type |
| `podSecurityContext` | object | see `values.yaml` | Pod-level security context |
| `nodeSelector` | object | `{}` | Node selector |
| `tolerations` | list | `[]` | Tolerations |
| `affinity` | object | `{}` | Affinity rules |
| `podAnnotations` | object | `{}` | Pod annotations |
| `podLabels` | object | `{}` | Pod labels |
| `imagePullSecrets` | list | `[]` | Image pull secrets |
