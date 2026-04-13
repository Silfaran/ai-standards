# Performance Standards

## Philosophy

- Prevent the most common production performance mistakes at code-writing time
- Rules here are enforceable by an agent reading the code — no production metrics needed
- Prefer simple and correct over premature optimization

---

## Database — Migrations

### Index rules

Every migration that adds a new table or column must be reviewed against these rules before it is considered complete.

**Always add an index when:**

| Situation | Why |
|---|---|
| Column appears in a `WHERE` clause in any repository query | Without index, PostgreSQL does a full table scan |
| Column appears in `ORDER BY` | Sorting without index is slow on large tables |
| Column is a UUID reference to another table's record (`board_id`, `user_id`, etc.) | See ADR-007 — no FK constraints means no automatic index |
| Column is used for searching or filtering by the API (e.g. `status`, `email`) | Predictable query pattern → index it now |

**You do not need an index when:**

| Situation | Reason |
|---|---|
| Column is `id` (primary key) | Already indexed by the primary key constraint |
| Column has a `UNIQUE` constraint | Already indexed by the unique constraint |
| Column is only ever written, never filtered or sorted | Indexes slow down writes — do not add speculatively |
| Table is small and will always be small (e.g. a config table with < 100 rows) | Full scan is faster than an index lookup at this scale |

**Migration checklist — before writing the final SQL:**

1. List all columns in the new table or added in this migration
2. For each column: will it appear in `WHERE`, `ORDER BY`, or as a reference to another table?
3. If yes → add `CREATE INDEX`
4. Never add `FOREIGN KEY`, `REFERENCES`, or `ON DELETE` — see ADR-007

### Safe migration patterns

**Adding a column to an existing table with data:**

```sql
-- SAFE in PostgreSQL 11+ when DEFAULT is a constant
ALTER TABLE boards ADD COLUMN archived_at TIMESTAMP DEFAULT NULL;

-- SAFE — nullable column, no default needed
ALTER TABLE boards ADD COLUMN description TEXT;

-- DANGEROUS — locks the table on PostgreSQL < 11 for large tables
-- Prefer: add column nullable, backfill, add NOT NULL constraint separately
ALTER TABLE boards ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'active';
```

If the table may be large (> 100k rows), use the three-step pattern:
1. Add column as nullable
2. Backfill existing rows in batches
3. Add `NOT NULL` constraint in a separate migration

**Adding an index to an existing table with data:**

```sql
-- BLOCKS reads and writes while building the index
CREATE INDEX idx_boards_user_id ON boards (user_id);

-- SAFE — builds concurrently without locking (takes longer, but non-blocking)
CREATE INDEX CONCURRENTLY idx_boards_user_id ON boards (user_id);
```

Use `CONCURRENTLY` whenever adding an index to a table that already has data.

---

## Database — Queries (DBAL repositories)

### Pagination is mandatory on all list queries

Every repository method that returns multiple rows must accept a limit and offset. There are no unbounded list queries.

```php
// WRONG — returns all rows, no limit
public function findByUserId(string $userId): array
{
    return $this->connection->fetchAllAssociative(
        'SELECT * FROM boards WHERE user_id = ?',
        [$userId],
    );
}

// CORRECT — paginated
public function findByUserId(string $userId, int $limit = 20, int $offset = 0): array
{
    return $this->connection->fetchAllAssociative(
        'SELECT * FROM boards WHERE user_id = ? ORDER BY created_at DESC LIMIT ? OFFSET ?',
        [$userId, $limit, $offset],
    );
}
```

| Parameter | Default | Maximum |
|---|---|---|
| `limit` | 20 | 100 |
| `offset` | 0 | — |

The API controller is responsible for reading `?page=` and `?per_page=` from the request and translating them to `limit` and `offset`.

### No queries inside loops

```php
// WRONG — N+1: one query per board
foreach ($boardIds as $boardId) {
    $member = $this->connection->fetchAssociative(
        'SELECT * FROM board_members WHERE board_id = ?',
        [$boardId],
    );
}

// CORRECT — one query for all boards
$placeholders = implode(',', array_fill(0, count($boardIds), '?'));
$members = $this->connection->fetchAllAssociative(
    "SELECT * FROM board_members WHERE board_id IN ($placeholders)",
    $boardIds,
);
```

If you find yourself writing a loop that calls a repository method, stop and rewrite it as a batch query.

### Select only the columns you need

```sql
-- WRONG — fetches all columns including large TEXT fields
SELECT * FROM boards WHERE user_id = ?

-- CORRECT — fetch only what the response actually needs
SELECT id, name, created_at FROM boards WHERE user_id = ?
```

Exception: internal domain operations that reconstruct full objects may use `SELECT *` if the table is narrow.

---

## API — Response Design

### List endpoints must support pagination

Every `GET` endpoint that returns a collection must:
- Accept `?page=` (1-based) and `?per_page=` (default 20, max 100) query parameters
- Return a response envelope with the total count:

```json
{
  "data": [...],
  "meta": {
    "total": 84,
    "page": 1,
    "per_page": 20
  }
}
```

---

## Frontend

### Lazy-load all routes except the landing page

```ts
// WRONG — synchronous import, loaded in the initial bundle
import BoardsPage from '@/pages/BoardsPage.vue'

// CORRECT — lazy-loaded, only fetched when the user navigates to /boards
const BoardsPage = () => import('@/pages/BoardsPage.vue')
```

The landing page may be eagerly loaded (it is the entry point). All other routes must be lazy.

### Import only what you use from large libraries

```ts
// WRONG — imports the entire library into the bundle
import _ from 'lodash'
const result = _.groupBy(items, 'status')

// CORRECT — imports only the function needed
import groupBy from 'lodash/groupBy'
const result = groupBy(items, 'status')
```

When adding a new dependency, check its bundle size with [bundlephobia.com](https://bundlephobia.com) before approving it. Prefer tree-shakeable libraries.
