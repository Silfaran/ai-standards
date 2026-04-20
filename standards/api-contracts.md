# API Contracts & Breaking Changes

## Philosophy

- The API contract is a promise to every caller. Breaking it without a migration path is a bug, regardless of how "small" the change feels.
- A contract is everything a caller can observe: URL, method, query params, request body shape, response body shape, status codes, headers, and error payload format.
- Additive is safe, subtractive and re-typed is not. Every change is evaluated against that binary before anything ships.
- The contract lives in code, not in a wiki. OpenAPI is the single source of truth; anything not in OpenAPI does not exist from a contract perspective.

---

## What counts as a breaking change

### Breaking (requires the full protocol below)

- Removing an endpoint, a method, a field, a header, a query parameter, or a status code that callers may depend on
- Renaming any of the above
- Changing the type of a response field (e.g. `string` → `number`, `string` → `string[]`, scalar → object)
- Narrowing the accepted values of a request field (new required field, tighter enum, shorter max length)
- Changing the shape of the error payload — including adding or renaming keys under the error envelope
- Changing default sort order, default pagination size, or default filter when callers are likely to rely on it
- Changing authentication semantics (e.g. scope required, token claim consumed)
- Changing HTTP semantics (`200` → `204`, `201` → `200`, `204` → `200 + body`)

### Non-breaking (safe, still requires CHANGELOG and tests)

- Adding a new endpoint, method, optional query parameter, or optional request body field
- Adding a new field to a response body — but **only** if consumers are known to ignore unknown fields (the frontend deserializers defined in [`frontend.md`](frontend.md) do; out-of-org clients may not)
- Adding a new status code that is not used by the previous contract (e.g. `202` on an endpoint that previously returned `200` only)
- Relaxing a validation rule (longer max length, wider enum with a backward-compatible default)
- Performance changes that do not alter the response shape

A change that looks safe in isolation but removes a field from one response may still be breaking if that field is the `id` a caller uses as a cache key. Judge by caller impact, not by the shape of the diff.

---

## Versioning strategy

The platform uses URL-based major versioning. No header-based or content-negotiation versioning — URL paths are explicit, debuggable from a browser, and visible in server logs.

```
/api/v1/boards
/api/v1/boards/{id}/members
```

Rules:

- Every public endpoint lives under `/api/v{major}/...`. Internal endpoints (`/internal/...`, `/health/...`) are versionless by convention.
- Minor and patch iterations are additive — no version bump.
- A new major version is introduced **only** when a breaking change is unavoidable. The previous major is not deleted in the same release.
- Two major versions may coexist. Three should not. Before introducing `v3`, plan the removal of `v1`.
- The `/api/v1` → `/api/v2` switch is a migration, not a rename. `v1` keeps serving until the deprecation window closes.

---

## Breaking-change protocol

Every breaking change follows these steps in order. Skipping a step is a contract violation.

1. **Detect at spec time.** The Spec Analyzer flags the change as breaking and asks the developer whether a non-breaking alternative exists (add a new field, new endpoint, feature flag). If there is a non-breaking path, take it.
2. **Deprecate the old shape.** The old endpoint/field continues to work and gains:
   - A `Deprecation: <RFC 3339 date>` response header naming the removal date
   - A `Sunset: <RFC 3339 date>` response header naming the sunset date
   - A `Link: <new-url>; rel="successor-version"` header pointing to the new shape when applicable
   - An entry in the OpenAPI spec marking the field/endpoint with `deprecated: true`
3. **Introduce the new shape side by side.** The new field/endpoint lives alongside the deprecated one. No response ever returns both under the same key — the new name is distinct.
4. **Log usage.** Every request that hits a deprecated endpoint or sends a deprecated field emits a `warn` log with `event=api.deprecated.usage`, `caller` (auth subject or IP), and the deprecated surface. Without this log, the deprecation window ends blindly.
5. **Announce.** The CHANGELOG entry for the release lists the deprecation, the sunset date, and the migration path. A feature spec under the relevant aggregate documents the migration for internal readers.
6. **Wait.** The deprecation window is **at least 30 days** for internal-only APIs and **at least 90 days** for any surface consumed by a client outside this repo. The window is measured from the first release that sets `Deprecation` / `Sunset` headers, not from the date the code landed.
7. **Remove.** On or after the sunset date, with deprecation logs showing zero callers for at least the last 7 days, the deprecated surface is removed. Removal is its own commit with `refactor(api)!:` prefix and a `BREAKING CHANGE:` trailer.

### Emergency exception

Security fixes (CVE, data leak, auth bypass) may shortcut steps 2–6 when the fix is incompatible with the old contract. The deprecation window collapses to the shortest viable period; the reason is documented in the security advisory, not as a precedent for future work.

---

## Backend-to-frontend contract

Backend and frontend live in separate repositories but share one contract. The rules below keep them in sync without either side guessing.

### OpenAPI is the contract

- Every controller carries complete OpenAPI/Swagger annotations — request body schema, response schemas (one per status code), error envelope, query params, headers.
- The backend CI job generates `openapi.json` on every main-branch build and uploads it as an artifact.
- The frontend CI job fetches the latest published `openapi.json` for the services it depends on and fails the build if the types it uses have changed in a breaking way. The generator lives in [`frontend.md`](frontend.md) → API types.
- No frontend type for a backend payload is hand-written when the OpenAPI schema covers it. Hand-written types drift, generated ones do not.

### Payload conventions

- API payloads are `snake_case`, as per [`backend.md`](backend.md) and [`frontend.md`](frontend.md). Do not mix casing in a single payload.
- Timestamps use RFC 3339 UTC (`2026-04-20T09:30:00Z`). Never Unix epoch, never locale-specific formats.
- Money uses the minor unit as an integer (`"amount_cents": 1995`) with a sibling `"currency": "EUR"` field. Never `float` for money.
- Enums in payloads are `snake_case` strings (`"status": "in_progress"`). Frontend narrows them with a TypeScript union.
- Nullable fields are explicit in the schema (`nullable: true`) and present in the response even when `null` — omitting a nullable field is a contract violation.

### Response envelope

Collection endpoints follow the envelope defined in [`performance.md`](performance.md):

```json
{ "data": [...], "meta": { "total": 84, "page": 1, "per_page": 20 } }
```

Error responses follow one envelope, defined once and reused by every endpoint. Changing the error envelope is a breaking change for every caller of every endpoint — approach with care.

### Field-level change rules

- Adding a field: safe, land in backend first, then frontend consumes it in a follow-up.
- Removing a field: full breaking-change protocol. `optional` / `nullable` is not a back door around this.
- Renaming a field: treated as add + deprecate + remove. Never an in-place rename on a live endpoint.
- Changing the type of a field: same as renaming — the new type lives under a new field name until the old one is sunset.

### Release coordination

- The backend releases the additive change first. The frontend consumes it in the next release.
- The backend never removes a deprecated field before confirming all internal frontends have migrated (deprecation log counts as evidence).
- Frontend features that require a non-yet-released backend change are blocked, not merged behind a feature flag that calls a non-existent endpoint.

---

## What the reviewer checks

Contract rules are enforced during review via the backend reviewer checklist (see [`backend-review-checklist.md`](backend-review-checklist.md) → "API Contracts") and the frontend reviewer checklist ("API Contracts"). When this standard changes, update the matching checklist entries in the same commit.
