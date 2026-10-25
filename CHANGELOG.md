# Changelog

## [0.6.1] - 2026-10-26

- Changed: 3rd party updates (Go and 3rd party dependencies including security updates) in `sg-cosi`:
  - Vulnerability #1: GO-2026-6617: HTTP/2 server crash due to HPACK encoder race in net/http
  - Vulnerability #2: GO-2026-6612: Double flow control refund on HTTP/2 server streams in net/http
  - Vulnerability #3: GO-2026-6611: Excessive CPU consumption from repeated initial window changes in net/http
  - Vulnerability #4: GO-2026-6610: HTTP/2 transport accepts malformed framing-related headers in net/http
  - Vulnerability #5: GO-2026-6603: HTTP/2 server memory exhaustion due to Trailer headers in net/http

## [sgii-0.1.0] - 2026-10-20

- New: updated, improved (new commands), documentation
- Changed: Go 1.27.2 and CVE fixes for 3rd party dependencies:
  - Vulnerability #1: GO-2026-6617: HTTP/2 server crash due to HPACK encoder race in net/http
  - Vulnerability #2: GO-2026-6612: Double flow control refund on HTTP/2 server streams in net/http
  - Vulnerability #3: GO-2026-6611: Excessive CPU consumption from repeated initial window changes in net/http
  - Vulnerability #4: GO-2026-6610: HTTP/2 transport accepts malformed framing-related headers in net/http
  - Vulnerability #5: GO-2026-6603: HTTP/2 server memory exhaustion due to Trailer headers in net/http

## [0.6.0-sgii] - 2026-10-09

- Changed: no changes to COSI functionality, binary or documentation - please use v0.6.0
- New: SGII (StorageGRID Incremental Inventory), stand-alone utility for creation of StorageGRID read-only snapshots, inventory and report generation (try `sgi -h`)

### [0.6.0] - 2026-09-21

- Support exact RFC3339 `expiresAt` values for StorageGRID S3 access keys while retaining the existing `validDays` parameter
- Add an opt-in alpha `SnapshotLease` controller for bounded StorageGRID snapshot sources, stable AccessKey credentials, manual renewal, and ordered automatic cleanup

## [0.5.3] - 2026-07-14

- Update Go to 1.26.5

## [0.5.2] - 2026-06-21

- Two supported workflows (Browfield with existing regular bucket, Greenfield with read-only snapshot bucket)
- Update documentation and examples

## [0.5.0] - 2026-06-08

- Initial release with support for Bucket Access operations
