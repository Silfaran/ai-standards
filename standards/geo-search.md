# Geo & Search Standards

## Philosophy

- Geographic data is structured data with hard precision rules. A user's location stored as `"Madrid"` is unsearchable; stored as `geography(Point, 4326)` it is queryable, indexable, and joinable to administrative boundaries.
- The search index is an opinion about the data, not a copy of it. The source of truth stays in the operational store; the index is rebuildable. A bug that loses the index is recoverable; a bug that loses the database is an incident.
- Ranking is a function the team owns. The system computes a numeric score internally for ordering and recommendation, and surfaces qualitative labels to users — not the raw number. The two evolve at different rates: the score iterates weekly, the labels iterate quarterly.
- Postgres FTS first, dedicated search engine when measured insufficient. The default stack already covers most needs at zero operational cost — see `tech-stack.md`. Premature Elasticsearch is the most common over-engineering in this domain.
- Distance is a tie-breaker, not the answer. "Closest plumber" is rarely what the user wants — they want "available plumber, qualified for my job, who happens to be close enough". Geography is one signal among many.

---

## When this standard applies

This standard applies whenever the system:

- Stores a location (a point, a service area, an address geocoded into coordinates)
- Searches by proximity ("within 10 km", "in this city", "in this polygon")
- Searches across structured + textual fields with a ranked result list
- Computes a compatibility / matching score between a query and candidates
- Renders maps in the frontend (markers, areas, route hints)

If none is true, this standard is read-only and the project may rely on simple `LIKE` queries indexed by trigrams (`pg_trgm`) without engaging the geo machinery.

---

## Vocabulary

| Term | Meaning |
|---|---|
| **Point** | A pair (longitude, latitude) in WGS-84 (SRID 4326), the de-facto standard for web mapping |
| **Geography vs Geometry** | PostGIS distinction: `geography` is sphere-aware (correct distances over long ranges), `geometry` is planar (faster, accurate only over small areas with appropriate projection). Default to `geography` for "real distance" needs |
| **Bounding box (bbox)** | A rectangle (`min_lon, min_lat, max_lon, max_lat`) used to pre-filter candidates before exact-distance computation |
| **GiST index** | PostgreSQL spatial index supporting `ST_DWithin`, `ST_Intersects`, etc. on `geography`/`geometry` columns |
| **FTS (Full-Text Search)** | Tokenization + stemming + ranking over text fields. In Postgres: `tsvector` + `tsquery` with a language-aware configuration |
| **Score** | An internal numeric ranking value, never displayed verbatim to users |
| **Label** | A qualitative output (e.g. "Highly recommended", "Available now") derived from the score and shown to users |
| **Match** | The decision unit: a candidate is a match iff its score crosses a configured threshold |

---

## Storage: location as a first-class column

A location is `geography(Point, 4326)`. Two `numeric` columns for `lat`, `lon` are forbidden — they break GiST indexing and require manual distance math.

```sql
CREATE TABLE professionals (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    tenant_id UUID NOT NULL,
    -- ...other columns
    location_point geography(Point, 4326),
    service_radius_meters INTEGER,                -- nullable when professional declares a polygon instead
    service_area geography(MultiPolygon, 4326)    -- nullable; one of (point+radius) OR (area) is set, not both
);

CREATE INDEX idx_professionals_tenant_location ON professionals USING GIST (tenant_id, location_point);
CREATE INDEX idx_professionals_tenant_area ON professionals USING GIST (tenant_id, service_area);
```

Rules:

- The column type is `geography(Point, 4326)` — explicit SRID, explicit shape. `geography` (no spec) is forbidden.
- Indexes are GiST and INCLUDE the tenant_id as the leading equality predicate (planner uses both — confirmed via `EXPLAIN`).
- A point AND a service area is a defect — pick one per row, document the choice. A `CHECK` constraint enforces:

```sql
ALTER TABLE professionals ADD CONSTRAINT chk_one_geo_form CHECK (
    (location_point IS NOT NULL AND service_area IS NULL)
    OR (location_point IS NULL AND service_area IS NOT NULL)
);
```

- Geocoding (address → point) happens at the boundary, in a `GeocoderGatewayInterface` (Domain). The application stores the geocoded point + the geocoder source + the geocode timestamp:

