# Changelog

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
