---
name: doctrine-migration-safe
description: Use when writing a Phinx migration — creating or altering a PostgreSQL table, adding columns, adding indexes, or modifying schema in a PHP/Symfony service that uses Doctrine DBAL (not the ORM).
paths: "**/src/Infrastructure/Persistence/Migration/**, **/phinx.php"
---

# Safe PostgreSQL migrations with Phinx

Every migration touches production data sooner or later. These rules prevent the two failure modes that matter: table locks under write load, and missing indexes that turn `WHERE` into a full table scan.

## Index rules — always add an index when

| Situation | Why |
|---|---|
| Column appears in a `WHERE` clause in any repository query | Without an index, PostgreSQL does a full table scan |
| Column appears in `ORDER BY` | Sorting without an index is slow on large tables |
| Column is a UUID reference to another table (`board_id`, `user_id`, ...) | ADR-007 forbids FK constraints → no automatic index |
| Column is used for search or API filters (`status`, `email`, ...) | Predictable query pattern — index it now |

## Index rules — do NOT add an index when

| Situation | Reason |
|---|---|
| Column is `id` (primary key) | Already indexed by the primary key |
| Column has a `UNIQUE` constraint | Unique constraint creates the index |
| Column is only written, never filtered or sorted | Indexes slow down writes — don't speculate |
| Table is small (< 100 rows) and will stay small | Full scan beats index lookup at this scale |

## Before writing the final SQL — 4-step check

1. List every column in the new/altered table.
2. For each column: will it appear in `WHERE`, `ORDER BY`, or as a reference to another table?
3. If yes → `CREATE INDEX`.
4. Never add `FOREIGN KEY`, `REFERENCES`, or `ON DELETE` — ADR-007 prohibits these project-wide.

## Safe `ALTER TABLE` patterns

### Adding a column to a table with data

```sql
-- SAFE — PostgreSQL 11+ handles constant DEFAULT without rewriting the table
ALTER TABLE boards ADD COLUMN archived_at TIMESTAMP DEFAULT NULL;

-- SAFE — nullable with no default, instant
ALTER TABLE boards ADD COLUMN description TEXT;

-- DANGEROUS on big tables — locks writes while filling every row
ALTER TABLE boards ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'active';
```

For tables larger than ~100k rows, use the three-step pattern:

1. Add column as nullable in migration A.
2. Backfill existing rows in batches (separate script or migration B).
3. Add `NOT NULL` constraint in migration C, after backfill.

### Adding an index to a populated table

```sql
-- BLOCKS reads and writes while building the index
CREATE INDEX idx_boards_user_id ON boards (user_id);

-- SAFE — takes longer but does not lock the table
CREATE INDEX CONCURRENTLY idx_boards_user_id ON boards (user_id);
```

Use `CONCURRENTLY` whenever adding an index to a table that already has data. Phinx accepts raw SQL in `up()` when you need `CONCURRENTLY` — the concurrent variant cannot run inside a transaction, so guard with `disableTransactions` or run it as a separate raw statement.

## Naming conventions

- Index name: `idx_<table>_<column>` for single-column, `idx_<table>_<col1>_<col2>` for composite.
- Unique index name: `uniq_<table>_<column>`.
- Table names: `snake_case`, plural (`boards`, `board_members`).
- Column names: `snake_case`, singular (`user_id`, `created_at`).

## Never edit an executed migration

Once a migration is applied anywhere (even locally), it is immutable. To correct a schema mistake, create a new migration that applies the correction. Phinx tracks applied migrations by name — editing history leaves every other environment in a broken state.

## Location and timestamp

Phinx migrations live in `src/Infrastructure/Persistence/Migration/`. Exclude this directory from Symfony service auto-discovery in `services.yaml` — see [backend.md](../../../standards/backend.md) for the exclude block.

## See also

- [standards/performance.md](../../../standards/performance.md) — full rules, including N+1 prevention and pagination.
- [standards/backend.md](../../../standards/backend.md) — ADR-007 context and DBAL conventions.
- ADR-007 (in `decisions.md`) — why this project uses no foreign keys.
