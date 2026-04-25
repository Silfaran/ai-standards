# Critical path — Payment endpoint

Use when the diff charges, refunds, holds in escrow, pays out, splits revenue, manages subscriptions, or handles webhooks from a Payment Service Provider. Always combine with [`auth-protected-action.md`](auth-protected-action.md) for the user-facing actions.

## Backend

### Money modeling
- PA-001 Every monetary value uses the `Money` VO (integer minor units + ISO 4217)
- PA-002 Money columns pair `amount_minor BIGINT` + `currency CHAR(3)` with CHECK
- PA-003 Currency mismatches throw `CurrencyMismatchException`
- PA-004 Splits use a sum-preserving algorithm (largest-remainder method)

### Idempotency on outbound calls
- PA-005 Every PSP mutation carries a deterministic `Idempotency-Key`

### Webhooks
- PA-006 Verify provider signature on RAW body BEFORE parsing JSON
- PA-007 `processed_webhooks(provider, event_id)` dedup; insert in same DB tx as state change BEFORE returning 200
- PA-008 Out-of-order tolerance: handlers check current state, never trust arrival order

### Ledger
- PA-009 Every balance change produces immutable `ledger_entries`; transactions sum to zero per currency at write time
- PA-010 Ledger append-only; corrections are NEW entries with `cause_type='adjustment'`
- PA-011 Account names stable; rename via reversal entries in same tx
- PA-018 Multi-party splits record both legs at capture time; payout settlement debits `payout_pending`

### State machines
- PA-012 Charge / Subscription / Refund / Payout / Dispute have explicit state machines enforced by aggregate + DB CHECK
- PA-013 Subscriptions are webhook-driven (no polling cron)
- PA-014 Refunds are first-class aggregates; charge state derived

### Pricing
- PA-015 Prices in DB (`prices` table with `valid_from` / `valid_until`); never hardcoded in PHP

### API serialization
- PA-016 Money serialized as `{ amount_minor, currency }`; serializer refuses Money → float

### Reconciliation
- PA-017 Daily reconciliation; non-zero delta is SEV-2 incident
- PA-019 Span attributes + metrics bounded; no customer identifiers as labels
- PA-020 `{PROVIDER}_WEBHOOK_SECRET` in `secrets-manifest.md` with rotation policy; HTTP webhooks rejected with 426 in dev/staging

### Authorization & audit (carried over)
- AZ-001 Voter check before mutation
- AU-006 Audit write in same DB tx
- AU-007 Entries on success / denied / failed

### Hard blockers
- BE-001 Quality gates green
- SC-001 No secrets committed
- LO-001 No unredacted sensitive fields in logs

## Frontend (when payments touch UI)

- PA-021 API payloads use `{ amount_minor, currency }`
- PA-022 Render via `Intl.NumberFormat` `style: 'currency'` + explicit locale
- PA-023 Card capture uses PSP hosted element; raw card numbers NEVER touch frontend state
- PA-024 Payment confirmation pages re-fetch backend (webhook-driven) before showing success

## What this path does NOT cover

- Authorization → [`auth-protected-action.md`](auth-protected-action.md)
- Sub-processor inventory entry for the PSP → [`pii-write-endpoint.md`](pii-write-endpoint.md) (GD-011)
- Stored payment instruments / KYC documents → [`file-upload-feature.md`](file-upload-feature.md)
