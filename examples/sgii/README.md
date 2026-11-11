# Sitemap for AI Search

- [Sitemap for AI Search](#sitemap-for-ai-search)
  - [How it works](#how-it-works)
  - [Security](#security)
  - [Operations](#operations)
    - [Example](#example)
    - [About this demo](#about-this-demo)

## How it works

Use a complete SGII baseline inventory to create a sitemap of current web objects for AI Search's that uses sitemap crawling mode.

SGII scans object versions with `ListObjectVersions`, not recursive `ListObjectsV2`. `query objects --latest-only` selects current version records and excludes keys whose latest entry is a delete marker.

The current `sgi` CLI has no XML output format or extension/time filter flags as that's considered a downstream use case.

Export JSONL first, then use the following Python 3 standard-library converter to write `--output <name>.xml`. The existing scan's Parquet file is sufficient; no additional snapshot or Parquet conversion is needed.

```sh
sgi query objects \
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

Run the standalone Python 3 converter, [`sgii-ingest.py`](./sgii-ingest.py). It uses only the standard library. If `--output` is omitted, it creates a uniquely named XML file in the current directory and prints its filename.

```sh
mkdir -p examples/sgii/sitemaps
python3 examples/sgii/sgii-ingest.py \
  --input web-objects.jsonl \
  --base-url https://proj1a2b3c.public.company.com/ \
  --extensions .txt,.md \
  --output examples/sgii/sitemaps/snapshot-proof.xml
```

Use the gateway's actual public hostname for `--base-url`. For the supplied Compose setup, set `SG_SITEMAP=snapshot-proof.xml` in its `.env` file and recreate the Caddy container after changing this variable. The sitemap URL is then `https://proj1a2b3c.public.company.com/snapshot-proof.xml`. Use a fresh output filename for each subsequent run; do not write into the read-only snapshot bucket.

For example, add `--since 2026-11-01T00:00:00Z --before 2026-11-09T00:00:00Z` to restrict modification times. Object-key URL encoding and XML escaping are separate operations; the converter handles both. It refuses to overwrite an existing output file and checks the sitemap protocol limits. For larger inventories, split the output and serve a sitemap index instead.

Keep the XML outside the read-only snapshot bucket, either as a local Caddy-served file or in a separate writable publishing bucket. Use a Caddy `handle` for the exact generated XML path and a separate handler for the snapshot's S3 reverse proxy. Serve the XML as `application/xml` on the same public host as its object URLs, and configure AI Search to use that sitemap URL. Ensure both the sitemap and listed content are accessible to the crawler without exposing S3 credentials (required by Caddy), and retain the snapshot for the entire crawl. Choose extensions and content types supported by the crawler; listing an object does not make its content crawlable. Markdown, HTML, PDF, CSV, and text are often crawable.

The same command can target an incremental manifest, but a `between` scan contains only that window's changes. Its sitemap omits untouched pages and cannot express deletions; do not replace a complete sitemap with it or assume AI Search treats missing URLs as delete instructions. A full updated sitemap requires a new complete inventory or a deliberately maintained current-key state built from the baseline plus subsequent latest-version and delete-marker changes. Simply concatenating baseline and incremental object queries would retain deleted URLs.

## Security

- SGII's `--prefix` argument allows the inclusion of only objects under `s3://bucket/prefix/`
- `--extensions ""` is required to include all extensions. Omitting the argument includes only `.html` and `.htm` objects, case-insensitively.
- `sitemap.xml` served over HTTP(S) won't contain objects not included in SGII query command output, but users who can browse the Web site or know precise locations of objects not included in `sitemap.xml` can still access data that is in the snapshot and allowed by its bucket policy

Because of that, prefix filtering and `sitemap.xml` cannot limit access to snapshot bucket's contents. Depending on how the bucket is shared, other objects may be accessible even if they're not enumerated in `sitemap.xml`.

What you can do about it:
- Create an `ai-bot` group and individual bots that belong to it, with no S3 access by default. Use these principals (either the group, or individual bots) in snapshot bucket's ACLs.
- If you use tags, `s3:ExistingObjectTag/<tag-key>` can be used in ACLs to limit access by tag
- `s3:prefix`
- In addition to prefix filtering, apply restrictive bucket ACL on the snapshot: allow access to the prefix directory and deny access to the rest. This is recommended if bucket data is read by users other than bucket owner.
- Or, apply path restrictions on HTTPS reverse proxy (allow prefix paths and sitemap.xml, while denying all others).

The container that shares S3 data needs credentials to access StorageGRID (the assumption is you won't share to anonymous). Use S3 keys with minimum-scoped (`s3:GetObject`) ACLs on only the bucket your gateway serves. Dispose the container and keys afterwards. STS AssumeRole can be used as well.

The example provided here is for demonstration purposes. See further below for more.

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

Configure a dot-env file with credentials, for example kompromise-cosi-snapshots/.env and create a baseline snapshot on the bucket `ai-cloner`, storing SGII information in the `sgi` bucket:

```sh
sgi snap --db-bucket sgi --source ai-cloner --env-file kompromise-cosi-snapshots/.env --snapshot ai-cloner-snap --type baseline
```

Response:
```sh
baseline snapshot=ai-cloner-snap rows=19 parquet=s3://sgi/scans/80f2a61c-9d8c-42e6-8b32-4fc752455e6b/20261110T082129.335662931Z/data.parquet manifest=s3://sgi/scans/80f2a61c-9d8c-42e6-8b32-4fc752455e6b/20261110T082129.335662931Z/manifest.json
```

My base bucket and my snapshot-bucket:

```sh
$ mc ls pepsi/ai-cloner
[2026-11-09 13:19:07 CST] 4.9KiB STANDARD 2023-08-31-teradata-ons-s3-netapp.md
[2026-11-10 16:24:58 CST]     0B intranet_blog/
[2026-11-10 16:24:58 CST]     0B public_blog/

$ mc ls pepsi/ai-cloner-snap
[2026-11-09 13:19:07 CST] 4.9KiB STANDARD 2023-08-31-teradata-ons-s3-netapp.md
[2026-11-10 16:25:01 CST]     0B intranet_blog/
[2026-11-10 16:25:01 CST]     0B public_blog/
```

I want only the content from prefix `public_blog` content exposed to AI chat assistant.

```sh
sgi query objects \
  --manifest s3://sgi/scans/80f2a61c-9d8c-42e6-8b32-4fc752455e6b/20261110T082129.335662931Z/manifest.json \
  --prefix public_blog/ \
  --latest-only \
  --sample 0 \
  --format jsonl \
  --output web-objects.jsonl \
  --env-file kompromise-cosi-snapshots/.env
```

It is important to perform some checks, such that prefixes (paths) that shouldn't be included aren't included.

```sh
grep intranet_blog examples/sgii/web-objects.jsonl
```

Since my server is at `https://<FQDN>:<PORT>` where PORT isn't 443, I need to provide that detail along with desired extensions (mostly Markdown, really).
```sh
python3 examples/sgii/sgii-ingest.py \
  --input web-objects.jsonl \
  --base-url https:///<FQDN>:<PORT>/ \
  --extensions .txt,.md
```

This gives me a site-map.

```sh
snapshot-20261110T093439Z-1794303279263137839-287e601ac167.xml
```

I moved that file to `./sitemaps/` for Docker Compose. For the same bucket, multiple XML files could be stored and served from this same proxy, as long as bucket policy allows.

Note that in this particular example, I messed up and used Caddy at `https://dt.datafabric.lan`, but the TLS certificate I created had issues with that name and the port was not set. I had to search-and-replace the XML file (or re-run the ingest command) to make that base URL `https://dt:8443` instead (as that was easier than re-issuing the certificate and changing the DNS entry).

Also remember that proxy's protocol, host name and port for `endpoint` must match what you have in the sitemap XML (valid hostname and TLS certificate for the StorageGRID S3 API endpoint).

We need to do just two more things:
- Apply a bucket policy for the S3 keys used by our Web proxy
- Start serving this sitemap file and proxying access to the bucket

Tenant root or any of `ai-managers` can clone the bucket and assign a bucket policy like this:

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
        "arn:aws:s3:::ai-cloner-snap/public_blog/*"
      ]
    }
  ]
}
```

Note that the bot resource allows access to everything in `s3://ai-cloner-snap/public_blog/*`, which was the idea. Tighten it further if you need to.

Anyone from `ai-managers`, because I gave the group "Manage all buckets" permission, can upload this policy file to the snapshot bucket:

```sh
aws s3api put-bucket-policy --bucket ai-cloner-snap --policy file://policy.json
```

Remember to start your Web proxy with the correct S3 credentials, otherwise the sitemap may be served okay, but object contents not at all.

```sh
docker compose up
# or potentially
# source .env
# caddy run --config Caddyfile
```

Therefore, test access with the XML sitemap first, as that's served by the proxy server, not S3. Then try accessing bucket contents. For example:

```sh
wget https://dt:8443/public_blog/2026-07-25-weka-io-tier-cold-to-netapp-storagegrid.md
--2026-11-11 11:30:14--  https://dt:8443/public_blog/2026-07-25-weka-io-tier-cold-to-netapp-storagegrid.md
Resolving dt (dt)... 192.168.1.13
Connecting to dt (dt)|192.168.1.13|:8443... connected.
HTTP request sent, awaiting response... 200 OK
Length: unspecified [text/markdown]
Saving to: ‘2026-07-25-weka-io-tier-cold-to-netapp-storagegrid.md’
```

Caddy log:

```json
{
  "level": "info",
  "ts": 1794367815.5537472,
  "logger": "http.log.access.log0",
  "msg": "handled request",
  "request": {
    "remote_ip": "192.168.1.13",
    "remote_port": "37460",
    "client_ip": "192.168.1.13",
    "proto": "HTTP/1.1",
    "method": "GET",
    "host": "dt:8443",
    "uri": "/public_blog/2026-07-25-weka-io-tier-cold-to-netapp-storagegrid.md",
    "headers": {
      "Connection": [
        "Keep-Alive"
      ],
      "User-Agent": [
        "Wget/1.21.4"
      ],
      "Accept": [
        "*/*"
      ],
      "Accept-Encoding": [
        "identity"
      ]
    },
    "tls": {
      "resumed": false,
      "version": 772,
      "cipher_suite": 4865,
      "proto": "",
      "server_name": "dt",
      "ech": false
    }
  },
  "bytes_read": 0,
  "user_id": "",
  "duration": 0.469134664,
  "size": 13688,
  "status": 200,
  "resp_headers": {
    "Server": [
      "Caddy"
    ],
    "Alt-Svc": [
      "h3=\":8443\"; ma=2592000"
    ],
    "Content-Type": [
      "text/markdown"
    ],
    "Etag": [
      "\"e4c8926ec3653885e7de7941d81a4305\""
    ],
    "Last-Modified": [
      "Mon, 09 Nov 2026 04:59:50 GMT"
    ],
    "Accept-Ranges": [
      "bytes"
    ]
  }
}
```

StorageGRID audit log (formatted by me for sanity) for bucket policy applied, and HTTP access and audit entries related to GetObject access:

```sh
2026-11-11T03:29:22+08:00 
  sg-storage-02 
  Audit: 2026-11-11T03:29:22.713729 
  [AUDT:
    [MRMD(CSTR):"PUT"]
    [MPAT(CSTR):"/api/v4/org/containers/ai-cloner-snap/policy"]
    [MPQP(CSTR):""][MDNA(CSTR):"192.168.1.211"]
    [MSIP(CSTR):"192.168.1.13"]
    [MDIP(CSTR):"192.168.1.211"]
    [MUUN(CSTR):"urn:sgws:identity::55295525968323305569:root"]
    [MRSC(UI32):200]
    [RSLT(FC32):SUCS]
    [MRSP(CSTR):"{\"policy\":{\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::55295525968323305569:group/ai-managers\"},\"Action\":[\"s3:GetObject\",\"s3:ListBucket\"],\"Resource\":[\"arn:aws:s3:::ai-cloner-snap\",\"arn:aws:s3:::ai-cloner-snap/*\"]},{\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::55295525968323305569:user/Read-only Marketing Bot\"},\"Action\":\"s3:GetObject\",\"Resource\":[\"arn:aws:s3:::ai-cloner-snap/public_blog/*\"]}]}}"]
    [MRBD(CSTR):""]
    [AVER(UI32):10]
    [ATIM(UI64):1794367762713729]
    [ATYP(FC32):MGAU]
    [ANID(UI32):12257404]
    [AMID(FC32):GMGT]
    [ATID(UI64):9439052543954811533]]

2026-11-11T03:30:15+08:00 
  sg-admin-01 
  endpoint: [2026-11-11T03:30:15+00:00] 
    192.168.1.13 200 6529 550 0.343 "8f8035a9-f517-4a5d-b916-6ec16134f56a" "192.168.1.213:18086"
    "GET /ai-cloner-snap/public_blog/2026-07-25-weka-io-tier-cold-to-netapp-storagegrid.md HTTP/1.1" 
    "192.168.1.211:10443"

2026-11-11T03:30:15+08:00 
  sg-storage-01 
  Audit: 2026-11-11T03:30:15.541181 
  [AUDT:
    [RSLT(FC32):SUCS]
    [CNID(UI64):1794367815203469]
    [TIME(UI64):282108]
    [SAIP(IPAD):"192.168.1.13"]
    [TLIP(IPAD):"192.168.1.211"]
    [S3AI(CSTR):"55295525968323305569"]
    [SACC(CSTR):"pepsi"]
    [S3AK(CSTR):"97T57WYOVZ0LO5FIR6B8"]
    [SUSR(CSTR):"urn:sgws:identity::55295525968323305569:user/Read-only Marketing Bot"]
    [SBAI(CSTR):"55295525968323305569"]
    [SBAC(CSTR):"pepsi"]
    [S3BK(CSTR):"ai-cloner-snap"]
    [S3KY(CSTR):"public_blog/2026-07-25-weka-io-tier-cold-to-netapp-storagegrid.md"]
    [VSID(CSTR):"NjREMEJGNUEtREJGQS0xMUYxLTlBQjItMjRDNzAwQzRGOUFB"]
    [CBID(UI64):0x0000000000000000]
    [UUID(CSTR):"64D16AE3-DBFA-11F1-880A-DF760074F9AA"]
    [CSIZ(UI64):13688]
    [MTME(UI64):1794200390490505]
    [AVER(UI32):10][ATIM(UI64):1794367815541181]
    [ATYP(FC32):SGET]
    [ANID(UI32):12908970]
    [AMID(FC32):S3RQ]
    [ATID(UI64):4002747496792963910]]
```

Finally, we want to make sure that:
- The bot reader can't access the original bucket
- The bot reader can't access files outside the specified path

As the tenant (or AI) admin, I can see these and that's expected (and desired, if I need to run PII checks on everything):

```sh
$ mc ls pepsi/ai-cloner/2023-08-31-teradata-ons-s3-netapp.md 
[2026-11-09 13:19:07 CST] 4.9KiB STANDARD 2023-08-31-teradata-ons-s3-netapp.md
$ mc ls pepsi/ai-cloner-snap/intranet_blog/2021-07-19-solidfire-mib-snmp-monitoring.md 
[2026-11-09 13:19:35 CST]  44KiB STANDARD 2021-07-19-solidfire-mib-snmp-monitoring.md
```

AI marketing bots are **not** supposed to be able to access these:
- Base bucket: we can't really tell as HTTP client, since the Web server connects to only the snapshot bucket. We could test with an S3 client, but that's separate from this use case
- We can try this on the snapshot bucket shared by the proxy: `wget https://dt:8443/internal_blog/2021-07-16-iqn-level-chap-authentiation-on-solidfire.md`

Let's see:

```sh
$ wget https://dt:8443/internal_blog/2021-07-16-iqn-level-chap-authentiation-on-solidfire.md
--2026-11-11 11:52:57--  https://dt:8443/internal_blog/2021-07-16-iqn-level-chap-authentiation-on-solidfire.md
Resolving dt (dt)... 192.168.1.13
Connecting to dt (dt)|192.168.1.13|:8443... connected.
HTTP request sent, awaiting response... 403 Forbidden
2026-11-11 11:52:57 ERROR 403: Forbidden.
```

StorageGRID has no audit log for this attempt because only access on load balancer happened, while the S3 API wasn't used due to error 403 seen here as well:

```sh
2026-11-11T03:53:58+08:00 sg-admin-01 
  endpoint: 
    [2026-11-11T03:53:58+00:00] 192.168.1.13 403 519 554 0.164 "8f8035a9-f517-4a5d-b916-6ec16134f56a"
    "192.168.1.213:18086"
    "GET /ai-cloner-snap/internal_blog/2021-07-16-iqn-level-chap-authentiation-on-solidfire.md HTTP/1.1"
    "192.168.1.211:10443"
```

So, even if the client attempted to deviate from sitemap XML, we'd be fine.

Our content is ready for cloud access.

If you want a more complex workflow, you could add another step, where some compliance dude runs their guardrails and what-have-ya batch-job on the snapshot bucket, and *then* (iff OK), pushes the ACLs. So the `ai-managers` group would only "nominate" and "propose" an ACL on the clone, while `compliance-managers` would effect if approved.

Finally, you need to expose this snapshot from some container. Caddy is recommended for demonstration and lightweight use, but [NGINX+](https://docs.nginx.com/nginx/admin-guide/installing-nginx/installing-nginx-plus/) and possibly others are equally capable:
- Share S3 as HTTP site or proxy S3 access to StorageGRID Load Balancer (depending on your scanner bot), which in turn serves that snapshot bucket. S3 reader should use limited-scope S3 keys for `Read-only Marketing Bot`. For HTTP export of S3 as Web content, the HTTP proxy should use the same user's S3 keys to access the bucket and clients wouldn't need to have the S3 keys.
- Inject the sitemap file on that container (remember, you can't write to the bucket!).
- Let the AI scanner know http://a348ss.cloudaccess.company.com:443/snapshot-20261108T183911Z-1794163151782176684-c94ac7893a15.xml has the goods.
- Make sure this workflow is recorded in SIEM or elsewhere. StorageGRID audit logs should be forwarded and collected as well, if you need to track access for SIEM or compliance.

### About this demo

This demo used [my forked](https://github.com/scaleoutsean/caddy-s3-proxy/) Caddy S3 Proxy which may or may not be out of date (and have CVEs).

As mentioned above, this isn't the only approach - feel free to use other plugins or a different server such as [NGINX+](https://docs.nginx.com/nginx/admin-guide/installing-nginx/installing-nginx-plus/) (strongly recommended for production).

- `env.example` - copy it to `.env` and edit for sitemap filename and StorageGRID S3 credentials
- `Caddyfile.example` - copy it to `Caddyfile` and edit for Proxy's FQDN, SG S3 API endpoint, snapshot bucket name and more
- `docker-compose.yaml` for HTTP(s) reverse proxy; uses `.env` and `Caddyfile`

You may not need all these files. You could, for example, run a self-compiled Caddy (with appropriate extension of your choice) from the CLI.

Some AI engines may be able to enumerate buckets directly, without a Web server proxy. In that case you may even consider using [OpenSharing Volume Tables](https://github.com/scaleoutsean/opensharing-server) instead.