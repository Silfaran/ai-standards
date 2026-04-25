# Audit Log Standards

## Philosophy

- An audit log answers "who did what to which thing, when, and from where". It is a different artifact from operational logs (`logging.md`), which answer "why did this request fail?".
- The audit log is append-only. A row inserted is a row that stays — corrections are new rows, never updates. This is what makes it admissible as evidence and useful for compliance.
- Every entry that matters in court (or in a customer dispute) is recorded synchronously, in the same database transaction as the action it describes. Async audit ("we'll log it on the queue") is a defect — when the queue is down, the action happened and the trail is missing.
- The audit log is not a debugging tool. Engineers do NOT read it to figure out a bug — they read it to investigate an incident or to honour a regulator's request. The schema reflects that: structured, low-cardinality, parsable.
- An action that is sensitive enough to need an audit entry is sensitive enough to need an explicit Voter check (`authorization.md`) and a typed exception path. Audit emerges from those — it is not a parallel system.

---

## When this standard applies

This standard applies whenever the system performs an action of one of these kinds:

- **Authorization-significant**: a privileged action (`user.delete`, `role.grant`, `tenant.suspend`)
- **Money-significant**: a financial state change (`charge.captured`, `payout.created`, `refund.issued`) — note this complements the `ledger_entries` of `payments-and-money.md` but is not a replacement
- **Privacy-significant**: a read or write of Sensitive-PII (`pii.access`, `dsar.export.delivered`, `rtbf.applied`) — required by `gdpr-pii.md`
- **Legally-significant**: a signed contract event, a consent grant or withdrawal, a verified identity check
- **Security-significant**: a successful authentication after MFA, a password change, a session revoked, an authorization denial (`authz.denied` from `authorization.md`)
- **Configuration-significant**: a backoffice change to a tenant's settings, a feature flag toggled in production, a price changed

Operational events (HTTP request received, query executed, job retried) belong in `logging.md` + `observability.md` — never in the audit log.

---

## Vocabulary

| Term | Meaning |
|---|---|
| **Audit entry** | A single immutable row recording one action |
| **Actor** | Who performed the action — typically a `Subject` (`authorization.md`); sometimes a service account, sometimes the system itself |
| **Action** | A stable string identifier in domain language: `board.delete`, `pii.access`, `consent.granted` |
| **Resource** | The aggregate the action targets — typed by `resource_type` + `resource_id` |
| **Outcome** | `succeeded` / `denied` / `failed`. A denial is just as important as a success |
| **Trace context** | The `trace_id` + `span_id` linking the audit entry back to the request that produced it |

---

## Schema (canonical)

The audit log is a single table per service, owned by Infrastructure. The shape is intentionally narrow — extensions go in `metadata` (JSONB), not new columns.

```sql
CREATE TABLE audit_log (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    occurred_at TIMESTAMPTZ NOT NULL,                  -- the business event time, not insert time
    tenant_id UUID NOT NULL,                            -- mandatory; cross-tenant queries are explicitly multi-tenant
    actor_kind TEXT NOT NULL,                           -- 'user' | 'service' | 'system'
    actor_id UUID,                                       -- nullable when actor_kind = 'system'
    actor_subject_role TEXT,                             -- highest-priority role at the time of the action; nullable for service/system
    action TEXT NOT NULL,                                -- 'board.delete', 'pii.access'
    resource_type TEXT NOT NULL,                         -- 'board', 'user', 'charge'
    resource_id UUID,                                    -- nullable when resource is global ('platform.config')
    outcome TEXT NOT NULL,                               -- 'succeeded' | 'denied' | 'failed'
    deny_reason TEXT,                                    -- populated when outcome = 'denied'
    request_ip INET,                                     -- nullable for system actors
    request_user_agent TEXT,                             -- truncated to 256 chars; PII-safe
    trace_id TEXT,                                       -- propagated from observability layer
    span_id TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb          -- typed per action; documented in audit-actions.md
);

ALTER TABLE audit_log ADD CONSTRAINT chk_actor_kind     CHECK (actor_kind IN ('user', 'service', 'system'));
ALTER TABLE audit_log ADD CONSTRAINT chk_outcome        CHECK (outcome IN ('succeeded', 'denied', 'failed'));
ALTER TABLE audit_log ADD CONSTRAINT chk_actor_id_match CHECK (
    (actor_kind = 'system' AND actor_id IS NULL) OR (actor_kind <> 'system' AND actor_id IS NOT NULL)
);

CREATE INDEX idx_audit_tenant_occurred  ON audit_log (tenant_id, occurred_at DESC);
CREATE INDEX idx_audit_actor             ON audit_log (tenant_id, actor_id, occurred_at DESC);
CREATE INDEX idx_audit_resource          ON audit_log (tenant_id, resource_type, resource_id);
CREATE INDEX idx_audit_action            ON audit_log (tenant_id, action, occurred_at DESC);
```

Rules:

