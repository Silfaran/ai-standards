# Digital Signature Integration Standards

## Philosophy

- A digital signature is a legal artifact. The bytes the user sees, the bytes the signer commits to, and the bytes the system stores MUST be byte-identical — any drift undermines the signature's value in a dispute.
- The signature provider (Signaturit, DocuSign, Adobe Sign, Dropbox Sign, Yousign, …) is a sub-processor for the document and the signer's data. It is in `pii-inventory.md` per `gdpr-pii.md` GD-011 from day one.
- Templates belong to the system, not to the provider. The provider renders them; the system owns versions, language variants, fields, and the audit trail of when each version was effective.
- Signing is asynchronous. The user clicks "send"; the signer receives a notification, signs from their device, the system observes a webhook. The handler that initiates is NOT the handler that confirms.
- Replay-attack resistance is non-negotiable. A signed document is immutable; a re-signing of "the same document" is a NEW signed document, with a new id, a new timestamp, a new audit entry.

---

## When this standard applies

This standard applies whenever the system needs a legally binding signature on a document: contracts (employment, service, mercantile, NDA), consent forms (medical, research), terms of service acceptance with legal weight, B2B agreements, regulatory filings.

It does NOT cover:
- TOS click-through that the project records as a `consent.granted` audit entry without a signed PDF — that's `gdpr-pii.md` consent ledger territory.
- Webhook signature verification (the cryptographic check on incoming PSP webhooks) — that lives in `payments-and-money.md` PA-006.
- API request signing (HMAC on outgoing service-to-service calls) — that's `security.md` territory.

---

## Vocabulary

| Term | Meaning |
|---|---|
| **Signature provider** | The third-party service that handles the legal signing flow (eIDAS-qualified, ESIGN-Act-compliant, etc.) |
| **Signing modality** | The level of legal weight: `simple` (click + IP), `advanced` (signer authentication + tamper-evident PDF), `qualified` (eIDAS QES with national ID) |
| **Template** | A versioned, parameterised document the system owns; rendered to a final PDF per signing |
| **Signing request** | A live signing operation: the document, the signer set, the modality, the deadline. Has a state machine |
| **Audit trail** | The provider-issued log proving who signed what, when, from where (often a separate PDF appended to the signed document) |
| **Hash chain** | The cryptographic fingerprint of the signed document recorded by the system, independent of the provider, for verification without provider lock-in |

---

## Choosing a modality (per use case, per jurisdiction)

The standard recognises three modalities. The choice is recorded in `{project-docs}/decisions.md` per use case AND per jurisdiction:

| Modality | What it requires | Use cases |
|---|---|---|
| **Simple** | Signer's intent + IP + timestamp | Internal acknowledgements, low-stakes acceptance |
| **Advanced** | Signer authentication (SMS code, email link) + tamper-evident PDF + provider audit trail | Service contracts, employment offers, NDAs |
| **Qualified (QES)** | National eID (DNIe in ES, Smart-ID, FNMT, etc.); legal equivalent of a handwritten signature in EU per eIDAS | Regulatory filings, certain employment contracts in regulated sectors, financial commitments |

A use case never silently downgrades modality. A contract that demands `advanced` MUST NOT fall back to `simple` "because the signer's phone died" — the signing is parked, the user is informed.

---

## The `SignatureGatewayInterface` (canonical seam)

Every signing operation goes through an interface defined in the Domain layer. Adapters per provider live in Infrastructure. Handlers depend on the interface only.

