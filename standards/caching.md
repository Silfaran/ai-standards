# Caching Standards

## Philosophy

- Cache only what is measurably hot — never speculatively. Premature caching is a tax on correctness.
- Every cached value has a documented owner, a TTL, and a stated invalidation strategy. If any of the three is missing, do not cache.
- Correctness beats latency. A stale response served to a user who just wrote the value is a bug, not an optimization.
- Rules here are enforceable by reading the code — they are about cache keys, headers, and invalidation hooks, not about production metrics.

---

## When to Cache (decision matrix)

Before adding a cache layer, the feature must satisfy **all three**:

| Dimension | Question | Caching eligible if… |
|---|---|---|
| Read pattern | Is this endpoint/query hot (read many times between writes)? | Yes — high R/W ratio, or expensive query (>50 ms p50) |
| Staleness | What is the maximum tolerated staleness? | Explicitly defined by the developer, not "zero" |
| Invalidation | Is there a clear trigger (event, command, write) that invalidates the cached value? | Yes — invalidation rule is expressible as code |

If any answer is "no" or "unclear", do not cache yet. Write the feature without cache, measure, and add caching in a follow-up feature once the pattern is proven.

**Never cache:**

- Authentication tokens, session data, password hashes, refresh tokens, MFA codes
- Per-user sensitive data in shared caches without a per-user key (PII leak via key collision)
- Responses from write endpoints (`POST`, `PUT`, `PATCH`, `DELETE`) — they have no cacheable semantics
- Anything under active debugging — caches mask bugs

---

## HTTP Response Caching

### Cache-Control is mandatory on every GET response

Every `GET` endpoint sets an explicit `Cache-Control` header. No endpoint inherits a framework default silently.

| Endpoint kind | `Cache-Control` | Notes |
|---|---|---|
| Static public asset (JS/CSS/font bundle with content hash in the filename) | `public, max-age=31536000, immutable` | 1 year; filename hash guarantees new URL on new content |
| Public content (marketing pages, public catalog entries) | `public, max-age=300, s-maxage=3600` | 5 min at the browser, 1 h at the CDN |
| Per-user authenticated read (dashboard, user boards) | `private, no-cache` | `no-cache` = revalidate every request; never cache in a shared proxy |
| Sensitive per-user data (account settings, payments, tokens) | `no-store` | Never stored anywhere, including the browser disk cache |
| Write endpoints (`POST`/`PUT`/`PATCH`/`DELETE`) | `no-store` | Non-cacheable by protocol — setting it explicitly is still required to be unambiguous |

### Conditional requests — ETag or Last-Modified

Every cacheable `GET` (anything that is not `no-store`) must return one of:

- `ETag: "<strong-validator>"` — a hash/version of the response body. Preferred for dynamic content.
- `Last-Modified: <RFC 7231 date>` — for resources with a clear mtime.

The server must honor `If-None-Match` / `If-Modified-Since` and return `304 Not Modified` with no body when the validator matches. A 200-with-body response on every request defeats the purpose.

### Vary is required when the response depends on request state

If the response differs by `Accept-Language`, `Authorization`, or any other header, declare it:

```
Vary: Accept-Language, Authorization
```

Missing `Vary` causes shared caches to serve one user's response to another. This is a correctness bug, not a performance bug.

---

## Application-Level Cache (Redis)

### When to reach for Redis (vs HTTP cache)

HTTP cache covers responses. Redis covers values computed below the controller layer: aggregated counters, expensive joins, rate-limiter state, idempotency keys, fan-out event dedup.

Use Redis only when:
- The value is computed more expensively than fetched (>50 ms)
- The value is shared across requests or services (an HTTP cache only helps one request at a time)
- Invalidation is event-driven, not time-driven (TTL alone is a last resort)

### Cache-aside is the default pattern

```
1. Read from Redis by key
2. If hit → return
3. If miss → compute, write to Redis with TTL, return
```

Write-through and read-through patterns are allowed only when the cache is authoritative for a bounded context (rarely the case). Default to cache-aside.

### Keys follow a mandatory namespace convention

```
{service}:{aggregate}:{operation}:{identifier}[:v{version}]
```

Examples:
- `task-service:board:by-id:550e8400-e29b-41d4-a716-446655440000`
- `task-service:board:members-count:550e8400-e29b-41d4-a716-446655440000:v2`

