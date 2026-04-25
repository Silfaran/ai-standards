# GDPR / Personal Data (PII) Standards

## Philosophy

- Personal data is a liability before it is an asset. Every field stored is a future obligation: to expose it on request, to delete it on request, to prove who accessed it.
- Classify the data, then design the storage. Encryption, retention, masking and audit decisions follow from classification, not the other way around.
- The right to be forgotten is a workflow, not a SQL `DELETE`. Some data the law requires you to keep (invoices, signed contracts), some downstream systems hold copies, some derived data has to be recomputed. Plan for it before you accept the first sign-up.
- Distinguish "secret" from "personal". `secrets.md` covers values whose leak changes the security posture (API keys, signing keys). This standard covers values that identify a person — they may be in plaintext in logs at the moment they are leaked, and the impact is to that person, not to the system.
- Boundary cases resolve toward the stricter rule: when in doubt, treat the field as PII-sensitive.

---

## When this standard applies

This standard applies the moment the system stores ANY of:

- A direct identifier of a natural person (name, email, phone, government ID, photo, voice recording)
- A pseudonymous identifier the system can link back to a person (`user_id` with the user table available)
- Any of the GDPR "special categories" (health, biometrics, ethnicity, religion, sexual orientation, political views, union membership, criminal records)
- Behavioural data tied to an identifier (search history, clickstream, IP-derived geolocation linked to an account)

Operating on EU/EEA users brings GDPR; operating on UK users brings UK GDPR; California brings CCPA/CPRA; Brazil brings LGPD. The technical patterns in this standard are largely the same; the legal articles cited are GDPR, but the architecture is portable.

---

## Vocabulary

| Term | Meaning |
|---|---|
| **Personal data** | Any information about an identified or identifiable natural person (GDPR Art. 4(1)) |
| **PII** | Synonymous with personal data in this standard. The acronym is used everywhere; the rules are GDPR-aligned |
| **Special category** | The GDPR-restricted classes above. They require an additional legal basis and stricter controls |
| **Data subject** | The natural person to whom personal data refers — typically a user, sometimes a third party (a contact in a contract) |
| **Controller / Processor** | Controller decides why and how data is processed; Processor processes on the controller's behalf. Most products are Controllers for their users and Processors for their B2B customers' end users |
| **Subject Access Request (SAR)** | A request from a data subject to access, export, rectify or delete their data — GDPR Articles 15–17 |
| **Right To Be Forgotten (RTBF)** | The deletion variant of SAR (Article 17) — with documented carve-outs |
| **DPIA** | Data Protection Impact Assessment — required for high-risk processing (Article 35) |

---

## Classification (the four-tier model)

Every personal-data field in the codebase MUST be classified. Classification is recorded in the `pii-inventory.md` document at the same path as `secrets-manifest.md` (`{project-docs}/pii-inventory.md`).

