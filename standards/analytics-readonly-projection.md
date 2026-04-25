# Analytics Read-Only Projections Standards

## Philosophy

- Analytics queries and operational queries belong on different code paths. The first prizes flexibility and aggregation; the second prizes correctness and latency. Mixing them produces slow OLTP and unreliable BI.
- The operational store is the source of truth. Every analytics surface — materialized view, read-replica, warehouse, dashboard — is a derivation. A bug that loses an analytics row is rebuildable; a bug that loses an operational row is an incident.
- Aggregations are computed at write time when the volume is high and the query is hot; computed on read when the data is small and the question changes often. Picking wrong is normal — the standard makes the choice reversible.
- Analytics never bypasses authorization or PII rules. A "data export" surface that reads `users.email` directly without the controls of `gdpr-pii.md` is a leak with extra steps.
- Reporting tools and notebooks live OUTSIDE the application. They consume read-only projections via documented contracts, never reach into application internals.

---

## When this standard applies

This standard applies whenever the system needs to:

- Render dashboards (admin metrics, tenant insights, marketplace health)
- Run scheduled reports (weekly tenant summary, monthly billing reconciliation digest)
- Power product analytics (funnels, cohorts, retention curves)
- Expose data to external BI tools (Metabase, Superset, Looker, Tableau)
- Feed product-machine-learning surfaces (recommendation candidates, propensity scores)

It does NOT cover the audit log (separate, see `audit-log.md`) or the financial ledger (separate, see `payments-and-money.md`). It complements `caching.md` (HTTP caching of read endpoints) — projections live BEHIND the cache, not in front of it.

---

## Vocabulary

| Term | Meaning |
|---|---|
| **Operational store** | The OLTP database (Postgres in `tech-stack.md`) backing the application's writes |
| **Projection** | A read-only derivation: a materialized view, a denormalized table, a search index, a cube, a CSV export. The projection is rebuildable from the operational store |
| **Read-only schema** | A Postgres schema (`analytics`) whose tables are read-only from the application — only background jobs WRITE there, application handlers SELECT |
| **Replica** | A streaming replica of the operational store. Same schema, eventually consistent (lag in seconds). Suitable for read-only queries that tolerate stale data |
| **Warehouse** | A separate database optimized for analytics (BigQuery, Snowflake, Redshift, ClickHouse, DuckDB). Hosted off the operational tier; loaded on a cadence |
| **Materialized view** | A SELECT query whose result is stored on disk and refreshed on a schedule. Postgres native; same database, isolated schema |
| **Event stream** | An append-only stream of domain events the operational store emits; analytics consumers read it independently |

---

## The four-tier projection model

Pick the tier per use case. Higher tiers cost more (operational complexity, latency, freshness trade-offs); higher tiers are needed when the lower one no longer fits.

| Tier | What it is | When to pick | Latency | Cost |
|---|---|---|---|---|
| **T1 — read on operational** | A handler SELECTs from operational tables (with proper indexes) | Single-tenant aggregates, low cardinality, < 100 ms p95 against a small dataset | 0 (real-time) | Lowest, but consumes OLTP capacity |
| **T2 — materialized view (same DB)** | `CREATE MATERIALIZED VIEW analytics.foo` refreshed on cron | Tenant-level KPIs, daily/hourly aggregates, query repeated thousands of times | Refresh cadence (5 min – 24 h) | Disk + refresh time, no extra infra |
| **T3 — read replica** | Streaming replica with the same schema; analytics queries hit the replica only | Cross-tenant queries, scans larger than working set, heavy reporting | Replication lag (seconds) | One replica per tier of read load |
| **T4 — warehouse / external store** | Loaded via CDC, batch ETL, or event-stream consumer; lives in BigQuery/Snowflake/ClickHouse | Cross-source joins, BI tools, ML feature engineering, retention beyond operational floor | Load cadence (minutes – nightly) | Infrastructure + governance overhead |

A new analytics surface starts at T1 unless a measurement (or a known-quantity scale) requires higher. Premature T4 is the most common over-engineering in this domain.

---

## T1 — Read directly on operational

The handler SELECTs from operational tables. Same authorization, same indexes, same Voters as any other read.

```php
// Application/Service/Analytics/TenantSummaryReadService.php
final readonly class TenantSummaryReadService
{
    public function execute(string $tenantId, Subject $subject): TenantSummaryView
    {
        if (!$this->voter->canViewSummary($subject, $tenantId)) {
            throw new ForbiddenActionException('tenant.summary.view', $tenantId);
        }
        return $this->repo->summary($tenantId);
    }
}
```

Rules:

- Same Voter rules as any other read (`AZ-001`).
- The repository method returns a typed `View` DTO — never raw arrays.
- Indexes are added per `PE-001`. A summary query without a covering index is a defect.
- Cap pagination per `PE-003` even when the consumer is internal — an unbounded `LIST` query is a deferred outage.

