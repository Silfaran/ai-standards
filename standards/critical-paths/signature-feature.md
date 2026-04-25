# Critical path — Digital signature feature

Use when the diff initiates, observes (webhook), or verifies a legally binding digital signature. Always combine with [`auth-protected-action.md`](auth-protected-action.md) and [`file-upload-feature.md`](file-upload-feature.md) (signed documents land in the private bucket).

## Backend

### Gateway seam
- DS-001 Every signing operation goes through `SignatureGatewayInterface` — no provider SDK imports

### Modality
- DS-002 Modality (`simple` / `advanced` / `qualified`) declared per use case + jurisdiction in `decisions.md`; never silent downgrade

### Templates
- DS-003 Templates as classes with `KEY` + `VERSION` constants; old versions retained forever; live edits forbidden
- DS-004 Multi-language templates per locale (i18n.md selects variant)
- DS-005 Template binary pinned by hash in `metadata.json` AND in every signing record

### State machine
- DS-006 `SigningRequest` aggregate enforces state machine; CHECK constraint mirrors states
- DS-007 Re-signing creates a NEW SigningRequest; signed documents are immutable

### Storage
- DS-008 On completion, signed PDF + audit-trail PDF stored in private bucket (FS-002); system records its own `document_sha256` independent of provider
- DS-009 Retention exceeds RTBF window for legal documents (gdpr-pii.md Section 17 carve-outs)

### Webhooks
- DS-010 Verify provider signature on RAW body BEFORE parsing
- DS-011 `processed_signature_webhooks` dedup; insert in same DB tx as state change
- DS-012 Out-of-order tolerance: handlers check current aggregate state

### Sub-processor
- DS-013 Provider declared in `pii-inventory.md` (GD-011) at integration time

### Audit
- DS-014 Audit entries on send / completed / declined / expired / cancelled / reminder.sent

### Privacy of signer data
- DS-015 Signer emails NEVER added to marketing lists — consent ledger says no

### Authorization
- DS-016 `canInitiateSigning` and `canVerifySignedDocument` Voters
- DS-017 Verification audit-trail URL is presigned (FS-009/FS-010), TTL ≤ 15 min

### Observability
- DS-018 Span attributes: provider / purpose / template_version / modality / signer_count / outcome — NEVER signer email / national ID / contract amounts
- DS-019 Metrics bounded by provider / purpose / modality / outcome / decline_reason / error_class

### Secrets
- DS-020 `SIGNATURE_PROVIDER_WEBHOOK_SECRET` in `secrets-manifest.md` with rotation; integration tests behind `@group signature-real`

### Hard blockers
- BE-001 Quality gates green
- SC-001 No secrets committed

## Frontend (when signing surfaces touch UI)

- DS-021 Signing UI presents the document for review BEFORE sending
- DS-022 Pending-signature UX shows explicit state + timestamps; no silent loading
- DS-023 Signed documents downloaded via presigned URL with `attachment` disposition
- DS-024 Verification surface displays both system `document_sha256` AND provider audit-trail link

## What this path does NOT cover

- Authorization → [`auth-protected-action.md`](auth-protected-action.md) (mandatory)
- The private-bucket storage rules → [`file-upload-feature.md`](file-upload-feature.md)
- PII fields on the signer → [`pii-write-endpoint.md`](pii-write-endpoint.md)
