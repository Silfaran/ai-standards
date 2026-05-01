# Critical path — Geo / search / matching feature

Use when the diff stores locations, searches by proximity, ranks candidates with a scoring engine, or renders a map. Combine with [`auth-protected-action.md`](auth-protected-action.md) for any tenant-scoped query.

## When to load this path

**PRIMARY trigger** (load this path as core when):
- A new column of type `geography(Point, 4326)` or `tsvector`
- A new GiST or GIN index in a migration
- A new `MatchScoreCalculator` Domain service or `MatchLabelResolver`
- A new endpoint accepting `bbox`, `radius`, or proximity parameters
- A new `{project-docs}/match-weights.md` entry or version bump

**SECONDARY trigger** (load only when no primary path covers the diff already):
- A new `GeocoderGatewayInterface` adapter or geocoding entry-point
- A frontend Map / search-input component
- A new pg_trgm-based fuzzy match query

**DO NOT load when**:
- The diff only modifies tests
- The diff only modifies `*.md`
- The "search" is a simple `LIKE` / `ILIKE` filter on a non-geo, non-text-search column (regular SQL applies, no path needed)

## Backend

### Storage
- GS-001 Locations as `geography(Point, 4326)` — never two `numeric` columns
- GS-002 GiST indexes leading with `tenant_id` (verified with EXPLAIN)
- GS-003 Row has `point + radius` OR `service_area`, not both — CHECK enforces
- GS-004 Geocoding behind `GeocoderGatewayInterface`; persists `geocoded_at` + `geocoder_source`; manual sources never re-geocoded automatically

### Geographic queries
- GS-005 `ST_DWithin` (not `ST_Distance` in WHERE) for radius — uses GiST
- GS-006 KNN `<->` is forbidden on `geography` (drops to planar math)
- GS-007 Bounding-box with `&&` + `ST_MakeEnvelope`; max bbox area bounded at API
- GS-008 Combined geo + text + structured queries are a single CTE chain ordered by selectivity
- GS-009 `EXPLAIN (ANALYZE, BUFFERS)` mandatory in PR description; Seq Scan on non-trivial table = defect

### Full-text search
- GS-010 `tsvector` columns `GENERATED ALWAYS AS ... STORED` with GIN index
- GS-011 One `tsvector` per locale matching language config (i18n.md)
- GS-012 User input via `plainto_tsquery` / `phraseto_tsquery` — never `to_tsquery`
- GS-013 Typo tolerance via `pg_trgm` `%` + `similarity()`

### Matching engine
- GS-014 `MatchScoreCalculator` is a Domain service, pure (no DB / LLM / I/O); inputs pre-loaded
- GS-015 Score weights are CONFIG (`{project-docs}/match-weights.md`); never hardcoded; weight changes are version-tagged
- GS-016 API responses NEVER serialize the raw numeric score — qualitative `MatchLabel` enum + structured `explanations` only
- GS-017 Score → label mapping centralised in `MatchLabelResolver`

### Pagination & cache
- GS-018 Search endpoints paginated per AC-002 / AC-003
- GS-019 Public-without-auth searches cache at CDN with `Vary: Accept-Language`; per-user keyed by subject id; weights version part of key

### Privacy
- GS-020 User exact coordinates are PII (GD-005) — never logged, never inlined into HTML
- AZ-001 Voter check on map endpoints

### Observability
- GS-021 Span attributes: `search.kind`, candidates pre/post filter, results returned, score_weights_version, duration_ms — NEVER query text or coordinates
- GS-022 Metrics: `search_requests_total`, `search_duration_seconds`, `search_candidates_filtered_total`, `match_label_distribution_total` — bounded labels

### Graduation
- GS-023 Move to a dedicated search engine only via ADR pointing at measured triggers (p95 SLO breach, index > RAM, language gaps, vector embeddings)

### Hard blockers
- BE-001 Quality gates green
- LO-001 No unredacted sensitive fields (coordinates) in logs

## Frontend (when rendering a map / search list)

- GS-024 Map fetches bbox-bounded queries; pan/zoom triggers debounced re-fetch
- GS-025 Markers clustered when count > 50 in viewport
- GS-026 Search inputs debounced (~250 ms)
- GS-027 User coordinates never inlined into HTML; never in `localStorage`
- GS-028 Result lists render the qualitative `MatchLabel` and `explanations` translated via i18n; NEVER the raw score

## Coverage map vs full checklist

This path covers these sections of `backend-review-checklist.md` / `frontend-review-checklist.md`:

- §Geo / search — GS-001..GS-023 (PostGIS storage, geo queries, FTS, MatchScoreCalculator, label resolver, pagination, privacy, observability, graduation)
- §Authorization (carried over) — AZ-001
- §Hard blockers — BE-001, LO-001
- §Frontend Geo / search — GS-024..GS-028

This path does NOT cover. Load the corresponding checklist section ONLY when the diff touches:

- `tests/` directory → load §Testing
- The CRUD shape of the search endpoint (controller, validation, OpenAPI) → load `crud-endpoint.md` (path)
- Cache headers / Redis keys for search results → load §Caching
- Migration adding the geo-indexed table → load §Migrations (DM-*)

## What this path does NOT cover

- Authorization → [`auth-protected-action.md`](auth-protected-action.md)
- LLM-driven matching variants → [`llm-feature.md`](llm-feature.md)
- The signed-search audit trail → [`audit-log.md`](../audit-log.md) (full standard, no critical-path subset yet)