When T1 stops fitting: query latency exceeds 100 ms p95, the OLTP plan is changing daily under load, or the same query runs from N concurrent dashboards.

---

## T2 — Postgres materialized views

The aggregation is precomputed and refreshed on a schedule.

### Schema discipline

```sql
CREATE SCHEMA IF NOT EXISTS analytics;

CREATE MATERIALIZED VIEW analytics.tenant_daily_activity AS
SELECT
    tenant_id,
    date_trunc('day', occurred_at) AS day,
    count(*) AS events,
    count(distinct actor_id) AS active_users
FROM audit_log
WHERE action LIKE 'user.%'
GROUP BY tenant_id, day
WITH NO DATA;

CREATE UNIQUE INDEX idx_analytics_tenant_daily_pk ON analytics.tenant_daily_activity (tenant_id, day);
CREATE INDEX idx_analytics_tenant_daily_day ON analytics.tenant_daily_activity (day);
```

Rules:

- Every projection lives in a dedicated schema (`analytics`). NEVER under the operational schema.
- The application's database role has `SELECT ONLY` on the `analytics` schema. The `analytics_writer` role (used by the refresh job) has `SELECT` + `REFRESH` on materialized views.
- Every materialized view has at least one UNIQUE INDEX so `REFRESH MATERIALIZED VIEW CONCURRENTLY` is possible — full refreshes lock readers.
- Refresh is `CONCURRENTLY` for any view consumed by user-facing reads; non-concurrent only for low-traffic admin reports.

### Refresh job

A scheduled command (Symfony console) refreshes views per their cadence, declared in `{project-docs}/analytics-projections.md`:

| View | Refresh cadence | Owner |
|---|---|---|
| `analytics.tenant_daily_activity` | every 1 h | platform team |
| `analytics.payouts_monthly` | nightly 02:00 | finance team |

The refresh job:

- Logs duration per view (metric `analytics_refresh_duration_seconds`).
- Tracks staleness (`last_refresh_at` per view; alert when > 2× cadence).
- Idempotent — a missed run is the next run's problem, not a backfill exercise.

### When T2 stops fitting

Refresh time exceeds the cadence; the view depends on cross-database joins; a new BI tool needs schemas the operational DB does not host.

---

## T3 — Read replica

A streaming replica of the operational database. Same schema, near-real-time, separate compute.

Rules:

- Connection string is a separate env var (`DATABASE_REPLICA_URL`); no application code chooses replica per query — separate connection objects (`@doctrine.dbal.default_connection` vs `@doctrine.dbal.replica_connection`) injected by name.
- Replica connections are READ-ONLY. The application's role on the replica has only `SELECT`. A `INSERT/UPDATE/DELETE` on the replica is rejected by the database, not by code.
- Application services that read the replica MUST tolerate stale data — every consumer has a documented "max acceptable lag" and the system surfaces lag as a metric (`replica_lag_seconds`).
- Lag exceeding the documented tolerance is a `SEV-3` incident — the consumer falls back to the primary OR refuses the request, depending on use case.

### Code shape

```php
final readonly class ProfessionalsRecentSignupsReadService
{
    public function __construct(
        #[Autowire('@doctrine.dbal.replica_connection')]
        private Connection $replica,
    ) {}

    public function execute(int $sinceDays): array
    {
        return $this->replica->fetchAllAssociative(
            'SELECT id, display_name, created_at
             FROM professionals
             WHERE created_at > NOW() - INTERVAL :i
             ORDER BY created_at DESC
             LIMIT 1000',
            ['i' => $sinceDays.' days'],
        );
    }
}
```

The handler signs the read for replica use explicitly. There is no "primary fallback" inside the read service — the orchestrating Application service handles the fallback decision.

---

## T4 — Warehouse / external store

The operational store feeds an external analytics database via one of:

- **Logical replication / CDC**: Postgres logical replication or Debezium reads the WAL and ships row changes to the warehouse.
- **Event-stream consumer**: domain events are consumed off the application's event bus and projected into warehouse tables.
- **Batch ETL**: a scheduled job reads slices of the operational DB and writes to the warehouse.

Rules:

- The application code does NOT know the warehouse exists. Loading is an infrastructure concern (CDC pipeline, ETL service) — `src/` of the application does not contain a `BigQueryClient`.
- The warehouse holds derived data only; identifiers, anonymized PII, aggregates. Direct copies of `users.email` into a warehouse without the controls of `gdpr-pii.md` are forbidden.
- The warehouse's PII shape MUST be classified into the same tiers as the operational store (`pii-inventory.md`) with the warehouse listed as a sub-processor (`GD-011`) when the warehouse runs in a different account/region.
- Warehouse retention is documented. A warehouse "for ML" that keeps PII forever is a privacy debt waiting to be flagged in audit.

### When T4 is justified

- Cross-source joins (operational + ad spend + helpdesk transcripts).
- BI tools needing cube-style queries against billions of rows.
- ML feature stores where the read pattern is "all rows for this entity, ever".
- Compliance retention beyond operational floor (data the operational store actively expires).

