# SGII 

SGII produces source-of-truth inventory records and stores them in user-configured bucket. It does not modify source buckets, rclone destinations, Elasticsearch, or OpenSearch indexes, although its output may be used to that effect.

SGII can emit query results as S3-compatible event notifications with `--format s3-event`. Snapshot scans collect only the inexpensive version-listing fields by default. Use `sgi snap --include-metadata` and/or `--include-tags` when those details are needed: user metadata requires `HeadObject`, and tags require `GetObjectTagging`, so each option adds object-level S3 requests and scan time.

## Tips and good practices

Despite precautions taken by SGII, there may be bugs in SGII or SGII example queries, so perform basic sanity checks using simple simulations on tests buckets.

SGII and its sample queries aren't the only places where issues may arise: bucket inventories may be temporarily stale due to pending Grid consistency, network issues or other reasons. That is why it is generally recommended to:
- Rely on applications to perform own bucket replication or synchronization where possible.
- Alternatively, for highest reliability, upload, replicate and sync from an event-streaming cluster. This is resource-expensive and usually not necessary for use cases with unstructured data where minor discrepancies do not meaningfully impact outcomes.
- In many cases it is sufficient to rely on events and periodically check with sampling from inventory database (which is what SGII creates). You can use SGII as primary method and Notifications for checks/verification as secondary (or the other way around) to identify and remedy failures in the primary approach. Remember that even StorageGRID Notifications have availability, completeness and other limitations (see the StorageGRID documentation for more on that).
- Do not use use snapshot intervals longer than StorageGRID ILM deletion or tiering rules, because in that case objects may get deleted or moved before they get scanned.

Discipline in how content is added to and removed from buckets helps.

Objects *can* be added, overwritten and deleted any way you want, but it is easier to understand, reason about and troubleshoot replication and synchronization pipelines if the way it is done is not chaotic. For example, we can space out overwrites, use user metadata to ease object tracking and so on. With "anything goes", SGII should still work the same way, but figuring out what exactly happened, in which order and at what step may not be easy, creating extra burden on support and operations.

With a bit of best practices and caution, this combined approach can be reliable enough for many use cases.

Full bucket enumeration on live buckets "just to be safe" every time you do it **does not solve anything**. It is actually worse because objects may change several times while scanning is ongoing. If you do full enumeration, at least use `sg-cosi` Snapshot Lease (see main `sg-cosi` README), which gives you a Point-in-Time bucket view to work with, and automatically deletes the snapshot bucket after specified "lease" time has passed.

## SGII variables

The following variables may be used by SGII:

| Variable | Use |  Required |
| :--------| :---: | :------|
| ENDPOINT | S3 endpoint | Yes|
| USERNAME| S3 access key	| Yes|
| PASSWORD| S3 secret key	| Yes|
| REGION	| S3 signing region	| Yes|
| SG_TENANT_API_ENDPOINT | StorageGRID Tenant API endpoint	| Yes|
| SG_TENANT_ID | Tenant account ID	| Yes|
| SG_TENANT_ADMIN | Tenant API username	| Yes|
| SG_TENANT_PASSWORD | Tenant API password	| Yes|
| TLS_VERIFY | Tenant API certificate verification; defaults to true	| No|
| CA_BUNDLE	| Optional Tenant API CA bundle path	| No|

You can keep them in an `.env` file and reference with `--env-file kompromise-cosi-snapshots/.env`, for example.

`TLS_VERIFY` is dangerous without `CA_BUNDLE` because your tenant *and* S3 credentials can be exposed.

## SGII snapshots

### Snapshot creation time

Baseline inventory time is **proportional** to the number of object versions and delete markers, not merely the number of current keys.

Large or version-heavy buckets **may take hours**. Do not interrupt the command merely because it does not finish within a few minutes. If interrupted after snapshot creation, no manifest is committed, but an unused snapshot bucket may remain for cleanup.

Incremental snapshots should take less time if changes are less than all changes between the time the bucket was created and the time of baseline snapshot.

### Create a baseline and incremental snapshot

