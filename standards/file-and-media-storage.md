# File & Media Storage Standards

## Philosophy

- Object storage is the right place for binary content. The application database is the wrong one — bytes in tables explode backup size, slow snapshots, and make replication painful.
- The bucket is the boundary between trust zones. Public buckets serve assets to the world; private buckets serve sensitive content to the system. They are never the same bucket with "smart access rules" — that pattern leaks one misconfiguration away.
- Direct uploads (browser → object storage via presigned URL) are mandatory at scale. Streaming uploads through the application server is a liability budget being spent on bytes the server does not need to see.
- Content is untrusted input. Every upload is sized, typed and scanned before it becomes addressable. A user-uploaded `.html` served from the same origin as the application is an XSS lab.
- Video is its own discipline. Transcoding pipelines, signed playback, multi-bitrate, captions are not "files with extra metadata" — they need their own state machine and their own ledger.

---

## When this standard applies

This standard applies whenever the system stores user-uploaded or system-generated binary content: profile photos, identity documents, signed contracts, training videos, audio recordings, attachments, exports, generated PDFs.

It does NOT cover the application's own deploy artifacts (Docker images, JS bundles) — those have their own delivery surface (registry, CDN of the build pipeline). It does NOT cover database backups — those are operational concerns, see runbooks.

---

## Vocabulary

| Term | Meaning |
|---|---|
| **Object** | A single binary blob stored under a key in a bucket — `users/{user_id}/avatar/v3.jpg` |
| **Bucket** | A namespace in the object store (S3 bucket, GCS bucket, MinIO bucket, R2 bucket). Per this standard, a bucket is either fully public or fully private — never mixed |
| **Presigned URL** | A short-lived URL that grants a single capability (PUT to upload, GET to download) on a single key. Issued by the backend; consumed by the browser; no further authorization needed |
| **Signed URL** | Synonym for presigned in this standard |
| **CDN** | Edge cache in front of public objects — CloudFront, Cloudflare R2, Fastly, Bunny |
| **Variant** | A derived object generated from an original (thumbnail, transcoded video bitrate, OCR-extracted text). Has its own key; lifecycle pegged to the original |

---

## The bucket layout

A project has at minimum two buckets per environment, named with intent:

```
{project}-public-{env}     -- avatars, course thumbnails, anything safe to cache at the edge
{project}-private-{env}    -- DNI scans, signed contracts, user-uploaded chat attachments, KYC media
```

Optional buckets, when justified:

```
{project}-video-source-{env}     -- raw uploads pending transcoding
{project}-video-output-{env}     -- transcoded outputs, served via signed CDN
{project}-exports-{env}          -- DSAR exports, invoice batches, ephemeral; lifecycle rule to auto-delete after N days
{project}-backups-{env}          -- DB / disaster recovery; managed by infra, not by application code
```

Rules:

- A bucket is public by capital-letter intent — `Public` in the name, plus a bucket policy that allows `s3:GetObject` to anyone. A "public" bucket with PUT open to the world is a defect — uploads always go through presigned URLs.
- A private bucket has zero anonymous permissions. Reads require either a presigned URL minted by the backend or an IAM-authenticated request.
- Cross-bucket access (a piece of code that reads private and writes public on the same call) is acceptable inside a worker, never inside an HTTP handler.
- A "smart" bucket policy that decides public vs private per prefix is forbidden. The misconfiguration risk is too high.

---

## Object keys

Keys are deterministic, hierarchical, and carry the tenant/owner so a single missed permission does not become a cross-tenant leak.

```
users/{user_id}/avatar/{version}.jpg
chats/{thread_id}/{message_id}/{filename}
contracts/{contract_id}/v{version}.pdf
courses/{course_id}/videos/{video_id}/source.mp4
courses/{course_id}/videos/{video_id}/output/720p.mp4
exports/dsar/{user_id}/{request_id}.zip
```

Rules:

- Keys NEVER contain user-supplied filenames at the leaf without sanitization. The system either renames to a known shape (`{message_id}.{ext}`) or url-encodes the original name into a metadata header.
- Keys ALWAYS contain the resource owner identifier (user, tenant, contract). A key that reads `uploads/abc-123.jpg` with no owner context is a bug — when the bucket is misconfigured, anyone who guesses the id reads everything.
- Versioning is in the key (`v3.jpg`) for replaceable artifacts (avatar, signed contract). Object-store native versioning is acceptable for backup purposes; do not rely on it for application semantics.

---

## Upload flow (presigned PUT)

The browser uploads directly to the object store. The application server mints the URL but never sees the bytes.

```
Browser                    Backend                   Object Store
   │  POST /api/v1/uploads  │                              │
   │ ────────────────────► │                              │
   │                        │ Validate purpose, quota,    │
   │                        │ allowed mime types          │
   │                        │ Mint presigned PUT URL,     │
   │                        │ scope=PUT, key, ttl=5m,     │
   │                        │ content-type whitelist,     │
   │                        │ max-bytes                   │
   │ ◄──────────────────── │ { url, key, expires_at }   │
   │                        │                              │
   │  PUT url + bytes       │                              │
   │ ──────────────────────────────────────────────────► │
   │                        │                              │
   │  POST /api/v1/uploads/{key}/finalize                  │
   │ ────────────────────► │                              │
   │                        │ Head-object: verify size +  │
   │                        │ content-type match the      │
   │                        │ presigned constraints       │
   │                        │ Trigger antivirus scan,     │
   │                        │ persist Upload aggregate    │
   │ ◄──────────────────── │ { upload_id }              │
```

