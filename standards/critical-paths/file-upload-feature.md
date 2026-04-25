# Critical path — File / media upload feature

Use when the diff accepts user-uploaded files, serves system-generated documents, or wires a video pipeline. Combine with [`auth-protected-action.md`](auth-protected-action.md) for any private-bucket access.

## Backend

### Storage shape
- FS-001 Binary content lives in object storage, NOT in DB columns
- FS-002 Buckets either fully public OR fully private — never mixed via prefix policies
- FS-003 Public buckets disallow anonymous PUT — uploads via presigned URLs
- FS-004 Object keys contain the owner identifier
- FS-005 User-supplied filenames sanitised — system renames at the leaf
- FS-021 Bucket names env-config; never hardcoded

### Upload flow
- FS-006 Presigned URLs scoped (single key, method, content-type whitelist, max-bytes); TTL ≤ 15 min for browser
- FS-007 Quotas enforced at presign time
- FS-008 Upload aggregate state machine: pending → uploaded → scanning → available / quarantined / scan_failed / mime_mismatch
- FS-011 Magic-byte verification after upload — client `Content-Type` never trusted
- FS-012 Async antivirus scan; periodic re-scans

### Download flow (private bucket)
- FS-009 Voter (AZ-001) runs BEFORE minting any private-bucket presigned GET
- FS-010 `Content-Disposition: attachment` for sensitive private downloads
- FS-022 Presigned URLs NEVER logged

### Variants & lifecycle
- FS-013 Variants tracked in `upload_variants`; delete-original cascades; variants in shorter-retention bucket
- FS-017 Soft-delete + lifecycle delete after N days; RTBF deletes immediately
- FS-018 Orphan detection nightly; orphan keys deleted after 30-day grace; orphan rows trigger incident

### Video pipeline (when applicable)
- FS-014 Video sources in separate bucket with lifecycle delete after `Video.status=available`
- FS-015 Video playback URLs signed by default
- FS-016 Captions as first-class variants per locale (i18n source attribution)

### Observability
- FS-019 Span attributes: `storage.bucket`, `storage.operation`, `storage.object_size_bytes`, `storage.error_class` — NEVER full key or presigned URL
- FS-020 Metrics bounded by bucket / operation / outcome / mime_class / failure_class

### Hard blockers
- BE-001 Quality gates green
- SC-001 No secrets committed (storage credentials in `secrets-manifest.md`)

## Frontend (when uploading from UI)

- FS-023 Use the presigned PUT flow (`POST /uploads` → upload directly → `POST /uploads/:key/finalize`); never stream bytes through the API
- FS-024 Presigned URLs consumed once; never stored in localStorage / sessionStorage / Pinia
- FS-025 Image / video tags pointing at private content fetch a fresh signed URL on render
- FS-026 Forms enforce `accept`, max-size, visible error states

## What this path does NOT cover

- Authorization → [`auth-protected-action.md`](auth-protected-action.md) (mandatory for private buckets)
- PII metadata associated with the upload → [`pii-write-endpoint.md`](pii-write-endpoint.md)
- Signed-document storage → [`signature-feature.md`](signature-feature.md) (different retention rules)
- Service-worker caching of media → [`pwa-surface.md`](pwa-surface.md)