Rules:
- Keys are all lowercase, colon-separated.
- Include a version suffix (`:v2`) when the schema of the cached value changes so stale entries expire without manual flush.
- Never embed user-controlled input into the key without validating its shape (UUID, numeric id, known enum).

### TTL defaults — use the shortest that is tolerable

| Data kind | Default TTL |
|---|---|
| Per-request idempotency key | 24 h |
| User-session-derived computed value | 5 min |
| Cross-user aggregate (counters, feeds) | 1 min, with event-driven invalidation on top |
| Reference data (country list, currency codes) | 1 h |
| Expensive read-through entity (`{aggregate}:by-id:{uuid}`) | 5 min, plus explicit invalidation on write |

Never set `TTL = 0` / infinite. Every Redis key expires, even when an explicit invalidation path exists — the TTL is the safety net against missed invalidations.

### Invalidation — event-driven by default

The write that changes the underlying data is the trigger for cache invalidation. Do not rely on TTL alone for entities that change predictably.

```php
// Wrong — the cache can serve stale data for up to 5 minutes after an update
final readonly class UpdateBoardHandler
{
    public function execute(UpdateBoardCommand $command): void
    {
        $this->repository->save($board);
    }
}

// Correct — invalidation is part of the write
final readonly class UpdateBoardHandler
{
    public function execute(UpdateBoardCommand $command): void
    {
        $this->repository->save($board);
        $this->cache->delete("task-service:board:by-id:{$board->getId()->toString()}");
    }
}
```

For values derived from multiple aggregates (counters, feeds), emit a domain event on write and have an event listener invalidate the derived key(s). Do not scatter `$cache->delete()` calls across unrelated handlers.

### Stampede protection is required for hot keys

A hot key that expires while under load causes every request to recompute the value simultaneously, overwhelming the origin. Mitigations, in order of preference:

1. **Soft TTL + recompute-on-miss with a lock**: request that hits a soft-expired entry acquires a short Redis lock and recomputes while others serve the stale value.
2. **Randomized jitter on TTL**: store with `TTL + random(0, TTL × 0.1)` to spread expiries.
3. **Background refresh**: a scheduled worker refreshes the key before its TTL elapses.

Pick one per hot key and document the choice in the spec's Technical Details.

### Never use the cache as the source of truth

If the Redis instance is lost, the system must continue to function (slower, but correct). Any feature that assumes cache state survives a restart is broken. This also means: no business-critical counters live only in Redis — persist them, cache them separately.

---

## Cache-friendly API design

Feature design that makes caching possible later, at zero up-front cost:

- **Stable URLs per resource.** `GET /boards/{id}` is cacheable; `GET /boards?id={id}` is harder (cache layers may treat every query-string variation as a distinct key).
- **Idempotent GETs.** A `GET` that increments a counter or logs an access is uncacheable. Move side effects to a separate event or `POST`.
- **Bounded list responses.** Paginated endpoints cache better than "return everything" endpoints.
- **Sparse fieldsets (`?fields=id,name`) produce distinct cache entries.** Prefer a small number of stable response shapes over one endpoint with combinatorial field selection.

---

## Spec-time caching decision

The Spec Analyzer asks about caching only when the feature has a plausible caching benefit. Stay silent otherwise — asking about caching for every write-only flow is noise.

Trigger the question when the feature involves:

- A read endpoint expected to be accessed significantly more than written
- A computed value that depends on multiple aggregates, external APIs, or non-trivial queries
- A public resource (unauthenticated) that can be served at the edge
- A rate limiter, idempotency guard, or deduplication mechanism

When triggered, ask the developer:

1. What is the maximum tolerated staleness? (e.g. "5 seconds", "1 minute", "not critical — hours are fine")
2. What write triggers invalidation? (e.g. "any update to the board", "a new member joins")
3. Is the response shared across users, or per-user?

Record the answers in the spec's Business Rules section. The `refine-specs` step later translates them into a concrete Redis key, TTL, and invalidation hook under Technical Details.

If the feature is clearly a write-only flow, a one-off admin action, or otherwise not caching-relevant, do not ask.

---

## What the reviewer checks

Caching rules are enforced during review via the backend reviewer checklist (see [`backend-review-checklist.md`](backend-review-checklist.md) → "Caching"). The checklist is the authoritative surface — if a rule appears here and not in the checklist, file a minor and update the checklist in the same commit.