When none of those is measured, a T2/T3 projection is sufficient — and one fewer system to operate.

---

## Privacy in projections

Projections inherit, never weaken, the privacy constraints of the operational store.

Rules:

- A `Sensitive-PII` field stays Sensitive-PII in the projection. Not "the warehouse is internal so it's fine".
- DSAR exports (`gdpr-pii.md`) include warehouse data — the `DsarExportService` walks operational AND projection sources or the architecture documents why a projection is excluded (e.g. anonymized aggregates with k-anonymity ≥ 20).
- RTBF (`gdpr-pii.md` Section 17) propagates to projections. Materialized views auto-rebuild on next refresh; replica deletes via streaming; warehouse deletes via the privacy event bus consumed by the ETL.
- A field that is NOT in `pii-inventory.md` MUST NOT be exported to a warehouse. The warehouse loader rejects unknown fields.

---

## Authorization in projection-reading endpoints

A projection-backed endpoint runs the same Voter as any other endpoint. The fact that "the data is summary stats" does not relax authorization.

Examples:

- A tenant admin's tenant-level summary requires the same Voter as their other tenant-admin actions.
- A platform-wide dashboard requires a `platform_operator` role; the Voter check is mandatory.
- A "public marketplace stats" endpoint serving aggregate counts to anonymous users still passes through the Voter (`canViewPublicStats(subject)` returning true for anyone) — the Voter is the auditable record that the call was authorized.

Cross-tenant queries via projections (a platform operator viewing the global dashboard) are explicitly multi-tenant in the SQL — the Voter authorizes the cross-tenant access, the SQL fetches across tenants, audit records the platform query.

---

## Caching projection responses

Projection-backed endpoints are typically cacheable per `caching.md`:

- Public counts → `Cache-Control: public, max-age=300, s-maxage=300` + `Vary: Accept-Language`.
- Per-tenant summaries → `Cache-Control: private, max-age=60` + invalidation on the events that move the underlying numbers.
- Per-user dashboards → `Cache-Control: private, no-cache` + ETag based on the projection's `last_refresh_at`.

The cache key includes the projection version (when the projection schema changes, bump the version in the key suffix).

---

## Observability

| Metric | Labels | Purpose |
|---|---|---|
| `analytics_refresh_duration_seconds` | `view`, histogram | Catches refreshes that grow past the cadence |
| `analytics_refresh_failures_total` | `view`, `error_class` | Stale projection alerts |
| `replica_lag_seconds` | `replica` | Replica liveness |
| `warehouse_load_duration_seconds` | `pipeline`, histogram | Warehouse load cadence health |
| `warehouse_load_rows_processed_total` | `pipeline`, `entity_type` | Volume tracking |

Every projection-backed read endpoint emits `analytics.read` span attributes:

- `analytics.tier` — `t1`/`t2`/`t3`/`t4`
- `analytics.projection` — view/table name (low cardinality)
- `analytics.staleness_seconds` — for T2/T3/T4 reads, how old the data is

A read whose `analytics.staleness_seconds` exceeds the documented tolerance is the dashboard's responsibility to surface ("data as of X minutes ago") — silent stale answers are a worse UX than visible delay.

---

## When to graduate (and when not)

The most common mistake in this domain is jumping from T1 to T4 because "we'll need a warehouse eventually". The standard's bias:

| Trigger to graduate | From → To |
|---|---|
| Same query running across 5+ dashboards | T1 → T2 |
| Query consuming > 5% of OLTP capacity | T1/T2 → T3 |
| Refresh time > cadence | T2 → T3 or T2-with-incremental |
| Cross-source joins required | T2/T3 → T4 |
| BI tool requires direct SQL on terabyte volumes | T3 → T4 |

A graduation is an ADR (`{project-docs}/decisions.md`). It documents the trigger that fired, the chosen tier, and the ownership of the new pipeline.

---

## Anti-patterns (auto-reject in review)

- An analytics query in a HTTP handler without a `Voter` check or pagination.
- A materialized view in the operational schema (mixed read/write surface).
- An application handler with a hardcoded `replica.connect(...)` — replica access is via DI'd connection.
- A warehouse loader that copies `users.email` (or any other Sensitive-PII) without an entry in `pii-inventory.md`.
- A "BI export" surface that bypasses authorization "because admins access it via VPN".
- Replica reads with no documented lag tolerance or `replica_lag_seconds` metric.
- A T4 pipeline introduced without an ADR.
- A materialized view refreshed non-`CONCURRENTLY` on a user-facing path.
- An analytics endpoint whose response is not cacheable (and is hit thousands of times per minute).

---

## What the reviewer checks

Projection rules are enforced during review via the backend reviewer checklist (see [`backend-review-checklist.md`](backend-review-checklist.md) → "Analytics & projections"). The checklist is the authoritative surface — if a rule appears here and not in the checklist, file a minor and update the checklist in the same commit.