Rules:

- The presigned URL is scoped: single key, single method, content-type, max content-length, TTL ≤ 15 minutes (typical 5 minutes).
- The browser never reuses a presigned URL across uploads — new file, new presign.
- The finalize step is mandatory — it confirms the upload landed within the constraints (size + mime). The Upload aggregate transitions from `pending` to `uploaded` only after finalize.
- The Upload aggregate's state never advances past `uploaded` until the antivirus scan returns a verdict.

### Quotas

The backend MUST enforce per-user and per-tenant quotas at presign time. The presign call is the choke point — without it, the only enforcement is bucket size (the bill).

```
quota_remaining = quota_limit - sum(uploads.size_bytes WHERE owner = user_id AND created_at >= window_start)
if requested_size > quota_remaining: 429
```

---

## Download flow (presigned GET, private buckets)

For private content, the application mints a presigned GET URL after authorization. The browser fetches directly.

```php
public function generateDownloadUrl(string $tenantId, string $contractId, Subject $subject): string
{
    $contract = $this->contracts->findById($tenantId, $contractId)
        ?? throw new ContractNotFoundException($contractId);

    if (!$this->voter->canDownload($subject, $contract)) {
        throw new ForbiddenActionException('contract.download', $contractId);
    }

    return $this->storage->presignGet(
        bucket: 'project-private-prod',
        key:    $contract->storageKey,
        ttl:    new \DateInterval('PT5M'),
        responseHeaders: [
            'Content-Disposition' => sprintf('attachment; filename="%s"', $contract->displayName),
        ],
    );
}
```

Rules:

- TTL ≤ 15 minutes for any URL handed to a browser. Background batch downloads MAY use up to 1 hour, documented per use case.
- The Voter (`AZ-001`) runs BEFORE minting the URL. A presigned URL is a capability — handing it to the wrong person bypasses every later check.
- The `Content-Disposition` header is forced to `attachment` for sensitive content (DNI, contract) so the browser does not render it inline. Inline rendering of an attacker-controlled `.html` from the same origin is XSS.
- A presigned URL is NEVER logged at any level (it is a capability with a TTL). It is also NEVER cached — each request mints a fresh one.

---

## Public assets

Public assets (avatars, course thumbnails, marketing images) live in the public bucket and are served via CDN.

Rules:

- The CDN domain is separate from the application origin (`assets.{project}.com`, not `{project}.com/assets/`). This isolates cookie scope (no app cookies sent with asset requests) and prevents an XSS pivot from the assets origin onto the app.
- Cache headers are set at upload time on the object metadata (`Cache-Control: public, max-age=31536000, immutable`). The key contains a version (`avatar/v3.jpg`) so cache invalidation is "publish a new key", not "purge the CDN".
- A public asset never contains PII or sensitive content. The mere act of writing to the public bucket is a classification statement: this is safe to be world-readable.

---

## Antivirus scanning

Every upload to a private bucket is scanned before becoming addressable.

```
Upload finalized → enqueue scan job → ClamAV / VirusTotal / cloud-native scanner
   ├─ clean    → Upload.status = available
   ├─ infected → Upload.status = quarantined; object moved to quarantine bucket; alert SOC
   └─ error    → retry per the queue policy; after retries exhausted → status = scan_failed; manual triage
```

Rules:

- A user-facing handler that reads an Upload checks `status = available` before serving the URL — never serves a `pending`/`scanning`/`quarantined` upload.
- The scan job is async (Symfony Messenger; see backend.md), idempotent, and writes the result via a domain event the Upload aggregate consumes.
- Clean re-scans are scheduled periodically — signature databases evolve, and a file marked clean today may be flagged tomorrow.

---

## Mime type & magic-byte verification

The backend NEVER trusts the content-type sent by the client. After upload, a worker:

1. Reads the first N bytes of the object (HEAD with range, or temp download for the worker).
2. Computes the magic-byte signature.
3. Compares against the allowed set declared at presign time.
4. On mismatch: marks the upload `mime_mismatch`, deletes the object, alerts.

Common attack pattern: presign asks for `image/jpeg`, browser uploads HTML with `Content-Type: image/jpeg`. Without magic-byte verification, the bucket happily stores HTML.

---

## Variants and derivatives

A variant is a derived object whose lifecycle is pegged to the original. The system tracks the parent-child link explicitly:

```sql
CREATE TABLE upload_variants (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    upload_id UUID NOT NULL,                -- the original
    variant_kind TEXT NOT NULL,             -- 'thumbnail_320', 'thumbnail_1080', 'transcode_720p', 'ocr_text'
    bucket TEXT NOT NULL,
    key TEXT NOT NULL,
    bytes BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (upload_id, variant_kind)
);
```

