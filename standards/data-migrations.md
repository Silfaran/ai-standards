# Data Migrations Standards

## Philosophy

- The schema is part of the public contract between two versions of the service — the running one and the next one to deploy. Changes that break this contract are the most common cause of avoidable incidents.
- Every schema change is decomposed until each individual migration is **backward-compatible with the version of the application that runs alongside it**. When that is impossible, the change explicitly accepts a maintenance window and records it.
- Migrations run forward only. There is no "rollback" migration — recovery is always a new forward migration. The revert is code + schema moving together.
- Data is migrated in the migration **only** when the change is cheap and bounded. Backfills that touch rows at scale are background jobs, not blocking DDL.
- Rules here are enforceable by reading the migration file and the deploy sequence — they are about shape, ordering, and compatibility, not about runbooks or specific monitoring dashboards.

This standard defines the **strategy** for schema evolution. Tactical rules for writing a single Phinx migration file (index rules, `ALTER TABLE` patterns, naming) live in the `doctrine-migration-safe` skill — do not duplicate them here.

---

## Breaking vs non-breaking schema changes

Classify every schema change before writing the migration. The class determines the required strategy.

### Non-breaking (single migration, any order)

- Adding a nullable column with no default
- Adding a column with a constant default (PostgreSQL 11+ rewrites the default at read time for existing rows, no table rewrite)
- Adding a table that no deployed code uses yet
- Adding an index (`CREATE INDEX CONCURRENTLY` on populated tables)
- Widening a column (`VARCHAR(50)` → `VARCHAR(100)`, `INT` → `BIGINT`)
- Adding a CHECK constraint that the existing data already satisfies
- Adding a new value to an enum/lookup list (provided no code path rejects the new value)

### Breaking (requires expand-contract — see below)

- Dropping a column, table, index, or constraint that any deployed version reads or writes
- Renaming a column, table, or index
- Changing a column type in a non-widening way (`TEXT` → `UUID`, `TIMESTAMPTZ` → `TIMESTAMP`, narrowing)
- Adding `NOT NULL` to a populated column (even with a default — unless the populated backfill is also done)
- Adding a CHECK constraint that existing data violates
- Narrowing an enum/lookup list (removing or restricting values)
- Restructuring a table (splitting one table into two, collapsing two into one)
- Any change where the previous version of the application would produce wrong data if it ran against the new schema

If the migration does not cleanly fit either list, treat it as breaking. The cost of an unnecessary expand-contract is hours; the cost of missing one is an incident.

---

## Expand → Migrate → Contract

Every breaking change is decomposed into three separately releasable phases. Each phase is a normal deploy — the previous and new versions of the application must coexist on the same schema at every phase boundary.

### Phase 1 — Expand (additive schema, backward compatible)

The schema grows to carry both the old and the new shape. The application learns to write the new shape but keeps reading the old one.

Typical phase-1 migrations:

- Add the new column (nullable) alongside the old one.
- Add the new table alongside the old one.
- Add a synonym view mapping the new name to the old table (when renaming).
- Duplicate writes at the application level: every write updates both the old and the new column.

At the end of phase 1, the deploy is safe to release. The old version of the application still works (it only reads/writes the old shape). The new version writes both shapes but still reads from the old shape.

### Phase 2 — Migrate (data move, usually async)

Existing data is moved into the new shape. This phase runs after phase 1 has been in production long enough for the dual-write to capture every new row.

Rules:

- Data migration at scale runs as a **background job**, never inside the Phinx migration. A migration that takes minutes to apply blocks deploys, locks tables, and has no progress reporting.
- The job is idempotent and resumable. Failure halfway through never leaves the system inconsistent — the job restarts from where it stopped or from scratch without harm.
- The job batches writes. Typical batch size: 1,000 to 10,000 rows per transaction, with an explicit commit between batches. Large single transactions cause bloat in PostgreSQL.
- The job records progress (last processed id, rows processed, errors) in a dedicated table or in the project's observability backend. A running job that cannot be observed is a running job that will be killed at the first restart.
- The application switches its **read path** to the new shape only after the backfill is verified complete — the switch is a feature flag or a configuration toggle, not a code deploy.

At the end of phase 2, both shapes hold identical data. The application may read from either.

### Phase 3 — Contract (remove the old shape)

After phase 2 has been stable (minimum 7 days of the application reading from the new shape with no regression), the old shape is removed.

Phase-3 migrations:

- Drop the old column / table / index.
- Remove the dual-write code path.
- Remove the synonym view.
- Remove any feature flag introduced in phase 1 or 2.

Phase 3 is released as its own commit with `refactor(db)!:` prefix and a `BREAKING CHANGE:` trailer in the message body. The commit explicitly names the phase-1 and phase-2 commits that preceded it.

---

## Backfills

### Inside the migration vs background job

Use the decision table below:

| Condition | Approach |
|---|---|
| Table has fewer than ~10,000 rows AND the update is a single `UPDATE` with no per-row logic | In-migration backfill acceptable |
| Table has ~10,000 to ~100,000 rows | In-migration backfill acceptable only outside business hours and with an explicit `-- SLOW` comment; prefer a background job |
| Table has more than ~100,000 rows OR per-row logic is required OR the operation can fail mid-flight | Background job, mandatory |
| Backfill requires calling an external service | Background job, mandatory |

### Background-job rules

- The job is triggered by an explicit admin command (a Symfony console command), not by startup code or a cron.
- Execution is traceable: a `backfills` table (or equivalent in the project docs) records job name, start, end, row count, outcome.
- Each batch commits independently — a crash loses at most one batch of work.
- Batches are ordered by primary key, not by a mutable column. Ordering by `created_at` on a high-write table causes skipped rows.
- The job is safe to run concurrently with live traffic. It uses `SELECT ... FOR UPDATE SKIP LOCKED` or a similar non-blocking primitive when writes collide.