```sql
ALTER TABLE professionals
    ADD COLUMN geocoded_at TIMESTAMPTZ,
    ADD COLUMN geocoder_source TEXT;     -- 'mapbox', 'nominatim', 'manual'
```

A point with a `manual` source is never re-geocoded automatically; a point with an automatic source is re-geocoded when the address changes.

---

## Geographic queries

### Radius (point + meters)

```sql
SELECT id, name, ST_Distance(location_point, $1::geography) AS distance_m
FROM professionals
WHERE tenant_id = $2
  AND ST_DWithin(location_point, $1::geography, $3)        -- $3 = radius in meters
ORDER BY distance_m
LIMIT 50;
```

Rules:

- `ST_DWithin` MUST come before any non-spatial filter that is not on `tenant_id`. The GiST index uses the bbox derived from `ST_DWithin` to prune; later filters narrow further on indexed columns.
- `ST_Distance` for ordering ONLY. Never use `<-> operator` (KNN) on `geography` — it is a `geometry` operator and silently drops to planar math.
- The radius is bounded at the API layer. Unlimited "anywhere within Europe" queries are denied with 422; the project's max radius is documented per use case.

### Bounding box (map viewport)

```sql
SELECT id, name, ST_AsGeoJSON(location_point) AS geojson
FROM professionals
WHERE tenant_id = $1
  AND location_point && ST_MakeEnvelope($2, $3, $4, $5, 4326)::geography
LIMIT 500;
```

Rules:

- The `&&` operator uses the GiST index to filter by bbox — fastest pre-filter for map renders.
- A viewport that exceeds the project's max bbox area returns 422 (zoomed-out queries return millions of points and never end well).
- The frontend de-duplicates by clustering at the rendering layer (see "Frontend rendering" below).

### Polygon containment (within a city / region / drawn area)

```sql
SELECT id, name
FROM professionals
WHERE tenant_id = $1
  AND ST_Intersects(service_area, $2::geography)
LIMIT 100;
```

Rules:

- The polygon parameter ($2) is validated at the boundary (well-formed, sane area). A polygon larger than the project's max area is rejected.
- Intersect vs Within is a domain decision: a service area that *touches* the query polygon may or may not count. The choice is per use case, recorded.

---

## Full-text search (Postgres FTS)

The default stack uses Postgres FTS with `pg_trgm` for typo tolerance. Other engines (Meilisearch, Typesense, OpenSearch) come in only when a measured limitation forces them — see `tech-stack.md` Search section.

### `tsvector` columns

```sql
ALTER TABLE professionals
    ADD COLUMN search_vector tsvector
        GENERATED ALWAYS AS (
            setweight(to_tsvector('simple', coalesce(display_name, '')), 'A')
            || setweight(to_tsvector('spanish', coalesce(headline, '')), 'B')
            || setweight(to_tsvector('spanish', coalesce(bio, '')), 'C')
        ) STORED;

CREATE INDEX idx_professionals_search ON professionals USING GIN (search_vector);
```

Rules:

- The `tsvector` column is `GENERATED ALWAYS AS (...) STORED` — Postgres keeps it in sync; no application code maintains it.
- Language configuration matches the source-locale of the field. Multi-language content (`i18n.md`) generates one `tsvector` per locale (`search_vector_es`, `search_vector_en`) — each indexed independently.
- Weights (`A` > `B` > `C` > `D`) reflect ranking importance: `display_name` matches outrank `bio` matches.

### Querying with rank + typo tolerance

```sql
WITH q AS (
    SELECT plainto_tsquery('spanish', $1) AS tsq,
           $1 AS raw
)
SELECT
    p.id,
    p.display_name,
    ts_rank_cd(p.search_vector, q.tsq) AS text_score,
    similarity(p.display_name, q.raw) AS name_similarity
FROM professionals p, q
WHERE p.tenant_id = $2
  AND (
      p.search_vector @@ q.tsq
      OR p.display_name % q.raw                              -- pg_trgm fuzzy match
  )
ORDER BY text_score DESC, name_similarity DESC
LIMIT 50;
```

Rules:

