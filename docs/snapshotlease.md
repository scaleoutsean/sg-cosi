# Leased snapshot buckets

`SnapshotLease` creates a temporary, read-only StorageGRID snapshot bucket and AccessKey credentials through COSI. It is intended to provide a stable point-in-time source for user-operated backup or analysis jobs inside or outside of Kubernetes.

It does not copy data, schedule jobs, configure destinations, prevent overlapping destination writers, verify backups, or implement restore workflows.

## Enable the controller

The controller is disabled by default. Enable it on the Helm release for the StorageGRID tenant:

```yaml
snapshotLease:
  enabled: true
  maxLifetime: 168h
  credentialGrace: 1h
  resyncInterval: 1h
```

Each `SnapshotLease` must specify the unique `driver.name` of that release. This prevents controllers for different StorageGRID tenants from handling each other's leases.

## Create a lease

Edit the driver, namespace, and source bucket in `examples/snapshotlease.yaml`, then apply it:

```bash
kubectl apply -f examples/snapshotlease.yaml
kubectl get snapshotlease project1-backup-source -n sg-cosi-coke -w
```

The controller creates a dedicated `BucketClass`, `BucketAccessClass`, `BucketClaim`, and `BucketAccess`. When the phase becomes `Active`, read the COSI credentials from the Secret named in `status.resources.credentialsSecret`:

```bash
SECRET=$(kubectl get snapshotlease project1-backup-source -n sg-cosi-coke \
  -o jsonpath='{.status.resources.credentialsSecret}')
kubectl get secret "$SECRET" -n sg-cosi-coke \
  -o jsonpath='{.data.BucketInfo}' | base64 -d | jq
```

If `SECRET` is empty, the controller has not populated `status.resources` yet. Check the lease and controller logs first:

```bash
kubectl get snapshotlease project1-backup-source -n sg-cosi-coke -o yaml
kubectl logs -n sg-cosi-coke deployment/sg-cosi-coke-snapshotlease --tail=120
```

A common cause is a lease duration that exceeds the controller's configured maximum lifetime. For example, `duration: 24h` is rejected if the Helm release was installed with `snapshotLease.maxLifetime=1h`.

## Extend a lease

Renewal uses an absolute UTC timestamp so every extension is visible in Kubernetes object history and audit logs:

```bash
kubectl patch snapshotlease project1-backup-source -n sg-cosi-coke \
  --type=merge \
  -p '{"spec":{"renewUntil":"2026-09-18T12:00:00Z"}}'
```

The requested time must be later than `status.expiresAt`, submitted before cleanup starts, and no later than `status.hardExpiresAt`. Check the `RenewalAccepted` status condition for the result.

The AccessKey does not rotate when a lease is extended. At initial provisioning it receives a defensive expiry of `status.hardExpiresAt` plus `credentialGrace`; accepted renewals can never pass that hard deadline.

## Cleanup behavior

At expiry, or when the lease is deleted early, the controller performs cleanup in this order:

1. Delete `BucketAccess` and wait for COSI to revoke the StorageGRID user and key.
2. Delete `BucketClaim` and wait for COSI to delete the snapshot bucket.
3. Delete the per-lease cluster-scoped access and bucket classes.

Failures remain visible in status and are retried. Naturally expired `SnapshotLease` objects remain in phase `Expired` for audit visibility. Delete the object when that record is no longer needed:

```bash
kubectl delete snapshotlease project1-backup-source -n sg-cosi-coke
```

Cleanup begins at `status.expiresAt` or on the next reconciliation. `resyncInterval` is the worst-case safety interval after missed events or controller downtime.

## Backup safety

The lease guarantees an immutable source view only. When copying repeatedly into one versioned destination bucket, overlapping jobs can still make an older source version current after a newer job writes. Destination locking, concurrency, version manifests, retention, verification, and restore selection remain the backup operator's responsibility.

## Example walk-through

An example walk-through with some additional context may be viewed [on my blog](https://scaleoutsean.github.io/2026/09/18/storagegrid-s3-cosi-snapshot-leases.html.)