- The table is owned by Infrastructure. Domain code does NOT import the audit table directly — it raises domain events that an `AuditLogProjector` consumes (see "Wiring" below).
- `metadata` is JSONB; the per-action shape is documented in `{project-docs}/audit-actions.md`. Adding a new shape requires updating that document in the same commit (the reviewer rejects otherwise).
- The PRIMARY KEY is `id` (UUID); there is no composite primary key — append-only tables benefit from a single-column PK for index size.
- Sequential UUIDv7 (or `pg_uuidv7` extension) is preferred for the PK on high-volume tables — improves index locality. Standard UUIDv4 is acceptable for typical volume.

### What `metadata` carries (and what it does NOT)

`metadata` carries:
- The diff for state changes: `{"before": {"name": "..."}, "after": {"name": "..."}}` for free-text edits where the diff is small.
- The reason for an action when policy demands it: `{"reason_code": "fraud_review"}`.
- The triggering event id when the action is a downstream effect: `{"caused_by_event_id": "evt_abc"}`.

`metadata` does NOT carry:
- Sensitive-PII (per `gdpr-pii.md` GD-005) — even in audit. A "before/after" of an email change records hashed pseudonyms or "[redacted]" placeholders.
- Free-form text the operator typed — that goes to `logging.md`'s structured fields if needed, not into the audit row.
- Embedded JSON that exceeds ~4KB. The audit log is not a content store — large blobs go to object storage (`file-and-media-storage.md`) and `metadata` carries the key.

---

## Append-only enforcement

The audit log is append-only at multiple layers:

1. **Code**: the `AuditLog` repository exposes only `record(AuditEntry)`. There is no `update`, no `delete`. PHPUnit checks the interface stays append-only.
2. **Database role**: the application's database role has `INSERT, SELECT` on `audit_log`; `UPDATE`, `DELETE`, `TRUNCATE` are revoked. The `migrations` role retains `ALTER` for schema evolution.
3. **Backups**: the audit log is included in every backup with the longest retention class — typically the legally required floor for the most-regulated action recorded.
4. **Optional WORM/immutability**: cloud-native WORM (S3 Object Lock, Azure Immutability Policies) on long-term archival of audit log exports — declared per project ADR if compliance requires it.

A migration that drops or alters an `audit_log` row is the kind of incident that wakes people up. Schema changes to the table follow `data-migrations.md` (expand-contract); existing rows are NEVER mutated.

### Retention

- Operational retention (online): documented per project; default is "longest legal floor of any audited action" — typically 6+ years for financial actions in EU jurisdictions.
- Archival retention (cold storage): when the operational table grows beyond practical query latency, older rows are archived to object storage in a Parquet-or-similar format with the same shape; the archival job is itself audited (`audit.archived`).

---

## Wiring (domain events → audit)

Domain code does NOT call `auditLog->record(...)`. Instead, it raises domain events; an `AuditLogProjector` (Application service) consumes the events and writes the entries.

```php
// Domain — knows nothing about audit
final class Board
{
    public function delete(Subject $by): BoardDeleted
    {
        if ($this->isDeleted) {
            throw new BoardAlreadyDeletedException($this->id);
        }
        $this->isDeleted = true;
        return new BoardDeleted($this->id, $this->tenantId, $by->id, $by->highestPriorityRole(), new \DateTimeImmutable());
    }
}

// Application — orchestrates, dispatches event
final readonly class DeleteBoardCommandHandler
{
    public function __invoke(DeleteBoardCommand $cmd): void
    {
        $board = $this->finder->execute($cmd->boardId);
        if (!$this->voter->canDelete($cmd->subject, $board)) {
            // Denial path also produces an audit entry — see below
            $this->auditOnDenial($cmd, 'not_owner');
            throw new ForbiddenActionException('board.delete', $board->id);
        }
        $event = $board->delete($cmd->subject);
        $this->boards->save($board);
        $this->eventBus->dispatch($event);              // → AuditLogProjector consumes
    }
}

// Infrastructure — projector
final readonly class AuditLogProjector
{
    public function onBoardDeleted(BoardDeleted $event): void
    {
        $this->auditLog->record(AuditEntry::from(
            occurredAt:    $event->occurredAt,
            tenantId:      $event->tenantId,
            actorKind:     'user',
            actorId:       $event->byId,
            actorRole:     $event->byRole,
            action:        'board.delete',
            resourceType:  'board',
            resourceId:    $event->boardId,
            outcome:       'succeeded',
            requestIp:     RequestContext::ip(),
            traceId:       RequestContext::traceId(),
            metadata:      [],
        ));
    }
}
```

Rules:

- The audit write happens in the SAME database transaction as the state change. The Application service either uses an outbox pattern (event stored in the same DB tx, projector reads it from there) OR the projector is invoked synchronously inside the same transaction. An async-only projector that writes audit AFTER the tx commits violates the synchronicity rule (see "Synchrony", below).
- Denial paths emit audit entries too — the failed Voter check produces an entry with `outcome='denied'`, `deny_reason`. This is a hard requirement.
- Failures (the action started but blew up halfway) emit `outcome='failed'` with `metadata.error_class`. The exception is propagated; the audit is the durable record that the attempt happened.