- `plainto_tsquery` for user input — never `to_tsquery` directly (it requires query operators that users do not type).
- Typo tolerance via `pg_trgm`'s `%` operator AND `similarity()` for ordering. The threshold is set per use case via `SET pg_trgm.similarity_threshold = 0.3` at session level.
- Phrase queries use `phraseto_tsquery`. Wildcard / prefix search uses `to_tsquery('foo:*')` — but only for cases the project has explicitly opted into.

---

## Combined geographic + text + structured search

Most real queries combine all three. The pattern is a single CTE-based query, not three sequential queries:

```sql
WITH candidates AS (
    -- 1. Geographic filter (most selective for "near me" queries)
    SELECT id
    FROM professionals
    WHERE tenant_id = $1
      AND ST_DWithin(location_point, $2::geography, $3)
),
text_filtered AS (
    -- 2. Text filter on the geo-narrowed set
    SELECT
        p.id,
        ts_rank_cd(p.search_vector, plainto_tsquery('spanish', $4)) AS text_score
    FROM professionals p
    JOIN candidates c USING (id)
    WHERE p.search_vector @@ plainto_tsquery('spanish', $4)
)
-- 3. Structured filter + final ordering with composite score
SELECT
    p.id,
    p.display_name,
    tf.text_score,
    ST_Distance(p.location_point, $2::geography) AS distance_m
FROM professionals p
JOIN text_filtered tf USING (id)
WHERE p.is_available = TRUE
  AND p.validation_level >= $5
ORDER BY tf.text_score DESC, distance_m ASC
LIMIT 50;
```

Rules:

- The most selective predicate goes FIRST in the CTE chain. For "near me + with text", geography is usually most selective.
- `EXPLAIN (ANALYZE, BUFFERS)` is mandatory on any new search query in PR review — the planner choice is part of the diff.
- A search query whose plan includes a `Seq Scan` on a non-trivial table is a defect. Indexes are added until the planner uses them.
- A search endpoint that returns more than a few hundred rows is a paginated endpoint (see `api-contracts.md` AC-002/003).

---

## Scoring engine (matching)

When the use case is "rank candidates against a demand" (a job request, a recommendation, a "best match" surface), the system needs a scoring engine. The engine is a Domain service:

```php
namespace App\Domain\Match;

interface MatchScoreCalculator
{
    /** @return iterable<MatchResult> */
    public function execute(MatchRequest $request, iterable $candidates): iterable;
}
```

Rules:

- `MatchRequest` carries the demand-side inputs (the query, the location, the requirements).
- Each candidate yields a `MatchResult` containing the numeric score and a list of "explanations" (which dimensions contributed and how much). The explanations are the input to the user-facing labels.
- The engine is pure. No DB calls, no LLM calls, no I/O. Inputs are pre-loaded by the application service that orchestrates the search.
- Weights are configuration, not code. They live in `{project-docs}/match-weights.md` and are loaded into the engine at construction. A weight change is a config change, version-tagged, observable.

### Score → label translation

Internal score is numeric; user-facing output is qualitative. The mapping is centralised:

```php
final readonly class MatchLabelResolver
{
    public function execute(float $score, MatchResult $result): MatchLabel
    {
        return match (true) {
            $score >= 0.85 => MatchLabel::HIGHLY_RECOMMENDED,
            $score >= 0.70 => MatchLabel::GOOD_MATCH,
            $score >= 0.50 => MatchLabel::POSSIBLE_MATCH,
            default        => MatchLabel::WEAK_MATCH,
        };
    }
}
```

Rules:

- Labels are an enum, finite, translated via `i18n.md`.
- The score is NEVER serialised to the API response. The label IS — together with the relevant explanations.
- A change to the score → label thresholds is a UX change, reviewed and announced — users get used to "highly recommended" meaning something specific.

### Explanations (transparency)

Each result includes structured reasons:

```json
{
  "professional_id": "...",
  "label": "highly_recommended",
  "explanations": [
    { "kind": "specialty_match", "weight": 0.4 },
    { "kind": "distance_under_5km", "weight": 0.2 },
    { "kind": "availability_now", "weight": 0.15 },
    { "kind": "high_validation_level", "weight": 0.1 }
  ]
}
```

The frontend turns the explanation kinds into translated phrases ("Specialises in your trade", "Less than 5 km away"). The user sees WHY, not the raw weights.

---

## Caching search results

