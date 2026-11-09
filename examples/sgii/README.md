# Sitemap for AI Search

- [Sitemap for AI Search](#sitemap-for-ai-search)
  - [How it works](#how-it-works)
  - [Security](#security)
  - [Operations](#operations)
    - [Example](#example)

## How it works

Use a complete SGII baseline inventory to create a sitemap of current web objects for AI Search's that uses sitemap crawling mode.

SGII scans object versions with `ListObjectVersions`, not recursive `ListObjectsV2`. `query objects --latest-only` selects current version records and excludes keys whose latest entry is a delete marker.

The current `sgi` CLI has no XML output format or extension/time filter flags as that's considered a downstream use case.

Export JSONL first, then use the following Python 3 standard-library converter to write `--output <name>.xml`. The existing scan's Parquet file is sufficient; no additional snapshot or Parquet conversion is needed.

```sh
$ sgi query objects \
  --manifest s3://sgi/scans/<chain>/<baseline-scan-time>/manifest.json \
  --prefix web/ \
  --latest-only \
  --sample 0 \
  --format jsonl \
  --output web-objects.jsonl \
  --env-file kompromise-cosi-snapshots/.env
```

Configure the public HTTPS URL that Caddy or other S3 reverse proxy maps to this manifest's `last_committed.name` snapshot bucket. 

This example preserves the full object key: `web/about.html` becomes `https://snapshot.example.com/web/about.html`. If Caddy strips a prefix, adjust the URL mapping accordingly. Do not use the StorageGRID API endpoint or a live source bucket URL when an immutable snapshot view is required.

The converter accepts `--extensions` (case-insensitive suffixes; empty means all objects) and optional inclusive `--since` / exclusive `--before` UTC modification-time bounds. Time-filtered output is a changed-object subset, not a complete site sitemap. Here the unique filename includes UTC time, epoch nanoseconds, and a random suffix, avoiding a fixed `sitemap.xml` object name.

See the example code in [`sgii-ingest.sh`](./sgii-ingest.sh).

For example, add `--since 2026-11-01T00:00:00Z --before 2026-11-09T00:00:00Z` before the heredoc to restrict modification times. Object-key URL encoding and XML escaping are separate operations; the converter handles both. It refuses to overwrite an existing output file and checks the sitemap protocol limits. For larger inventories, split the output and serve a sitemap index instead.

Keep the XML outside the read-only snapshot bucket, either as a local Caddy-served file or in a separate writable publishing bucket. Use a Caddy `handle` for the exact generated XML path and a separate handler for the snapshot's S3 reverse proxy. Serve the XML as `application/xml` on the same public host as its object URLs, and configure AI Search to use that sitemap URL. Ensure both the sitemap and listed content are accessible to the crawler without exposing S3 credentials (required by Caddy), and retain the snapshot for the entire crawl. Choose extensions and content types supported by the crawler; listing an object does not make its content crawlable. Markdown, HTML, PDF, CSV, and text are often crawable.

The same command can target an incremental manifest, but a `between` scan contains only that window's changes. Its sitemap omits untouched pages and cannot express deletions; do not replace a complete sitemap with it or assume AI Search treats missing URLs as delete instructions. A full updated sitemap requires a new complete inventory or a deliberately maintained current-key state built from the baseline plus subsequent latest-version and delete-marker changes. Simply concatenating baseline and incremental object queries would retain deleted URLs.

## Security

- SGII's `--prefix` argument allows the inclusion of only objects under `s3://bucket/prefix/`
- `--extensions ""` is required to include all extensions. Omitting the argument gets you nothing.
- `sitemap.xml` served over HTTP(S) won't contain objects not included in SGII query command output, but users who can browse Web site or know precise locations of objects not included in `sitemap.xml` can still access data that is in the snapshot

Because of that, prefix filtering and `sitemap.xml` cannot limit access to bucket contents. Depending on how bucket is shared, other objects may be accessible even if they're not enumerated in `sitemap.xml`.

What you can do about it:
- Create an `ai-bot` group and individual bots that belong to it, with no S3 access by default. Use these principals (either the group, or individual bots) in snapshot bucket's ACLs.
- If you use tags, `s3:ExistingObjectTag/<tag-key>` can be used in ACLs to limit access by tag
- `s3:prefix`
- In addition to prefix filtering, apply restrictive bucket ACL on the snapshot: allow access to the prefix directory and deny access to the rest. This is recommended if bucket data is read by users other than bucket owner.
- Or, apply path restrictions on HTTPS reverse proxy (allow prefix paths and reject others).

The container that shares S3 data needs credentials to access StorageGRID (the assumption is you won't share to anonymous). Use S3 keys with minimum-scoped (`s3:GetObject`) ACLs on only the bucket your gateway serves. Dispose the container and keys afterwards. STS AssumeRole can be used as well.

## Operations

Unlike some other workflows, StorageGRID and SGII make it possible to:
- Create an easy workflow with S3 as First Class storage for AI and Analytics
- Make it possible to completely avoid storage management in the cloud

To that end:
- This workflow doesn't require storage administrator, resulting in convenience, faster time to result, lower costs, fewer human errors and a better ROI
- This workflow is easy to automate: identify, snapshot, propose, approve, effect. Without "thinking time", 60 seconds tops
- You don't need own storage in the cloud. Simply expose your endpoint to your cloud gateway

**NOTE:** SGII by design does not allow read-write snapshots. StorageGRID itself allows writable snapshots, but SGII isn't interested in them so, on the one hand, you don't need to tell users they shouldn't write to their snapshot bucket (because they won't be able to) and, on the other, that pattern would be weird and is one of the reasons SGII doesn't implement it. Create your own automation if you want it differently because SGII won't add writable snapshots.

### Example

- Bucket: `ai-cloner` with public content for AI chatbot under `public_blog` prefix. Default bucket policies allow the tenant root only
- Groups:
  - `ai-managers` - the guys who manage access for AIs. You need to be careful here. I allowed this group of users to manage buckets in the tenant (i.e. like the tenant root can), so they can override ACLs, for example. You may not want to do that, but then someone will have to do that for them, so you only add another layer of complexity
  - `bots-read-only` - read-only group for AI bots, with no default group permissions
- Users:
  - `marketing-bot`, from the `bots-read-only` group -  `urn:sgws:identity::55295525968323305569:user/Read-only Marketing Bot`
  - `ai-decider`, from the `ai-managers` group - `urn:sgws:identity::55295525968323305569:user/ai-decider`
- Actions:
  - `s3:GetObject` - required to get sitemap and objects listed in it should be given to the marketing bot, but only when `prefix="public_blog"`. We don't want the rest in AI chatbot.

With this, tenant root or `ai-managers` can clone the bucket and assign ACLs:

```json
{
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::55295525968323305569:group/ai-managers"
      },
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::ai-cloner-snap",
        "arn:aws:s3:::ai-cloner-snap/*"
      ]
    },
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::55295525968323305569:user/Read-only Marketing Bot"
      },
      "Action": "s3:GetObject",
      "Resource": [
        "arn:aws:s3:::ai-cloner-snap",
        "arn:aws:s3:::ai-cloner-snap/*"
      ]
      "Condition": {
        "StringLike": {
          "s3:prefix": "public_blog/*"
        }
      }
    }
  ]
}
```

Anyone from `ai-managers`, because I gave the group "Manage all buckets" permission, can upload this policy to the snapshot bucket:

```sh
aws s3api put-bucket-policy --bucket ai-cloner-clone --policy file://policy.json
```

If you want a more complex workflow, you could add another step, where some compliance dude runs their guardrails and what-have-ya batch-job on the snapshot bucket, and *then* (iff OK), pushes the ACLs. So the `ai-managers` group would only "nominate" and "propose" an ACL on the clone, while `compliance-managers` would effect if approved.

Finally, you need to expose this snapshot from some container. Caddy is recommended, but NGINX and others can do that as well:
- Share S3 as HTTP site, or proxy access to StorageGRID Load Balancer, which in turn serves snapshot bucket. For S3, reader should use S3 keys for `Read-only Marketing Bot`. For HTTP export of S3 as Web content, the HTTP proxy should use the same user's S3 keys to access the bucket and clients wouldn't need to have the S3 keys.
- Inject the sitemap file on that container (remember, you can't write to the bucket!).
- Let the AI scanner know http://a348ss.cloudaccess.company.com:443/snapshot-20261108T183911Z-1794163151782176684-c94ac7893a15.xml has the goods.
- Make sure this workflow is recorded in SIEM or elsewhere. StorageGRID audit logs should be forwarded and collected as well, if you need to track access for SIEM or compliance.