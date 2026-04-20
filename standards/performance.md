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

### Core Web Vitals targets (per page)

Every user-facing page must meet the "good" threshold for each Core Web Vital on a mid-tier mobile device on 4G. Pages that regress below these thresholds are not shippable.

| Metric | Good | Needs improvement | Poor | What it measures |
|---|---|---|---|---|
| LCP (Largest Contentful Paint) | ≤ 2.5 s | 2.5–4.0 s | > 4.0 s | Time until the largest visible element finishes rendering |
| INP (Interaction to Next Paint) | ≤ 200 ms | 200–500 ms | > 500 ms | Worst-case latency between a user input and the next visual update |
| CLS (Cumulative Layout Shift) | ≤ 0.1 | 0.1–0.25 | > 0.25 | Total unexpected layout shift during page life |

TTFB (Time To First Byte) should be under 800 ms for origin-served HTML and under 200 ms for CDN-cached HTML. A poor TTFB typically indicates a backend or caching problem, not a frontend one.

### Measurement is non-negotiable

Every frontend ships with the [`web-vitals`](https://github.com/GoogleChrome/web-vitals) library wired in `main.ts`. Metrics are reported to the logging pipeline (see [`logging.md`](logging.md)) as structured JSON so they can be aggregated server-side.

```ts
// main.ts — after app.mount()
import { onCLS, onINP, onLCP, onTTFB } from 'web-vitals'

const report = (metric: { name: string; value: number; id: string; rating: string }) => {
  // POST to the backend log endpoint — never use navigator.sendBeacon directly to a third party
  fetch(`${import.meta.env.VITE_API_URL}/internal/web-vitals`, {
    method: 'POST',
    body: JSON.stringify(metric),
    keepalive: true,
  })
}

onLCP(report)
onINP(report)
onCLS(report)
onTTFB(report)
```

Lighthouse CI runs in GitHub Actions on every PR that touches the frontend. A performance score below 90 on the key pages (landing, login, dashboard) blocks the merge.

### Vite bundle configuration

Every frontend's `vite.config.ts` must set an explicit bundle budget and chunking strategy. Do not rely on the default — the default does not warn when the bundle grows past sensible limits.

```ts
// vite.config.ts
export default defineConfig({
  build: {
    target: 'es2022',
    chunkSizeWarningLimit: 250, // kB — fails CI if a chunk exceeds this
    rollupOptions: {
      output: {
        manualChunks: {
          vue: ['vue', 'vue-router', 'pinia'],
          query: ['@tanstack/vue-query'],
          forms: ['vee-validate', 'zod'],
        },
      },
    },
  },
})
```

Rules:

- `chunkSizeWarningLimit` is set explicitly. CI fails on warnings from `vite build`.
- Vendor libraries shared across most routes (Vue runtime, router, store, query client) are split into a `vendor` chunk so they cache independently of application code.
- Never use `manualChunks: undefined` or a `(id) => ...` catch-all that lumps everything into one vendor file.

### Bundle size budgets per entry

| Artifact | Max size (gzipped) | Rationale |
|---|---|---|
| Initial HTML response | 15 kB | Fits in one round trip on slow mobile |
| Initial JS (entry + critical chunks) | 170 kB | Parse/compile budget on mid-tier Android |
| Initial CSS | 50 kB | Render-blocking — keep lean |
| Per-route lazy chunk | 80 kB | Navigating to a new route should feel instant |
| Total JS over page lifetime | 500 kB | Hard ceiling — more than this is a design smell |

If a budget is exceeded, the fix is one of: (1) code-split further, (2) remove the dependency, (3) replace the dependency with something smaller. Never raise the budget silently.

### Images and media

- Every `<img>` and `<video>` declares `width` and `height` attributes (or a fixed aspect-ratio container). Missing dimensions cause CLS.
- Below-the-fold images use `loading="lazy"`. Above-the-fold images must not — they delay LCP.
- The largest above-the-fold image uses `fetchpriority="high"` and is preloaded in the document head when it is known at build time.
- Serve modern formats: AVIF with WebP fallback. PNG/JPEG only when the source pipeline cannot produce either.
- Never ship an unoptimized source image straight from a designer. Images go through the build pipeline (responsive `srcset`, width-appropriate variants) or a media service.

### Fonts

- Preload the one or two font files the initial render actually needs: `<link rel="preload" as="font" type="font/woff2" crossorigin>`.
- All `@font-face` declarations use `font-display: swap`. Never block text rendering on a font download.
- Subset fonts to the characters actually used (Latin subset minimum). A full Unicode font is almost never justified.

### Runtime performance

- Long lists (> 50 visible items) use virtualization (`@tanstack/vue-virtual` or equivalent). A naive `v-for` over 10 000 rows freezes the page on input.
- No synchronous `JSON.parse` / `JSON.stringify` on payloads larger than ~1 MB on the main thread. Offload to a worker or paginate the API.
- No `setInterval` polling loops for data that changes rarely. Prefer TanStack Query's `refetchOnWindowFocus` + explicit invalidation.
- `watchEffect` / `computed` with expensive work must memoize their inputs. A `computed` that filters a 1 000-item list on every keystroke is an INP regression waiting to happen.

### What "cache-ready" means for the frontend

Even without a CDN wired yet, the frontend is built so one can be added later with zero code changes:

- Every built asset has a content hash in its filename (Vite's default — do not override).
- No runtime code assumes same-origin for static assets: asset URLs use Vite's `import.meta.env.BASE_URL` or the public path Vite injects.
- No session/auth state is embedded in the HTML shell. The shell must be safe to cache publicly and served identically to every user.