This simple example illustrates how to get started:
- The user keeps SGII database files in his bucket called `sgi`. To create a *baseline* snapshot for a production bucket `deletion-ilm` using our .env file:

```sh
./bin/sgi snap --db-bucket sgi --source deletion-ilm --env-file kompromise-cosi-snapshots/.env --snapshot deletion-baseline-snap --type baseline
```

`--include-metadata` and `--include-tags` can be used to get more data, but are disabled by default. That these multiply the workload required to produce inventory, so unless you need that extra information, do not enable these options.

Be patient. What has to happen:

- SGI creates the read-only snapshot and waits for it to become ready. This takes less than a minute, usually 10 seconds.
- It enumerates all object versions and delete markers with paginated `ListObjectVersions` calls. This can take seconds to hours.
- It writes every record to Parquet and publishes the manifest. This is usually several seconds.

`ListObjectVersions` enumeration is sequential: SGI waits for each paginated S3 request to complete before issuing the next one. SGI does not create worker threads or fetch pages in parallel. This keeps one invocation conservative, but it is not a rate limiter; a large scan can still issue a continuous stream of requests until enumeration finishes. Avoid running multiple scans for the same bucket concurrently, and use the normal StorageGRID monitoring and scheduling practices (including [Traffic Limiting policies](https://docs.netapp.com/us-en/storagegrid/admin/managing-traffic-classification-policies.html#matching-rules)) if service impact is a concern.

After some time, a baseline bucket listing will be created in `s3://sgi/scans` (our `--db-bucket`). In the console you will see something like:

```raw
baseline snapshot=sgi-deletion-ilm-20261010t171634z rows=13 parquet=s3://sgi/scans/39be365e-15dc-4bc6-af0d-4589137c6398/20261010T172310.957501314Z/data.parquet manifest=s3://sgi/scans/39be365e-15dc-4bc6-af0d-4589137c6398/20261010T172310.957501314Z/manifest.json
```

Wait 10 minutes *and* allow some changes to happen in the watched bucket (new objects, deleted objects). Then take another snapshot with `--type incremental`. With two adjacent snapshots, you can run queries (see below). Snapshots default to `now()-300s` so it's easier to wait several minutes although `--at` can be used as well (example: `--at 2026-10-13T12:10:00Z`).

Take a look at the manifest files and snapshot buckets on StorageGRID to see what's what.

The third and subsequent snapshots would also be `--type incremental`. Each needs the previous for a comparison query. SGII cannot compare against a snapshot bucket with a random point in time.

If another baseline is created accidentally, it starts a new chain. The original chain and its manifests remain usable, but select it explicitly when creating the next incremental:

```sh
./bin/sgi snap \
  --type incremental \
  --chain <original-chain-id> \
  --db-bucket sgi \
  --source deletion-ilm \
  --env-file kompromise-cosi-snapshots/.env
```

Without `--chain`, SGI selects the newest valid manifest only when the source has one chain. If multiple chains exist, SGI refuses to guess; use `sgi list` and pass the intended `--chain`.

How manifests are connected:

- Every manifest contains the same `chain_id`.
- Every incremental manifest preserves the original baseline.
- Every new incremental manifest records its immediate predecessor in `predecessor_manifest` as a full S3 URI.
- `last_committed` identifies the snapshot and Parquet file represented by that manifest.
- `sgi list` scans `scans/` path in database bucket, reads all manifests, and reconstructs the chain view from those fields.

### List manifests and chains

Use `sgi list` to find related manifests, baseline names, and the snapshot bucket represented by each committed scan:

```sh
./bin/sgi list \
  --db-bucket sgi \
  --source deletion-ilm \
  --headers on \
  --env-file kompromise-cosi-snapshots/.env
```

Filter further with `--chain` or `--snapshot`. The output includes the chain ID, baseline bucket, last committed snapshot bucket, time window, row count, predecessor manifest URI, and manifest URI.

The snapshot bucket is not encoded in the Parquet path. It is recorded in the manifest. For the active checkpoint, use `last_committed.name`:

```sh
mc cat pepsi/sgi/scans/<chain>/<scan-time>/manifest.json | jq -r '.last_committed.name'
```

Use that value as the StorageGRID snapshot bucket when reading the corresponding inventory. Do not infer the source bucket from the `scans/<chain>/<scan-time>/` path.

### Run the guided evaluation

For a small, reproducible demonstration of versioning and incremental inventory, create and use a test bucket with versioning enabled:

```sh
python3 examples/sg-inventory-evaluate.py \
  --env-file kompromise-cosi-snapshots/.env \
  --bucket deletion-ilm \
  --db-bucket sgi \
  --yes
```

The evaluator checks that the source bucket has versioning enabled, then creates two baseline objects, creates a baseline inventory, overwrites one object, deletes the other, creates a third object, and creates an incremental inventory. It then creates a second overwrite and a fourth object before creating a second incremental inventory.

The default wait between mutations and each incremental snapshot is 12 minutes. SGII uses a cutoff approximately six minutes in the past, so a five-minute wait can place the mutations outside the incremental window. Use `--wait-seconds` to change this deliberately; waits shorter than 11 minutes produce a warning.

Artifacts are written to a timestamped `sgi-evaluation-*` directory unless `--output-dir` is supplied. They include the manifests, raw StorageGRID `list-object-versions` results, SGII JSONL records, text reports, JSON comparison reports, and a Markdown summary table. The evaluator leaves its uniquely prefixed test objects in the source bucket so a separate StorageGRID notifications watcher can observe the same mutations. Remove that prefix only after notification and inventory inspection is complete.

The evaluator is intentionally independent of a notifications watcher. Run it by itself for an inventory demonstration, or run the watcher alongside it to compare near-real-time notifications with the later point-in-time incremental reports. The comparison should account for notification timing, retries, duplicates, and the deliberate overlap between adjacent SGII windows.

### Delete a snapshot bucket

SGII does not delete snapshot buckets automatically. To inspect old buckets in one chain, use `snap prune` with a committed manifest. The default is a dry run and retains the newest two snapshot buckets:

```sh
./bin/sgi snap prune \
  --db-bucket sgi \
  --manifest s3://sgi/scans/<chain>/<scan-time>/manifest.json \
  --keep 2 \
  --env-file kompromise-cosi-snapshots/.env
```

Pass `--yes` only after reviewing the list. The command deletes old snapshot buckets but retains their Parquet files and manifests for audit. `--keep` counts the newest committed snapshot buckets in the anchored manifest chain; it must be positive.

SGII does not delete snapshot buckets implicitly. This is to avoid making "black box moves" and surprises.

If you create many incremental snapshot buckets, you may want to delete older ones while retaining the two most recent committed snapshots. You can identify the buckets to *keep* by reading `last_committed.name` from the two most recent manifests.

Workflow: after a baseline snapshot on Sunday, you create daily incrementals every day of the week. By next Sunday you have seven snapshot buckets, but you really need only the most recent two because each scan is compared only with its immediate predecessor. You could delete the oldest five and leave just the last two. Never delete the current predecessor before its successor has been committed.

Do not preserve an old baseline while deleting all of its incremental successors and expect SGII to continue from that baseline. The manifest chain and Parquet databases would need a deliberate merge or reset, and the old baseline may already have holes because StorageGRID ILM removed historical versions.

If ILM makes a chain unreliable, reset it with a new baseline. Retain the old manifests and Parquet files for audit if useful, then remove old snapshot buckets only after the new baseline is committed and its `last_committed.name` is the active checkpoint. The new baseline starts a new chain; do not manually splice old incremental databases into it.

Mind your ILM policies on the buckets where you use SGII and watch carefully what happens.

Parquet files on S3 are small and cheap to retain, so they are less of a problem and can be left alone. 

## SGII Queries (Current Commands)

This document collects common questions that SGII inventory data should answer. It is intentionally split between behavior available in the current CLI and queries that need a future command or downstream integration.

Prior to querying, you would execute `sgi snap --type baseline` and (after some changes and at least 10 minutes later) `sgi snap --type incremental` (use `sgi snap -h` for more) to have something to query.

### Inspect an incremental delta

A `between` scan is already a delta. It contains version records and delete-marker records observed in the requested time window.

```sh
./bin/sgi report \
  --manifest s3://sgi/scans/<chain>/<scan-time>/manifest.json \
  --env-file kompromise-cosi-snapshots/.env
```

Example output:

```text
source=sgi-source snapshot=sgi-sgi-source-20261008t144237z filter=between rows=20
versions=15 delete-markers=5
```

The `--sample` option limits only the printed examples. It does not limit enumeration:

```sh
./bin/sgi report \
  --manifest s3://sgi/scans/<chain>/<scan-time>/manifest.json \
  --sample 100
```

### Compare complete inventories

When both manifests refer to complete inventories, `--previous-manifest` compares immutable records by bucket, key, version ID, kind, timestamp, ETag, and size.

```sh
./bin/sgi report \
  --manifest s3://sgi/scans/<chain>/<current-scan>/manifest.json \
  --previous-manifest s3://sgi/scans/<chain>/<previous-scan>/manifest.json \
  --env-file kompromise-cosi-snapshots/.env
```

The comparison categories are:

- `added`: present in the current inventory but not the previous inventory
- `removed`: present in the previous inventory but not the current inventory
- `mismatched`: same immutable identity, different metadata

A `between` scan should not be compared to a complete baseline as though it were a complete inventory. Its rows are changes, not the complete state of the bucket.

These queries are useful for generating worklists for rclone or another transfer tool.

### Query reports and query types

Supported options:

- `--manifest`
- `--prefix`
- `--kind version|delete-marker`
- `--latest-only`
- `--sample`
- `--headers on|off` for text output; defaults to `off`
- `--format text|jsonl|parquet|s3-event`
- `--output`
- `--include-metadata` and `--include-tags` (effective only if it was gathered with the snap command)

`query changes` and `query objects` read the same Parquet records but have different defaults and intended uses:

- `query changes` returns both `version` and `delete-marker` records. Use `--kind` to select one category.
- `query objects` returns only `version` records. Use `--latest-only` when a current-object worklist is wanted; without it, historical version records are included.

Incremental snapshots use a one-minute overlap with the preceding snapshot window. SGII deduplicates repeated object identities while enumerating one snapshot and writing its Parquet file, so a single manifest does not contain duplicate rows caused by pagination or the overlap. SGII does not deduplicate across different manifests: querying adjacent incremental manifests separately can return the same version or delete marker from both. Consumers combining multiple snapshots must deduplicate by at least `bucket`, `key`, `version_id`, and `kind`.

The default incremental cutoff is also five minutes before the command's current time (`beforeTime=now()-300s`). This is independent of the one-minute overlap. A recently created object can therefore be absent from a scan even when the snapshot command is run after the object was created; use an explicit `--at` cutoff after the object timestamp when testing or when a different boundary is required.

The text format is headerless by default for simple pipelines. Add headers for interactive exploration:

```sh
./bin/sgi query objects \
  --manifest s3://sgi/scans/<chain>/<scan>/manifest.json \
  --headers on \
  --sample 5
```

```sh
./bin/sgi query changes \
  --manifest s3://sgi/scans/<chain>/<scan>/manifest.json \
  --kind delete-marker \
  --prefix sgi-workload/delete-me.txt \
  --sample 5 \
  --format jsonl
```

## Examples

### What changed since the last checkpoint?

Return all version records and delete markers in the latest committed window, optionally filtered by prefix.

```sh
./bin/sgi query changes \
  --manifest s3://sgi/scans/<chain>/<scan-time>/manifest.json \
  --prefix customer-a/ \
  --sample 100
```

The command supports text, JSONL, and Parquet output. Text is convenient for inspection; JSONL or Parquet are more useful for automation. `--format` selects the format; `--output` is a file path. For example, use `--format jsonl`, not `--output jsonl`.

### Which current objects should be copied?

For mirroring the current object state, consumers usually need current versions rather than every historical version.

```sh
./bin/sgi query objects \
  --manifest s3://sgi/scans/<chain>/<scan-time>/manifest.json \
  --latest-only \
  --format jsonl \
  --output new-objects.jsonl
```

This is intentionally different from a version-preserving backup query.

For one object key, S3 marks exactly one entry as `IsLatest` - either the newest object version or the newest delete marker. What that means is if the same object gets uploaded twice (t0 version, t1 version), and deleted once after that (t3), `--latest-only` should show only the deletion as the latest change. In the opposite case (delete isn't the last action on a key), an "intermediate" deletion won't show up as "latest" since another PUT that came after it would be "latest" at the end of snapshot time range.

### Which objects should be deleted at the destination?

If you're replicating or copying to a remote bucket, delete markers can produce a destination deletion worklist:

```sh
./bin/sgi query changes \
  --manifest s3://sgi/scans/<chain>/<scan-time>/manifest.json \
  --kind delete-marker \
  --format text
```

The important rule for a non-versioned destination is: process the union of latest `version` and latest `delete-marker` records for the same snapshot. Copy latest `versions`; delete destination keys for latest delete markers. Do not query only latest `version`s and assume that absence of an object means deletion from the source, because an incremental scan is not a complete inventory - if an object hasn't been touched in the snapshot period, it won't be in the "between"-style snapshot bucket's list of objects.

A destination policy must decide whether a delete marker means deleting the current destination object, preserving a destination version, or recording a tombstone. Example: StorageGRID Cloud Mirror [does **not** mirror deletes](https://docs.netapp.com/us-en/storagegrid/ilm/comparing-cloud-storage-pools-to-cloudmirror-replication.html) to the destination bucket, so the destination can pile up objects the source no longer has. You could use SGII to delete deleted objects at the destination.

### Which versions disappeared?

A missing historical version is **not** automatically a delete-marker event. It may have been removed by ILM or another version-pruning operation.

This requires comparing two complete inventories, or comparing a complete inventory against an accumulated inventory state. The result should be classified separately as `pruned` rather than `deleted`.

## Index Reconciliation

SGII should remain independent of Elasticsearch, OpenSearch or other schemas. It can produce neutral source worklists; an index-specific adapter can query the destination and record the result.

### Did notifications for new objects arrive?

Sample newly observed versions and look them up in the index:

```sh
./bin/sgi query changes \
  --manifest s3://sgi/scans/<chain>/<scan-time>/manifest.json \
  --kind version \
  --sample 100 \
  --format jsonl
```

The reconciliation adapter should compare at least:

- source bucket and object key

To feed an OpenSearch index from a query result, request S3-event output and send each record to the index API. For example, this sends each event record as a separate OpenSearch document:

```sh
./bin/sgi query changes \
  --manifest s3://sgi/scans/<chain>/<scan-time>/manifest.json \
  --kind version \
  --format s3-event \
  --output events.json

jq -c '.Records[]' events.json | while IFS= read -r event; do
  curl --fail-with-body --silent --show-error \
    --user "$OPENSEARCH_USER:$OPENSEARCH_PASSWORD" \
    -H 'Content-Type: application/json' \
    -X POST "https://<opensearch-host>:9200/sgi-index/_doc" \
    --data "$event"
done
```

This example lets OpenSearch generate document IDs, so rerunning it creates duplicates. A reconciliation adapter that needs idempotent updates should derive a stable ID from the bucket, key, and version ID, then use `PUT /sgi-index/_doc/<id>` (with the ID URL-encoded) or use the OpenSearch bulk API. The `s3-event` format always uses a `Records` array, and optional StorageGRID metadata and tags are carried under each record's `sgi` extension.

### Which objects were overwritten?

An overwrite is a new version for a key that already had an earlier version. It should be distinct from a new key.

A future query should classify records using the accumulated key/version history:

- `new-key`: no earlier version for the object key
- `overwritten`: an earlier version exists for the same object key
- `delete-marker`: a delete marker was observed
- `pruned`: an earlier version disappeared from a later complete inventory

The current `query` commands do not claim these history-dependent classifications yet.

## DuckDB Exploration

Parquet is often the easiest format for ad hoc exploration. After writing or downloading a scan file, DuckDB can query it directly:

```sql
SELECT kind, count(*) AS records
FROM read_parquet('data.parquet')
GROUP BY kind
ORDER BY kind;
```

Show the newest version records:

```sql
SELECT bucket, object_key, version_id, size, etag, last_modified
FROM read_parquet('data.parquet')
WHERE kind = 'version'
ORDER BY last_modified DESC
LIMIT 5;
```

Show current versions only:

```sql
SELECT bucket, raw_key, version_id, size, etag
FROM read_parquet('data.parquet')
WHERE kind = 'version' AND is_latest;
```

For direct S3 access, use DuckDB's `httpfs` extension and configure the StorageGRID S3 endpoint and credentials according to the local DuckDB setup. Keeping the SGII query command headerless by default preserves shell compatibility, while DuckDB provides richer ad hoc grouping and filtering.

### Which index records are stale?

The adapter can take an index export and compare it to SGII source records:

```sql
SELECT i.bucket, i.object_key, i.version_id
FROM index_records AS i
LEFT JOIN source_inventory AS s
  ON s.bucket = i.bucket
 AND s.object_key = i.object_key
 AND s.version_id = i.version_id
WHERE s.version_id IS NULL;
```

This identifies index records that are absent from the selected complete SGII inventory. The actual index export schema and the policy for removing historical versions belong to the reconciliation adapter, not SGII. A `between` scan alone cannot prove that a record is stale because it contains only changes observed during its window.

### Can I sample reconciliation results?

Yes. Sampling should be per category, not one global sample. For example, `--sample 100` should allow up to 100 records each for new, overwritten, deleted, pruned, and missing-from-index results.

The `sgi list` command shows:

- chain ID
- source bucket identity
- baseline cutoff
- latest committed cutoff
- baseline and last snapshot bucket names
- manifest URI

### Are there coverage gaps?

For adjacent committed scans, report:

- previous cutoff
- next cutoff
- configured overlap
- effective gap or overlap
- missing or out-of-order chain members

The overlap is a scheduling safety margin, not proof that notifications or inventory records cannot be missed.

### Which snapshot buckets are stale?

A future cleanup report should distinguish:

- committed predecessor still needed by the chain
- latest committed snapshot

## ILM and ORLM Evidence

A controlled StorageGRID experiment showed that ILM deletion is visible in versioned S3 listings but does not produce a usable S3/SNS notification for SGII (or anyone else, for that matter). The audit log records an `IDEL` operation with `AMID:ILMX`; for current-version deletion it also records a new `DMRK` delete-marker version ID. A following `ORLM` record confirms that the ILM operation completed and policy conditions met. Historical-version deletion records contain the deleted `VSID` but do not create a delete marker. These state transitions are otherwise the same as ordinary object and version deletion from SGII's perspective.

This means SGII can observe an ILM deletion only if a snapshot enumerates the relevant versioned listing before ILM removes it. If ILM removes a version between snapshots, the version simply disappears from the next inventory. If it disappears before any SGII snapshot captures it, SGII cannot report that deletion from the latest snapshot alone; use complete-inventory comparisons or an accumulated inventory to classify it as `pruned`.

Users who need pruning information should schedule snapshots more frequently than the shortest ILM interval that removes non-current versions. Audit-log-to-webhook translation should not be treated as a replacement for this cadence, because `IDEL` and `ORLM` are audit evidence rather than reliable object notifications.

## Proposed Query Categories

The neutral result categories could (depending on needs & feedback) eventually include:

- `new-key`
- `overwritten`
- `delete-marker`
- `pruned`
- `missing-from-index`
- `stale-index-record`
- `metadata-mismatch`
- `unchanged`

The first implementation priority is a filtered, machine-readable worklist with `--prefix`, `--kind`, `--sample`, and `--format jsonl|text|parquet`. Index reconciliation can then consume the same worklist without adding OpenSearch-specific (or other destination-specific) assumptions to SGII.