---

## Zero-downtime deploy coordination

A deploy that ships schema changes alongside application changes has three moving parts: the running instance, the new instance, and the schema. They coexist for minutes — sometimes hours — and every combination must behave correctly.

### The compatibility matrix

For every deploy that includes a migration, the developer confirms all four cells of the matrix are safe:

| Schema before → after | App `N-1` | App `N` |
|---|---|---|
| Before | works | works |
| After | **works** | works |

The highlighted cell is the one that surprises people. The new migration lands first; for a brief period, the old application is running against the **new** schema. If the old app crashes or writes wrong data in that cell, the deploy is broken.

If the highlighted cell is not safe, the change must be decomposed into expand-contract phases such that each intermediate schema is compatible with both versions of the application.

### Deploy order (the golden sequence)

1. **Run the migration.** The schema now carries both shapes (additive change from phase 1) or the new safe shape.
2. **Deploy the new application instances.** They take traffic alongside the old ones. Both versions operate correctly on the current schema.
3. **Drain and terminate the old instances.** Only the new version is running.
4. (After validation) **Run the contract migration** when phase 3 of an expand-contract is due.

Never merge step 1 and step 4 into a single migration. That is the textbook example of a breaking deploy.

### Session-level effects

Long-running connections (PgBouncer pools, application-level pools) may hold prepared statements referencing the old schema. After a column drop or rename, reset connection pools as part of the deploy — otherwise the first request on an old connection after the migration crashes.

---

## Cross-service considerations

Every service owns its own database (see [`backend.md`](backend.md) → Database Isolation). This removes the hardest class of cross-service migration problems — a schema change in one service cannot corrupt another service's data.

What remains:

### Event-driven data dependencies

When service A publishes a domain event and service B persists a projection of it, a change to the event shape is an **API contract** change, not a database change. It follows the breaking-change protocol in [`api-contracts.md`](api-contracts.md).

When service B's projection schema changes but the upstream event stays stable, the change is local to B and follows this standard unchanged.

### Cross-service data copies

There is no `JOIN` across services. When a new feature requires data currently held by another service, the options are, in order of preference:

1. Call the owning service's API at read time. Cache per [`caching.md`](caching.md).
2. Consume a domain event and maintain a local projection. The projection schema follows this standard.
3. Import a bounded snapshot via a one-time event-replay. The import is a background job; ongoing sync is event-driven.

Direct cross-service database access is forbidden. A `JOIN` between two services' tables is a latent incident waiting for a schema change.

### Coordinated releases across services

When two services must upgrade together to stay compatible, this is a signal that the contract between them was broken. Two paths are acceptable, in order:

1. Roll the change in one service first, shipping an additive change (event version 2 alongside event version 1). The second service migrates at its own pace. This is always preferred.
2. If the contract cannot be split additively, coordinate the release, document the window, and accept the risk explicitly — this is a rare exception, not a pattern.

Never ship a "simultaneous deploy" as the default coordination mechanism.

---

## Rollback posture

Migrations are **forward-only**. Phinx's `down()` method exists mechanically but is not used in production recovery.

The real rollback plan for a bad schema change is:

- For a non-breaking change: deploy a new migration that reverses the additive effect (drop the new column, drop the new table). The application may need a follow-up deploy to stop using the new shape.
- For an in-progress expand-contract: halt at the current phase. The expand phase is safe to live on indefinitely if the downstream phases are not executed.
- For a destructive contract phase that caused data loss: recovery comes from backups and point-in-time recovery, not from a `down()` migration. This is a documented incident, not routine work.

Every migration's PR description includes a one-sentence answer to "how do we undo this if it lands bad?" If that sentence is "revert the commit", the migration is not production-safe.

---

## Reversibility checklist (per migration)

Before a migration leaves the developer's machine, confirm:

- [ ] Classified as non-breaking or breaking using the lists above.
- [ ] If breaking: phase declared (expand / migrate / contract) and referenced in the commit message.
- [ ] Backfill strategy chosen per the decision table — in-migration or background job.
- [ ] Compatibility matrix reviewed: the old application version works against the new schema in the deploy window.
- [ ] Large-table considerations (`CONCURRENTLY`, three-step NOT NULL) applied per the `doctrine-migration-safe` skill.
- [ ] Idempotent — running the migration twice leaves the schema in the same state.
- [ ] Commit message uses `!` and a `BREAKING CHANGE:` trailer when the change is breaking.
- [ ] PR description answers "how do we undo this if it lands bad?" in one sentence.

---

## Spec-time migration decision

The Spec Analyzer asks about schema evolution only when the feature touches existing tables or introduces a constraint change. Stay silent when the feature only adds new tables.

When triggered, ask the developer:

1. Which existing fields are modified, removed, or re-typed?
2. What is the current row count of the affected tables (order of magnitude)?
3. Is the downstream application already in production at another customer, or is this the first deployment? (Solo-dev early-stage projects may relax expand-contract; production services never do.)

Record the answers in the spec's Technical Details. The `refine-specs` step translates them into phase declarations and, when applicable, background-job tasks in the plan.

---

## What the reviewer checks

Data migration rules are enforced during review via the backend reviewer checklist (see [`backend-review-checklist.md`](backend-review-checklist.md) → "Data migrations strategy"). The tactical index/`ALTER TABLE` rules from the `doctrine-migration-safe` skill remain under "Database & migrations" in the same checklist. When this standard changes, update the matching checklist entries in the same commit.