```php
namespace App\Domain\Signature;

interface SignatureGatewayInterface
{
    /** @throws SignatureProviderUnavailableException */
    public function sendForSigning(SigningRequest $request): SigningRequestResult;

    /** @throws SignatureProviderUnavailableException */
    public function fetchSignedDocument(string $providerRequestId): SignedDocument;

    /** @throws SignatureWebhookInvalidException */
    public function parseWebhook(string $rawBody, string $signatureHeader): SignatureWebhookEvent;

    public function cancel(string $providerRequestId, string $reason): void;
}

final readonly class SigningRequest
{
    /**
     * @param list<Signer> $signers
     * @param list<TemplateField> $fields  // values to inject into the template
     */
    private function __construct(
        public string $purpose,                    // 'employment_contract', 'nda', 'consent_research'
        public string $templateKey,
        public string $templateVersion,
        public string $modality,                   // 'simple' | 'advanced' | 'qualified'
        public array $signers,
        public array $fields,
        public string $locale,                     // signer-facing locale (i18n.md)
        public ?\DateTimeImmutable $deadline = null,
        public ?string $callbackUrl = null,
    ) {}
}
```

Rules:

- The interface lives in `src/Domain/Signature/`. Provider adapters in `src/Infrastructure/Signature/{Provider}SignatureGateway.php`.
- The Domain interface NEVER mentions the provider name, an SDK type, or a transport detail. Migrating from Signaturit to DocuSign is a one-line wiring change.
- Handlers depend on the interface; tests mock it; integration tests run behind a `@group signature-real` annotation with a daily budget.
- The `purpose` is bounded (constant or enum) — it drives observability labels (cardinality bound).

---

## Templates (the system owns them)

A template is a class plus a binary (PDF or HTML-template that renders to PDF). Both versioned together.

```php
namespace App\Domain\Signature\Template;

final readonly class EmploymentContractTemplate
{
    public const KEY = 'employment_contract';
    public const VERSION = 'v5';

    /** @param array<string, scalar> $fields */
    public function fields(EmploymentContractData $data): array
    {
        return [
            'employee_name'   => $data->employeeName,
            'employer_name'   => $data->employerName,
            'start_date'      => $data->startDate->format('Y-m-d'),
            'monthly_salary'  => sprintf('%s %s', $data->salary->amountMinor / 100, $data->salary->currency),
            'collective_agreement' => $data->collectiveAgreement,
            // ...
        ];
    }

    public function modality(): string { return 'advanced'; }
    public function deadlineDays(): int { return 14; }
}
```

Storage layout:

```
templates/signature/
  employment_contract/
    v3/
      template.pdf            # the form with field anchors
      metadata.json           # the field schema, the modality, the language
    v4/
      template.pdf
      metadata.json
    v5/                       # current
      template.pdf
      metadata.json
```

Rules:

- Versions are append-only: `v3`, `v4`, `v5`. Old versions stay forever — a contract signed under `v3` MUST be rendered as `v3` for any reprint or audit.
- The active version is declared in code (the `VERSION` constant). Bumping the version is a code change reviewed like any other; a "live" content edit is forbidden.
- Multi-language templates: one template per locale (`v5/es/template.pdf`, `v5/en/template.pdf`). The signer's locale (per `i18n.md`) selects the variant.
- A template is binary-pinned per version: a hash recorded in `metadata.json` AND in the database row for every signing — drift detection guards against accidental edits.

---

## SigningRequest aggregate (state machine)

```
draft → sent → in_signing → completed
   │      │         │
   │      │         └─► declined / expired / revoked
   │      │
   │      └─► cancelled (sender pulled it before signers acted)
   │
   └─► failed_to_send
```

Rules:

- The aggregate enforces transitions; the database `CHECK` constraint mirrors the allowed states (per the precedent in `payments-and-money.md` PA-012).
- `completed`, `declined`, `expired`, `revoked` are terminal. A re-signing of "the same document" is a NEW SigningRequest with its own id.
- `failed_to_send` is the result of a `SignatureProviderUnavailableException` at send time — a retryable state, surfaced in the UI with a "retry" affordance.
- Webhook events are the source of truth for state transitions after `sent`. A polled `fetchSignedDocument` is a fallback when the webhook is delayed; never the primary path.

---

## Storage (own the artifact)