### Synchrony

Audit is **synchronous with the state change**, never async-only. Two acceptable patterns:

- **Same-tx projector**: the projector runs inside the handler's DB transaction (Doctrine DBAL `transactional()` block). Reliable, simple, the default.
- **Outbox**: the handler writes the audit entry to an `audit_outbox` table in the same tx; a worker drains the outbox to the canonical `audit_log` table. Required when the canonical store is in a different database (an audit warehouse).

Async-via-message-queue WITHOUT outbox is forbidden — when the queue is down, the action lands without the audit, and that combination is exactly the situation an audit exists to defend against.

---

## What the API exposes

The audit log is read-only via API, and never to anonymous callers. Permitted reads:

- The actor who performed an action MAY read their own audit entries (`GET /api/v1/me/audit`) — useful for "show me my account activity".
- A tenant admin MAY read their tenant's audit entries (`GET /api/v1/tenants/{id}/audit`) — paginated, filterable by action / actor / resource / time range.
- A platform operator MAY read across tenants only via a backoffice surface that itself audits the read (`audit.platform_query` entry).

Filters use indexed columns; arbitrary `metadata` JSONB queries from the API are forbidden — that path leads to slow queries and information disclosure (probing one user's metadata).

API responses redact PII per `gdpr-pii.md` — the audit entry stores hashed actor ids, the response renders display names by joining to the user table at read time.

---

## Audit and `logging.md`

The two are easy to confuse. The contract:

| Concern | `logging.md` | `audit-log.md` |
|---|---|---|
| Question answered | "What is happening / has gone wrong in the system?" | "Who did what, to which thing, when, from where?" |
| Storage | stdout → log aggregator (Loki, Cloudwatch, Datadog) | Postgres (operational) + cold archive |
| Lifetime | hot for 30 days, cold to 90, then deleted | years (legal floor) |
| Schema | structured JSON, evolving freely | strict, append-only, schema-checked |
| Read pattern | full-text + label filters in a UI | indexed queries by tenant + action / actor / resource |
| PII handling | redaction list | NEVER stored; references only |
| Insert path | sync, fire-and-forget | sync, in the same DB tx as the action |

A given event MAY appear in both — e.g. a successful login is logged operationally for monitoring AND audited (`auth.login.succeeded`) for legal record. The two are written in the same handler, with different purposes.

---

## Read-side: dashboards and exports

The audit log feeds two consumer surfaces:

- **Internal investigation UI**: a backoffice tool with the indexed filters above. Every query made through this UI is itself audited (`audit.queried`).
- **Customer-facing activity log**: the per-actor or per-tenant view through the API.
- **Regulator export**: an on-demand CSV/JSON export of the relevant slice. The export itself is audited (`audit.exported`) with the requesting party's identity in `metadata`.

The audit log is NOT a generic analytics surface. Aggregations across tenants for product metrics live in `analytics-readonly-projection.md`, not here.

---

## Observability of the audit log

Even the audit log has observability — it is a system component like any other.

| Metric | Labels |
|---|---|
| `audit_entries_total` | `tenant_id_class` (NOT raw id; class = `customer / internal / partner`), `action_class` (group of actions), `outcome` |
| `audit_write_failures_total` | `error_class` |
| `audit_outbox_lag_seconds` | (only if outbox pattern in use) |
| `audit_archive_runs_total` | `outcome` |

A non-zero `audit_write_failures_total` is a `SEV-2` incident — actions are landing without trail. The runbook (when the project ships `runbooks.md`) lists the resolution path.

---

## Anti-patterns (auto-reject in review)

- An UPDATE or DELETE on `audit_log` rows in any code path or migration.
- Audit writes in a separate, async-only job (`messageBus->dispatch(new AuditEntryRequested(...))` outside an outbox pattern).
- A protected action with no audit entry on success or denial — the Voter is consulted but silence follows.
- Free-form `description` columns added to the table — `metadata` carries structured per-action keys, not prose.
- Sensitive-PII written into `metadata` — even "for traceability". The reference is the actor/resource id; the PII is reconstructed at read time via authorized joins.
- A read endpoint that supports arbitrary `metadata` JSONB queries.
- An "audit" that is actually operational logging in disguise (single-line text, levels, formatting controlled by Monolog).
- Backups that exclude `audit_log` to save space.

---

## What the reviewer checks

Audit rules are enforced during review via the backend reviewer checklist (see [`backend-review-checklist.md`](backend-review-checklist.md) → "Audit log"). The checklist is the authoritative surface — if a rule appears here and not in the checklist, file a minor and update the checklist in the same commit.

## Automated drift detection

`scripts/project-checks/check-audit-action-drift.sh` fails CI when the codebase emits an audit entry whose `action` (e.g. `board.delete`, `signature.sent`) has no documented `metadata` shape in `{project-docs}/audit-actions.md`. See [`quality-gates.md`](quality-gates.md) → "Drift validators (consuming projects)".