Rules:

- A delete of the original cascades to the variants — the worker that deletes the original enqueues deletes for every variant.
- Variants are regeneratable from the original — the system tolerates losing them. This means variants live in a bucket with shorter retention or no backup, reducing cost.

---

## Video pipeline

Video is its own discipline; the file-storage rules apply but with extra states.

### Upload + transcode flow

```
Source upload → upload_video_source (pending)
              → finalize → status=uploaded
              → transcode job enqueued
              → ffmpeg/ProviderAPI: 240p/360p/720p/1080p + HLS manifest + thumbnails
              → variants persisted (transcode_240p, transcode_720p, …)
              → captions job enqueued (Whisper / provider)
              → variants persisted (captions_es.vtt, captions_en.vtt)
              → Video.status = available
```

Rules:

- The source MUST live in a separate bucket (`{project}-video-source-{env}`) with a lifecycle rule to delete N days after `Video.status = available`. Keeping source forever is expensive and rarely useful; if the project needs it (re-encoding for new bitrates), declare via ADR.
- Output uses HLS (`.m3u8` + segments) by default for browser playback. MP4 progressive download is acceptable for short clips ≤ 60 s; declared per use case.
- Playback URLs are signed (CDN signed cookies for HLS, signed URLs for MP4). Public video is rare; default is signed.
- Thumbnails are generated at known timecodes (1s, 5s, midpoint). The thumbnail variant is independent of the bitrate variant — a video has both.

### Captions

- Captions are first-class variants (`captions_{locale}.vtt`).
- Auto-generated captions are flagged in metadata (`source = 'machine'`, see `i18n.md` translation source attribution); editors may promote to `human`.
- A video without captions in the user's locale falls back per the i18n fallback chain. A video with NO captions in any locale is acceptable but flagged for a11y review.

---

## Cleanup and retention

Storage costs grow forever unless deletion is engineered in.

Rules:

- Every Upload aggregate has a documented retention rule, declared at the spec level and reflected in the inventory if PII (`gdpr-pii.md`).
- Soft-delete + lifecycle: when a user deletes content from the application, the Upload aggregate transitions to `deleted` + `deleted_at`. A nightly job deletes the object N days after that timestamp (default 7), giving a recovery window.
- RTBF (`gdpr-pii.md` Section 17) deletes immediately — no recovery window for content the data subject has demanded gone.
- Orphan detection: a periodic job lists buckets and checks each key has a corresponding Upload row. Orphan keys (in storage but not in the database) are deleted after a 30-day grace period; orphan rows (in the database but missing from storage) flag an incident.

---

## Cross-region & cross-account

When the bucket and the application live in different cloud accounts (a common pattern in multi-tenant SaaS), every cross-account permission is an explicit policy. There is no "wildcard role assumption" — the application's IAM role has the minimum capabilities needed.

Cross-region replication is operational concern (DR), not application concern. A handler does NOT pick the region at runtime.

---

## Observability

| Span attribute | Required | Example |
|---|---|---|
| `storage.bucket` | yes | `project-private-prod` |
| `storage.operation` | yes | `presign_put` / `presign_get` / `head` / `delete` |
| `storage.object_size_bytes` | when known | `2_345_678` |
| `storage.error_class` | on error | `ObjectNotFound` / `AccessDenied` |

NEVER as span attribute: presigned URL, object key (KEY contains owner ids — log it as `storage.object_id_hash` only when needed for debugging).

| Metric | Labels |
|---|---|
| `storage_operations_total` | `bucket`, `operation`, `outcome` |
| `storage_bytes_uploaded_total` | `bucket`, `mime_class` (e.g. `image`, `video`, `pdf`, `other`) |
| `storage_bytes_downloaded_total` | `bucket`, `mime_class` |
| `storage_objects_quarantined_total` | `bucket`, `reason` |
| `video_transcode_duration_seconds` | `output_bitrate`, histogram |
| `video_transcode_failures_total` | `failure_class` |

---

## Anti-patterns (auto-reject in review)

- Storing binary content in a database column (`bytea` for an avatar).
- Streaming an upload through the application server when a presigned PUT is feasible.
- A bucket with anonymous PUT permitted.
- A "smart" bucket policy that decides public vs private per prefix.
- A presigned URL with TTL > 15 minutes for a browser-handed download.
- Trusting the client-supplied `Content-Type` without magic-byte verification.
- Serving a user-uploaded HTML file inline from the application's main origin.
- Logging a presigned URL.
- A user-facing endpoint serving an upload before the antivirus verdict.
- Object keys without an owner identifier.
- Hardcoded bucket names in code (use config + env per environment).

---

## What the reviewer checks

Storage rules are enforced during review via the backend reviewer checklist (see [`backend-review-checklist.md`](backend-review-checklist.md) → "File & media storage") and the frontend reviewer checklist (see [`frontend-review-checklist.md`](frontend-review-checklist.md) → "File & media storage"). The checklists are the authoritative surface — if a rule appears here and not in the checklist, file a minor and update the checklist in the same commit.