When a signing completes, the system fetches the signed document AND the provider's audit trail and stores both in the **private bucket** (per `file-and-media-storage.md` FS-002):

```sql
CREATE TABLE signed_documents (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    tenant_id UUID NOT NULL,
    signing_request_id UUID NOT NULL,
    template_key TEXT NOT NULL,
    template_version TEXT NOT NULL,
    template_hash BYTEA NOT NULL,                  -- pinned at send time, verified on store
    document_bucket TEXT NOT NULL,
    document_key TEXT NOT NULL,
    document_sha256 BYTEA NOT NULL,                -- the system's independent fingerprint
    audit_trail_bucket TEXT NOT NULL,
    audit_trail_key TEXT NOT NULL,
    provider_name TEXT NOT NULL,
    provider_request_id TEXT NOT NULL,
    provider_signed_at TIMESTAMPTZ NOT NULL,
    locale TEXT NOT NULL,
    modality TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE signed_documents ADD CONSTRAINT chk_modality CHECK (modality IN ('simple', 'advanced', 'qualified'));
CREATE UNIQUE INDEX idx_signed_provider_request ON signed_documents (provider_name, provider_request_id);
```

Rules:

- The system records its own `document_sha256` — independent of the provider. Verification of "is this the document we signed?" never requires the provider; the system can prove it offline.
- Both the signed PDF and the audit-trail PDF are stored. The audit trail is the proof of who signed when.
- Retention is set to the longest legal floor (typically 6+ years for employment contracts; 10+ for some financial / insurance documents) and ALWAYS exceeds the user's RTBF. RTBF on a signed contract that is still inside the retention window MUST refuse — see `gdpr-pii.md` Section 17 carve-outs.

---

## Webhooks

Provider webhooks signal state transitions. The handler follows the same pattern as `payments-and-money.md`:

1. Verify the signature on the **raw** body (each provider has its scheme — HMAC over body + secret, JWT, etc.).
2. Look up the event id in `processed_signature_webhooks`.
3. If found → return 200; provider stops retrying.
4. If new → process; insert into the dedup table AND update the SigningRequest aggregate in the SAME DB transaction; return 200.

```sql
CREATE TABLE processed_signature_webhooks (
    provider TEXT NOT NULL,
    event_id TEXT NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (provider, event_id)
);
```

Rules:

- Webhook signature verification is the FIRST line of the handler — before parsing, before persisting, before logging. Invalid signature returns 401 + log + drop.
- Out-of-order webhook events follow `payments-and-money.md` PA-008 — handlers check current aggregate state, never trust arrival order.
- The webhook secret is in `secrets.md` as `SIGNATURE_PROVIDER_WEBHOOK_SECRET` with a documented rotation policy.

---

## Authorization & PII in signing

Signing involves PII (signer name, email, sometimes national ID, sometimes payment instrument). Two layers apply:

- `authorization.md` — the user initiating the signing has a Voter check (`canInitiateSigning(subject, purpose, tenant)`). The signer (third party) is identified by their email + provider auth; the system does not authenticate them, the provider does.
- `gdpr-pii.md` — the signer's data is `Internal-PII` minimum, often `Sensitive-PII` for national ID + signature image. The provider is a sub-processor, in `pii-inventory.md` (GD-011). The signing event itself is privacy-significant — `audit-log.md` records `signature.sent`, `signature.completed`, `signature.declined`.

Rules:

- The signer's identity data is NEVER stored beyond what is on the signed PDF + the audit trail. The system stores `signer_email_hash` (peppered, see GD-007) for dedup if needed; the email is in the document.
- A signing notification email or SMS is sent by the provider, not by the application — the application MUST NOT export the signer's email to its own marketing list (consent ledger says no).

---

## Reminders, deadlines, expiration

