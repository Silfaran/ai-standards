# Critical path — PII-writing endpoint

Use when the diff stores or updates personal data of a user (registration, profile edit, KYC submission, document upload that carries PII metadata). Always combine with [`auth-protected-action.md`](auth-protected-action.md).

## When to load this path

**PRIMARY trigger** (load this path as core when):
- A new column whose tier is Internal-PII or Sensitive-PII (per `gdpr-pii.md` classification)
- A new row in `{project-docs}/pii-inventory.md`
- A new endpoint that writes/updates personal data (registration, profile edit, KYC submit, consent change)
- A new sub-processor SDK integrated in code (must update `pii-inventory.md` in same commit)

**SECONDARY trigger** (load only when no primary path covers the diff already):
- An update to `LoggingMiddleware::SENSITIVE_FIELDS` or the redaction list
- A consent UI component on the frontend
- A new DSAR / RTBF endpoint or worker

**DO NOT load when**:
- The diff only modifies tests
- The diff only modifies `*.md`
- The personal data is exclusively contained inside an uploaded file (load `file-upload-feature.md` instead — handles file metadata classification)

## Backend

### PII classification & storage
- GD-001 Every new PII column has a row in `{project-docs}/pii-inventory.md`
- GD-002 Sensitive-PII columns encrypted at rest via `SensitivePiiCipher`
- GD-003 Sensitive-PII never in list-endpoint projections; masked by default
- GD-004 Decryption emits `event=pii.access` audit (value never logged)
- GD-005 PII never in URLs / query / headers / errors / spans / metric labels / log lines
- GD-006 New PII field triggers same-commit update of `logging.md` redaction list
- GD-007 Hash-based dedup uses peppered hash (`PII_DEDUP_PEPPER`)
- GD-008 Repository projections (`SELECT id, display_name`) never `SELECT *`

### DSAR / RTBF coverage
- GD-009 `DsarExportService` test fixture includes the new field if `dsar_export=yes`
- GD-010 `ForgetUserCommand` reads inventory at runtime
- GD-013 No prod → non-prod copies without redaction pipeline

### Sub-processors
- GD-011 New SDK integrations have a sub-processor row in the inventory
- GD-012 Consent-gated processing queries `ConsentLedger` before any work

### Logging hard blocker
- LO-001 No unredacted sensitive fields in logs

### Audit
- AU-006 Audit write in same DB transaction as state change
- AU-007 Entries on success and denial

### High-risk processing
- GD-014 DPIA threshold check; spec linked to a completed DPIA when relevant

## Frontend (when collecting PII)

- GD-015 PII never in URL paths / query / hash / `localStorage`
- GD-016 Sensitive-PII forms use `autocomplete="off"` + single TLS submit (no multi-step localStorage drafts)
- GD-017 Consent UI presents one consent per purpose
- GD-018 Consent withdrawal reachable in ≤2 clicks; effective immediately
- GD-019 Analytics / observability calls carry hashed `user_id` only
- IN-016 `Accept-Language` header set on Axios instance for the active locale
- AZ-014 UI gating presentation-only; backend re-checks

## Coverage map vs full checklist

This path covers these sections of `backend-review-checklist.md` / `frontend-review-checklist.md`:

- §GDPR / PII — GD-001..GD-014 (classification, encryption, DSAR/RTBF, sub-processors, consent, DPIA)
- §Logging hard blocker — LO-001 (the redaction baseline)
- §Audit — AU-006, AU-007 (entry on success and denial)
- §Frontend PII collection — GD-015..GD-019 + IN-016 + AZ-014

This path does NOT cover. Load the corresponding checklist section ONLY when the diff touches:

- `tests/` directory → load §Testing
- `LoggingMiddleware::SENSITIVE_FIELDS` field redaction patterns → load §Logging (LO-002..LO-007)
- New encrypted column at the schema level → load §Database + §Migrations (DM-*)
- Consent UI redesign beyond the GD-017..GD-018 minimum → load §Frontend UX states

## What this path does NOT cover

- Authorization decisions → [`auth-protected-action.md`](auth-protected-action.md) (always required)
- The CRUD scaffolding → [`crud-endpoint.md`](crud-endpoint.md)
- PII inside file uploads (DNI scans, contracts) → [`file-upload-feature.md`](file-upload-feature.md)
- PII inside LLM prompts → [`llm-feature.md`](llm-feature.md) (PiiPromptGuard mandatory)