| Tier | What it covers | Storage rule | Logging rule | Retention default |
|---|---|---|---|---|
| **Public** | Data the user has chosen to publish (a public profile bio, a published review with their display name) | Plaintext, indexable | May appear in logs | Until user removes |
| **Internal-PII** | Identifiers and contact data needed for the service to function (email, name, phone, postal address, account preferences) | Plaintext, indexed; access audited; backups encrypted at rest | Redacted in logs (display only the hashed `user_id`); never in URLs/headers | Account lifetime + legal retention |
| **Sensitive-PII** | Data whose leak causes direct harm (government ID, payment instrument tail, precise geolocation, biometric template, health, sexuality, political/religious data) | Column-level encryption (`pgcrypto`); access logged per row; never returned in list endpoints | Never in logs at any level | Minimum legally required; specific TTL declared |
| **Derived/Pseudonymous** | Aggregates and identifiers derived from PII (a user's K-anonymized cohort id, a hashed email used as a dedup key) | Plaintext; documented derivation function | May appear in logs as the pseudonym, never with the inverse | As needed for the use case |

A field that does not fit a tier defaults to `Internal-PII`. Promotion to `Sensitive-PII` is recorded in the inventory; demotion is forbidden — once a field is sensitive, the rule does not relax.

### Examples

| Field | Tier |
|---|---|
| `users.email` | Internal-PII |
| `users.display_name` (public profile) | Public |
| `users.password_hash` | Internal-PII (it identifies an account; not a secret per `secrets.md` because the hash is the value, not a recoverable credential) |
| `users.tax_id` (DNI/NIE/SSN) | Sensitive-PII |
| `professionals.bio` (user-published) | Public |
| `chat_messages.body` | Internal-PII (default; could be Sensitive depending on product) |
| `geolocation_pings.lat,lng` (precise, repeated) | Sensitive-PII |
| `audit_logs.user_id` | Internal-PII |
| `analytics_events.cohort_id` (k>=20) | Derived/Pseudonymous |

---

## The PII inventory document

`{project-docs}/pii-inventory.md` is the single source of truth. The reviewer rejects any diff that introduces a column matching a PII pattern without a corresponding row.

Each row:

| Field | Meaning |
|---|---|
| `field` | Fully qualified `table.column` (`users.email`, `chat_messages.body`) |
| `tier` | One of the four tiers above |
| `legal_basis` | GDPR Art. 6 basis: `contract`, `consent`, `legitimate_interest`, `legal_obligation`, `vital_interest`, `public_task` |
| `purpose` | One short sentence: why the system stores this |
| `retention` | Active retention rule (`account_lifetime + 6 years`, `30 days`, `until consent withdrawn`) |
| `processors` | Sub-processors that receive the field (`Stripe`, `SendGrid`, `OpenAI`); empty if none |
| `dsar_export` | Field included in DSAR data export (`yes` / `no` with reason) |
| `rtbf_action` | On RTBF: `delete` / `anonymize` / `retain (legal)` with the article cited |

A new column with PII content + no inventory row = hard reject, same severity as a missing secret in the manifest.

---

## Storage patterns

### Internal-PII

Stored plaintext in the operational database. Backups encrypted at rest by the platform. Indexes allowed (the system needs to look up users by email).

Rules:

- The column MUST NOT appear in `SELECT *` API responses for unrelated endpoints. Repository methods enforce projection (`SELECT id, display_name FROM users` for a public listing; never `SELECT * FROM users` then filter in PHP).
- Foreign references use the surrogate key (`user_id UUID`), never the email or phone.
- Hash-based deduplication uses a peppered hash (`crypt_hash(email_lower, $pepper)`); the pepper lives in `secrets.md` as `PII_DEDUP_PEPPER`.

### Sensitive-PII

Stored with column-level encryption. The encryption key lives in `secrets.md` as `PII_ENCRYPTION_KEY` (rotated per its policy); the column type is `BYTEA` and reads/writes go through a single Application service.

```sql
-- Migration: add the encrypted column
ALTER TABLE users ADD COLUMN tax_id_encrypted BYTEA;
-- Search by partial value uses a separate, peppered hash column for equality match
ALTER TABLE users ADD COLUMN tax_id_hash BYTEA;
CREATE UNIQUE INDEX idx_users_tax_id_hash ON users (tax_id_hash);
```

```php
namespace App\Application\Service\Privacy;

final readonly class SensitivePiiCipher
{
    public function __construct(
        #[Autowire('%env(PII_ENCRYPTION_KEY)%')]
        private string $key,
    ) {}

    public function encrypt(string $plaintext): string
    {
        // libsodium AEAD; key from secrets manifest
        return sodium_crypto_secretbox(
            $plaintext,
            random_bytes(SODIUM_CRYPTO_SECRETBOX_NONCEBYTES),
            $this->key,
        );
    }

    public function decrypt(string $ciphertext): string
    {
        // ... reverse, with constant-time comparisons
    }
}
```

Rules:

- Sensitive-PII columns NEVER appear in `SELECT` projections of list endpoints. Detail endpoints SHOULD return the value masked (`****1234`) unless the caller has an explicit "view sensitive" permission (Voter rule; see `authorization.md`).
- Every read of the decrypted value is logged with `event=pii.access`, `field`, `subject_id`, `actor_id`, `purpose`, `trace_id`. The read is auditable; the value is NEVER logged.
- A column that is `Sensitive-PII` per the inventory but NOT encrypted at rest is a hard reject.
- Sensitive-PII MUST NOT cross service boundaries unless the boundary call is justified by a documented purpose (the inventory's `processors` list).

### Backups and disaster recovery

Backups inherit the classification of the data they contain. Backup retention follows the strictest retention rule of any field in the snapshot. A backup SHOULD NOT contain Sensitive-PII unless it is used for disaster recovery of the same field — analytics or staging restores from prod backups MUST first run a redaction pipeline.

---

## Logs, traces, metrics

PII rules in observability are stricter than secret rules:

| Channel | Internal-PII | Sensitive-PII |
|---|---|---|
| Logs | Hashed pseudonym only (`user_id`) — never email, phone, tax_id, body | Never, at any level |
| Traces | `subject_id` as a span attribute — never display names, contact data | Never |
| Metrics | Never as a label (high-cardinality + leakage). Aggregate counts only | Never |
| URLs / Query strings | Never (URLs are logged, cached, in Referer headers) | Never |
| Error responses to clients | Never | Never |

The redaction list in `logging.md` MUST cover every field in the inventory whose tier is `Internal-PII` or `Sensitive-PII`. A new PII field added to the inventory triggers a same-commit update of the redaction list. See `secrets.md` SC-010 for the precedent pattern.

---

## Subject access requests (SAR / DSAR)

The product MUST be able to honour, within the legal deadline (one month for GDPR, extendable once):

| Right | What the product produces |
|---|---|
| **Access** (Art. 15) | A machine-readable export of all PII fields the data subject's `user_id` appears in. Format: JSON, one file per entity type, plus a manifest |
| **Rectification** (Art. 16) | An interface or admin tool to correct the user's stored data. Free-text fields update via the normal write path; immutable fields (an invoice's name) require an explanation |
| **Erasure / RTBF** (Art. 17) | The RTBF workflow described below |
| **Restriction** (Art. 18) | A flag on the user record that suppresses processing (no marketing, no derived analytics) without deleting; rare, but the system MUST support it |
| **Portability** (Art. 20) | The same export as Access, in a structured, commonly-used, machine-readable format |
| **Objection** (Art. 21) | A consent withdrawal flow per consent-driven processing purpose; documented per `legal_basis = consent` |

The export is generated by a `DsarExportService` that walks the inventory: for each row with `dsar_export = yes`, it dumps the data subject's records. The service runs as an async job; the user gets a download link with a 7-day TTL via signed URL (see `file-and-media-storage.md`).

A DSAR test fixture exists: a synthetic user is seeded, the export job runs, and the test asserts every inventory row marked `dsar_export = yes` is non-empty in the export. A field added to the inventory without being included in the export is a defect.

---

## Right to be forgotten (RTBF)

RTBF is the destructive workflow. It runs through a single command handler (`ForgetUserCommand`) and follows three phases:

### Phase 1 — Identify carve-outs

Some data MUST be retained even after RTBF. The `rtbf_action` column of the inventory enumerates them:

| Action | When | Result |
|---|---|---|
| `delete` | No legal/contractual reason to keep | Row hard-deleted from the operational DB |
| `anonymize` | Statistical or aggregate value, no need for the identifier | Identifying columns nulled or replaced with stable pseudonym; row remains for analytics |
| `retain (legal: <article>)` | Tax law (4–6 years), insurance (10 years for liability), AML, court order | Row remains; access locked behind a "retained-only" permission; audit trail continues |

The handler reads the inventory at runtime — the inventory is the authoritative source, not a hardcoded list per service.

### Phase 2 — Execute

The handler walks the data subject's records aggregate by aggregate, applying the action declared per field. Every action emits an audit-log entry (`event=privacy.rtbf.applied`, `field`, `action`, `subject_id`, `actor_id`).

Side effects:

- Sub-processors with copies receive a deletion request via their API. The request is recorded with `processor`, `request_id`, `requested_at`. Confirmation polled or webhook-received.
- Derived datasets (analytics warehouses, search indexes, ML training sets) get a deletion event on the privacy event bus; downstream consumers MUST honour it within the documented SLA (e.g. nightly).

### Phase 3 — Verify

After execution, an automated check runs the same scan as the DSAR export and asserts that every `delete`/`anonymize` field is either gone or anonymized. Any residual triggers an incident (`SEV-2`) — the user has been told their data is gone; the system must back the claim.

### What RTBF does NOT do

- Erase encrypted backups older than the next backup-rotation cycle. The backup is destroyed when its retention expires; until then, encryption + key rotation make the backup effectively inaccessible.
- Erase data the user posted in shared spaces (a comment thread, a community board) — the comment is anonymized (display name replaced with "Deleted user"), not necessarily deleted, depending on product policy. Documented per surface.
- Erase data the user is currently in dispute over (active billing dispute, criminal investigation request). The retention is the law's default; the lift is the law's clearance.

---

## Sub-processors and data residency

Every external service that processes PII on behalf of the controller is a sub-processor. The inventory lists them per field; the product maintains a public sub-processor list at the project's privacy URL.

Rules:

- A new sub-processor (Stripe, SendGrid, OpenAI, Twilio…) is added to the inventory in the same commit that introduces the integration. Reviewer rejects otherwise.
- Sub-processor data residency is recorded: where their servers are. EU-only deployments restrict to EU-region sub-processors or sub-processors with valid SCC/Adequacy.
- LLM sub-processors are doubly sensitive — a prompt that contains a user's chat is exfiltrating PII to the model. See `llm-integration.md` for the per-call PII guard.

---

## Consent

When the legal basis for a processing purpose is `consent`, the system MUST:

- Record the consent event with `subject_id`, `purpose`, `granted_at`, `policy_version` (the version of the privacy policy in force at consent time).
- Provide a withdrawal interface that produces a `consent_withdrawn` event with the same shape and `withdrawn_at`.
- Stop the processing within the documented SLA on withdrawal — no "next batch" excuse.
- Block the processing entirely until consent is granted; consent is opt-in.

A `ConsentLedger` aggregate stores these events. It is the primary input to the marketing system, the ML opt-in, the analytics opt-in, and any other consent-gated path. The handler that initiates a consent-gated process MUST query the ledger first; bypassing it is a hard reject.

---

## DPIA (Data Protection Impact Assessment)

A DPIA is required when the processing is high-risk (Art. 35). High-risk patterns relevant to web products:

- Systematic monitoring of public spaces (geolocation, biometric)
- Large-scale processing of special categories
- Automated decision-making with legal or significant effect (e.g. credit, hiring, eligibility scoring)
- New technologies whose privacy implications are not yet established (LLM-driven personalization is a candidate today)

The template lives at [`templates/dpia-template.md`](../templates/dpia-template.md). A feature that crosses a high-risk threshold MUST have a completed DPIA filed in `{project-docs}/dpia/` before merging the implementation. The reviewer checks: spec → DPIA → implementation, in that order.

---

## Anti-patterns (auto-reject in review)

- A new column whose name or content is PII, with no row in `pii-inventory.md`.
- A `Sensitive-PII` field stored in plaintext, or with a `text` column type, or returned in a list endpoint.
- An email, phone or tax id appearing in a URL path, query string, log line, error message, or span attribute.
- Hardcoding a sub-processor (a `new \Stripe\StripeClient(...)`) without an inventory entry naming Stripe as a processor of the affected fields.
- A "soft delete" implementation that does not address RTBF — a tombstoned row that still contains PII is not RTBF.
- A logging middleware that does not consult the redaction list (or uses a stale copy of it).
- An LLM call whose prompt is built from raw user data without classification (see `llm-integration.md`).
- A backups job that copies prod to staging without redaction.
- A "consent everywhere" flow that does not actually gate the processing — checkbox without effect.

---

## What the reviewer checks

Privacy rules are enforced during review via the backend reviewer checklist (see [`backend-review-checklist.md`](backend-review-checklist.md) → "Personal data (PII) & GDPR") and the frontend reviewer checklist (see [`frontend-review-checklist.md`](frontend-review-checklist.md) → "Personal data (PII) & GDPR"). The checklists are the authoritative surface — if a rule appears here and not in the checklist, file a minor and update the checklist in the same commit.

## Automated drift detection

`scripts/project-checks/check-pii-inventory-drift.sh` fails CI when the codebase imports a known sub-processor SDK (Stripe, OpenAI / Anthropic, SendGrid / Twilio, Signaturit / DocuSign, Mapbox, …) without a matching entry in `{project-docs}/pii-inventory.md`. The provider list is curated per project in the script header. See [`quality-gates.md`](quality-gates.md) → "Drift validators (consuming projects)".