- The `deadline` on a `SigningRequest` is enforced by the provider when supported; a backstop cron in the application transitions to `expired` if the provider misses the deadline by 1+ hour.
- Reminders are scheduled (default: at 50% and 90% of the deadline window). The schedule is configurable per template; sending a reminder is itself a `signature.reminder.sent` audit entry.
- After expiration, the document and audit trail are NOT generated (the signing did not complete). A new `SigningRequest` is needed to retry.

---

## Verification (proving a signature)

A read API allows authorized parties to verify a signed document:

```
GET /api/v1/signed-documents/{id}/verify
→ {
    "document_sha256": "...",
    "matches_storage": true,
    "provider_audit_trail_url": "<presigned URL, TTL 5m>",
    "signers": [
      {"name": "...", "email_hash": "...", "signed_at": "..."}
    ],
    "signed_at": "...",
    "modality": "advanced",
    "template_version": "v5"
  }
```

Rules:

- The endpoint runs a Voter (`canVerifySignedDocument(subject, document)`).
- The provider audit-trail URL is a presigned URL per `file-and-media-storage.md` (FS-009/FS-010), TTL ≤ 15 minutes.
- The system's own SHA-256 verification is independent of the provider — even if the provider goes out of business, the system can prove the document.

---

## Cancellation & revocation

- Cancellation is signer-side ("I won't sign") OR sender-side ("I withdraw the offer"). Both transition the aggregate to a terminal state.
- Revocation of a completed signed contract is NOT a signature operation — it is a NEW signed document (e.g. a "termination agreement"). The original signed contract is immutable.
- A bug that results in needing to "void" a signed document is a documented incident with legal review. The system does NOT silently delete signed documents, even on RTBF — the carve-out is explicit (`gdpr-pii.md` Section 17 retain-legal).

---

## Observability

| Span attribute | Required | Example |
|---|---|---|
| `signature.provider` | yes | `signaturit` |
| `signature.purpose` | yes | `employment_contract` |
| `signature.template_version` | yes | `v5` |
| `signature.modality` | yes | `advanced` |
| `signature.signer_count` | yes | `2` |
| `signature.outcome` | when known | `sent` / `completed` / `declined` / `expired` |

NEVER as span attribute: signer's email, signer's national ID, contract amounts (PII risk).

| Metric | Labels |
|---|---|
| `signatures_sent_total` | `provider`, `purpose`, `modality`, `outcome` |
| `signatures_completed_total` | `provider`, `purpose`, `modality` |
| `signatures_declined_total` | `provider`, `purpose`, `decline_reason` |
| `signature_provider_latency_seconds` | `provider`, `operation`, histogram |
| `signature_webhook_failures_total` | `provider`, `error_class` |
| `signature_template_drift_total` | `template_key` (catches the binary-pin invariant) |

---

## Anti-patterns (auto-reject in review)

- A handler or service that imports a provider SDK directly (`Signaturit\Sdk`, `DocuSign\eSign`) — bypasses the gateway.
- A signing operation without an `audit-log.md` entry on send AND on completion.
- Storing signed documents in the public bucket.
- Mutating a signed document or its aggregate state in place.
- Re-using a `SigningRequest` for a "second signing of the same template" — that is a new aggregate.
- A template version edited live without a code commit.
- A webhook handler that parses the body before verifying the signature.
- A verification endpoint without a Voter.
- A "skip the modality" code path that downgrades to `simple` when the provider is unavailable.
- Marketing emails sent to signer addresses harvested from signing flows.
- An RTBF process that deletes signed contracts within their legal retention window.

---

## What the reviewer checks

Signature rules are enforced during review via the backend reviewer checklist (see [`backend-review-checklist.md`](backend-review-checklist.md) → "Digital signatures") and the frontend reviewer checklist (see [`frontend-review-checklist.md`](frontend-review-checklist.md) → "Digital signatures"). The checklists are the authoritative surface — if a rule appears here and not in the checklist, file a minor and update the checklist in the same commit.