Search responses are cacheable when the inputs are bounded and the freshness requirement allows it. See `caching.md` for HTTP cache semantics (CA-001..CA-011).

Rules:

- Public-without-auth searches (a category page) cache at the CDN with `Cache-Control: public, max-age=60` and `Vary: Accept-Language`.
- Per-user searches do NOT share a cache. The cache key (Redis or HTTP) includes the subject id.
- Cache keys for search responses include the FULL bounded input set — query string, filters, location, locale, page. A change in any field is a different key.
- Score weights changes invalidate caches via a version suffix (`v3:...`).

---

## Frontend rendering

Maps and search lists are presentation; the rules are about not over-fetching and not leaking PII.

Rules:

- The map fetches a bounding-box query, not "everything". As the user pans, a debounced `ref` triggers a new fetch.
- Markers are clustered client-side when count > 50 in viewport. `vue-leaflet` + `leaflet.markercluster` (or equivalent) covers most cases — the choice lives in `tech-stack.md`.
- Search input is debounced (250 ms typical). Each keystroke does NOT issue a request.
- Empty result state is distinct from filtered-empty — see frontend `empty-loading-error-states` skill.
- Coordinates of a USER appearing on a map are PII (`gdpr-pii.md` GD-005) — they are NEVER inlined into HTML; they are fetched on demand from a private endpoint with a signed bbox.

---

## When to graduate to a dedicated search engine

Stay on Postgres FTS + GiST until at least one of the following is measured:

- p95 search latency exceeds the project's SLO under expected load
- Index size exceeds RAM available for caching
- The product needs language features Postgres lacks (faceted search with N facets, custom analyzers per language family, real-time relevance tuning, vector embeddings as a first-class column)
- Cross-table search becomes an unavoidable requirement

When one of these triggers, write an ADR ("Move {use_case} from Postgres FTS to {Meilisearch / OpenSearch / Typesense}"), documented per project. Until the trigger fires, the dedicated engine is over-engineering.

---

## Observability

| Span attribute | Required | Example |
|---|---|---|
| `search.kind` | yes | `geo_radius` / `text_only` / `geo_text` / `match` |
| `search.candidates_pre_filter` | yes | `1247` |
| `search.candidates_post_filter` | yes | `42` |
| `search.results_returned` | yes | `20` |
| `search.score_weights_version` | when match | `v3` |
| `search.duration_ms` | yes (also a metric) | `42` |

NEVER as span attribute: the user's exact coordinates, the search query text (PII risk; "John Doe Madrid" tells everything).

| Metric | Labels |
|---|---|
| `search_requests_total` | `kind`, `outcome` (success / empty / 422 / 5xx) |
| `search_duration_seconds` | `kind`, histogram |
| `search_candidates_filtered_total` | `kind` (counts pre/post) |
| `match_label_distribution_total` | `label` (highly_recommended / good_match / possible_match / weak_match) — visualises product health |

A gradual shift in `match_label_distribution_total` toward `weak_match` indicates the candidate pool is degrading or the demand surface is changing — early warning before users complain.

---

## Anti-patterns (auto-reject in review)

- Two columns `lat`, `lon` instead of `geography(Point, 4326)`.
- Missing GiST index on a queried geography column.
- `ST_Distance` in the `WHERE` clause without `ST_DWithin` (no index use, full table scan).
- A search query whose `EXPLAIN` shows `Seq Scan` on the candidate table.
- Surfacing the raw match score in the API response.
- Hardcoding score weights in PHP (must be config).
- Loading the geocoder SDK into a handler — it lives behind a `GeocoderGatewayInterface`.
- A map endpoint that returns more than the documented max points per request without pagination/clustering.
- Storing a user's exact coordinates in HTML or `localStorage`.
- Auto-graduating to Elasticsearch / OpenSearch without an ADR pointing at measured triggers.

---

## What the reviewer checks

Geo & search rules are enforced during review via the backend reviewer checklist (see [`backend-review-checklist.md`](backend-review-checklist.md) → "Geo & search") and the frontend reviewer checklist (see [`frontend-review-checklist.md`](frontend-review-checklist.md) → "Geo & search"). The checklists are the authoritative surface — if a rule appears here and not in the checklist, file a minor and update the checklist in the same commit.
