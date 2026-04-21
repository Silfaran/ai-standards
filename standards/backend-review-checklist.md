# Backend Review Checklist

Closed list of verifiable rules for the Backend Reviewer agent. Each rule maps to a single, observable check on the diff. If a rule needs context, the source standard is cited at the end.

The reviewer must NOT re-read the full standards — this checklist is the authoritative review surface. If a rule seems missing for the current diff, request it as a `minor` and flag it for inclusion in a future checklist update.

> **Quality gates pre-requisite.** Mechanical checks (PHPStan level 9, PHP-CS-Fixer, `composer validate`, `composer audit`, migrations on clean Postgres, PHPUnit) are enforced by the pre-commit hook and GitHub Actions CI before the reviewer sees the diff. See [`quality-gates.md`](quality-gates.md). If CI is red, reject immediately with status `QUALITY-GATE-FAILED` and point the developer to the failing job — do not start the full review.

---

## Hard blockers (auto-reject, regardless of iteration)

- [ ] Quality gates CI is green for the current commit (PHPStan L9, PHP-CS-Fixer, composer audit, migrations, PHPUnit)
- [ ] PHPStan level 9 passes (zero errors) — confirm via CI, no baseline entries added to hide violations
- [ ] PHP-CS-Fixer passes (zero violations) — confirm via CI
- [ ] No string concatenation/interpolation in SQL — DBAL parameterized queries only
- [ ] No CORS `*` in `nelmio_cors.yaml` — explicit origin allowlist via env
- [ ] No secrets committed (`.env`, keys, tokens, fixtures with real credentials)
- [ ] No SSL verification disabled (`verify => false`, `--insecure`)
- [ ] No internal details leaked in error responses (stack traces, file paths, SQL errors)
- [ ] No log entries with unredacted sensitive fields (`password`, `token`, `access_token`, `refresh_token`, `secret`, `api_key`, `credential`, `card_number`)
- [ ] Migrations executed previously are NOT modified — new migration created instead

## Architecture (Hexagonal + DDD + CQRS)

- [ ] Folder layout: `Domain/`, `Application/`, `Infrastructure/` boundaries respected
- [ ] Commands and queries are separated — never mixed in the same handler
- [ ] Handlers call services (Domain or Application) or repositories directly — never inline extracted logic
- [ ] Services expose exactly ONE public method (`execute`) plus the constructor — zero exceptions. Any additional method is `private` and called from `execute`. Multi-public services (twin signatures, overloaded variants, "convenience wrappers") split into separate classes
- [ ] `[critical]` Service placement: domain services (pure rules) live in `src/Domain/Service/{Aggregate}/`; application services (use-case orchestrators) live in `src/Application/Service/{Aggregate}/`. A service under `Domain/Service/` MUST NOT import from `App\Infrastructure\*`, MUST NOT depend on framework classes beyond the ones it reads (PSR interfaces are fine), and MUST NOT orchestrate side effects (no event publishing, no email sending, no transactions). If it does any of these — move to `Application/Service/`
- [ ] `[critical]` Fast disambiguator for Domain-vs-Application placement: a service that injects `Doctrine\DBAL\Connection`, `MessageBusInterface`, or any other transactional/side-effect primitive is Application by construction. A domain service MUST NOT hold any of these — if it does, move to `Application/Service/` regardless of what the name suggests
- [ ] Services are declared `readonly class` — NOT `final` (PHPUnit 13 `createMock()` compatibility). `readonly` preserves immutability without blocking test doubles
- [ ] Finder services (throw-on-miss aggregate lookups) live in Domain — `src/Domain/Service/{Aggregate}/{Aggregate}FinderService.php`
- [ ] Handlers are not duplicated by a parallel `{Action}UseCase` class in `Application/Service/` — the handler IS the application service for that use case
- [ ] Services inject repository INTERFACES (Domain), not implementations (Infrastructure)
- [ ] Services MAY depend on other services — duplicating logic that already exists in another service is a violation (prefer composition). A domain service NEVER composes an application service (inverted-layer violation)
- [ ] No inline `find + null check + throw` in handlers — a `{Aggregate}FinderService` owns the throw-on-miss lookup and the handler calls it
- [ ] Repository interfaces expose ONLY nullable lookups (`findById(Id): ?Entity`, `findByEmail(...): ?Entity`, …) — throw-on-miss methods (`getById`, `findOrFail`) do NOT live on the repository
- [ ] Every aggregate that has a throw-on-miss need has a `{Aggregate}FinderService` under `src/Domain/Service/{Aggregate}/` (canonical precedent: `UserFinderService` in login-service)
- [ ] Finder services follow the one-execute rule: one finder = one lookup = one `execute()` method. Variant lookups live in separate `{Aggregate}FinderBy{Key}Service` classes (e.g. `UserFinderByEmailService`) — never a second method on an existing finder
- [ ] Handlers do NOT orchestrate 2+ repositories for a single domain operation — logic extracted to a service (cascade deletes, cross-aggregate updates → typically Application)
- [ ] Handlers do NOT contain authorization/ownership checks inline when the same check repeats across handlers — delegated to a shared domain service
- [ ] Handlers do NOT contain branching business logic ("if exists reactivate else create", multi-step state transitions) — extracted to a service (Application if it orchestrates side effects; Domain if it's a pure rule)
- [ ] Domain layer has zero Symfony/Doctrine imports
- [ ] Aggregates use `static create()` (new, raises events) and `static from()` (rehydration, no events)
- [ ] Value objects, commands, queries, DTOs use `private __construct` + `static from()`

## Controllers

- [ ] Each controller extends `AppController`
- [ ] One controller per command/query — no multi-action controllers
- [ ] Controllers only call `dispatchCommand()` / `dispatchQuery()` — never call services directly
- [ ] No business validation in controllers — only structural (JSON valid, fields present, types correct)
- [ ] Type-guard the request: `is_string()`, `is_int()`, `is_array()` — never trust `$request->getContent()`
- [ ] Returns `400` for malformed JSON, `422` for missing/wrong-type fields
- [ ] Trims string inputs (names, emails) — never trims passwords
- [ ] Every controller has OpenAPI/Swagger annotations
- [ ] `services.yaml` injects `$commandBus: '@command.bus'` and `$queryBus: '@query.bus'` by name

## Validation layering

- [ ] Structural validation lives in the controller
- [ ] Business invariants live in Value Objects (using `webmozart/assert`)
- [ ] Domain exceptions exist for each business rule violation and are mapped in `ApiExceptionSubscriber`
- [ ] No `match` arm missing in `ApiExceptionSubscriber` for any new domain exception
- [ ] No domain exception returns 500 — every expected failure has a mapped HTTP status

## Database & migrations

- [ ] New tables use `id UUID DEFAULT gen_random_uuid()` as PK
- [ ] Snake_case for tables and columns
- [ ] Index added for every column appearing in `WHERE`, `ORDER BY`, or as a UUID reference (the project's no-FK ADR means references are not indexed automatically — see `{project-docs}/decisions.md`)
- [ ] No FOREIGN KEY / REFERENCES / ON DELETE clauses — per the project's no-FK ADR
- [ ] On large tables: `CREATE INDEX CONCURRENTLY` instead of `CREATE INDEX`
- [ ] On large tables: 3-step pattern for `NOT NULL` columns (add nullable → backfill → add NOT NULL)
- [ ] No service queries another service's tables — each service owns its DB
- [ ] Phinx seeds added for every new aggregate (realistic local data)

## Data migrations strategy

- [ ] Migration is classified as non-breaking or breaking using the lists in `data-migrations.md` — classification is visible in the commit message or PR description
- [ ] Breaking changes decomposed into expand → migrate → contract phases; the phase is declared in the commit message, and each phase is its own commit
- [ ] Contract-phase commits (dropping / renaming / re-typing a populated column or table) use `refactor(db)!:` prefix and a `BREAKING CHANGE:` trailer
- [ ] Compatibility matrix holds: the previous application version continues to work correctly against the new schema for the duration of the deploy window
- [ ] No removal, rename, or non-widening type change of a column/table/index happens in the same migration that creates its replacement
- [ ] No `NOT NULL` added to a populated column without a completed backfill in a prior phase
- [ ] Backfills on tables larger than ~10k rows run as a background job (Symfony console command), not inline in the Phinx migration
- [ ] Background-job backfills are idempotent, batched (≤10k rows per commit), ordered by primary key, and report progress (row count, errors, last processed id)
- [ ] The migration is idempotent — running it twice leaves the schema in the same state
- [ ] PR description answers "how do we undo this if it lands bad?" in one sentence — "revert the commit" is not acceptable for breaking migrations
- [ ] No cross-service database access introduced — new data dependencies use the owning service's API or a domain-event projection

## Repositories & queries

- [ ] All multi-row repository methods accept `int $limit = 20, int $offset = 0` — no unbounded list queries
- [ ] No queries inside loops (N+1) — use `IN (...)` batch queries
- [ ] `SELECT` only the columns the response needs (no `SELECT *` in API-facing queries)
- [ ] No raw SQL string interpolation — placeholders only

## API responses

- [ ] List endpoints accept `?page=` (1-based) and `?per_page=` (default 20, max 100)
- [ ] List responses include envelope: `{ "data": [...], "meta": { "total", "page", "per_page" } }`
- [ ] Status codes match: 200/201/204/400/401/403/404/409/422/429/500
- [ ] Error body shape: `{ "error": "message", "details": [...] }`

## Async messaging (when applicable)

- [ ] Every command/query/event/message implements `messageName()` returning `{service_name}.{type}.{snake_case_action}`
- [ ] Async transports use `messenger.transport.symfony_serializer` — never `PhpSerializer`
- [ ] `default_bus` set explicitly when multiple buses exist
- [ ] Cross-service messages: identical FQCN + constructor + `messageName()` in both services
- [ ] `composer.json` and `composer.lock` in sync after dependency changes

## Caching

- [ ] Every `GET` endpoint sets an explicit `Cache-Control` header — no framework default inherited silently
- [ ] Per-user authenticated reads use `private, no-cache`; sensitive per-user data (tokens, payments, settings) uses `no-store`
- [ ] Write endpoints (`POST`/`PUT`/`PATCH`/`DELETE`) explicitly set `no-store`
- [ ] Cacheable `GET` responses emit either `ETag` or `Last-Modified` and honor `If-None-Match` / `If-Modified-Since` with `304`
- [ ] `Vary` header declared on responses that differ by `Accept-Language`, `Authorization`, or any other header
- [ ] No auth/session/PII/token values written to a shared Redis cache without a per-user key
- [ ] Redis keys follow `{service}:{aggregate}:{operation}:{identifier}[:v{n}]`, lowercase, colon-separated
- [ ] Every Redis key has an explicit TTL — no infinite keys
- [ ] Every cached entity has an invalidation path on write (`$cache->delete(...)` in the write handler or via event listener) — TTL alone is not the invalidation strategy
- [ ] Hot keys have stampede protection documented (soft TTL + lock, jittered TTL, or background refresh) — choice recorded in the spec's Technical Details
- [ ] Redis is never the source of truth — data loss on cache restart must be recoverable from the primary store

## Secrets management

- [ ] Every env var in the diff that matches the secret categories in `secrets.md` has a row in the project's `secrets-manifest.md` (owner, category, environments, source, rotation, `last_rotated`)
- [ ] Secrets are read exclusively from process environment variables — no direct calls to provider SDKs (AWS Secrets Manager, Vault, etc.) from application code
- [ ] Every required secret read uses a fail-fast helper that throws when the value is missing or empty — no silent fallbacks to `null` or empty string
- [ ] `.env.example` lists every new secret with a placeholder (`CHANGE_ME`) and a category comment; no real value is committed
- [ ] No secret value is baked into a Docker image (`COPY .env`, `ENV SECRET=...` in a Dockerfile) or passed as a CLI argument
- [ ] No secret value is written to disk, logged, emitted as a span attribute, or used as a metric label
- [ ] Frontend diffs: no secret placed in a `VITE_*` variable (API keys, OAuth client secrets, private URLs, private identifiers)
- [ ] JWT/crypto key rotation uses a two-key window (current + previous) during the rotation window; the manifest lists both env vars
- [ ] Any new secret category extends the redaction list in `logging.md` in the same commit

## Logging

- [ ] LoggingMiddleware wired into `command.bus`, `event.bus`, `message.bus`
- [ ] Query buses do NOT have logging middleware
- [ ] Logs are structured JSON to `php://stdout` — never plain text
- [ ] In `when@test`, monolog handler `type: null` (no log noise in tests)
- [ ] No successful-handling logs (noise)
- [ ] Sensitive fields redacted in payloads (see hard blockers above)

## Observability

- [ ] Every inbound HTTP request has a server span with `http.route` (template, not rendered path), `http.request.method`, `http.response.status_code`, and `service.name` / `service.version`
- [ ] Every DBAL query emits a client span named by SQL operation (`SELECT boards`) — never with literal values
- [ ] Every command/query/message handler wraps execution in a Messenger span
- [ ] Every outgoing HTTP client call emits a span and propagates `traceparent` / `tracestate`
- [ ] No span attribute carries passwords, tokens (access/refresh/API), request bodies with PII, or full SQL with literals
- [ ] Every log line includes `trace_id`, `service.name`, `service.version`; `span_id` when inside a span
- [ ] `http_server_requests_total`, `http_server_errors_total`, `http_server_request_duration_seconds` exposed per route/method (no high-cardinality labels like `user_id`, `trace_id`)
- [ ] `messenger_handler_duration_seconds`, `messenger_handler_errors_total`, `messenger_queue_depth` exposed with `bus`/`message`/`transport` labels only
- [ ] `/health/liveness` (process-only) and `/health/readiness` (DB + cache + broker pings; returns 503 with failing check JSON) both present and unauthenticated
- [ ] Every user-facing service has an SLO documented in project docs — no un-measured user-facing routes

## API Contracts

- [ ] Every public endpoint lives under `/api/v{major}/...` — no un-versioned public routes
- [ ] OpenAPI annotations complete for every controller (request schema, response schema per status, error envelope, query params, headers) — drift from implementation is a blocker
- [ ] No breaking change (removed/renamed/re-typed field, narrower validation, changed status code) without following the breaking-change protocol (see `api-contracts.md`)
- [ ] Deprecated endpoints/fields emit `Deprecation` + `Sunset` headers (and `Link: ...; rel="successor-version"` when applicable) and are marked `deprecated: true` in OpenAPI
- [ ] Every call to a deprecated endpoint/field emits a `warn` log with `event=api.deprecated.usage` and the caller identity
- [ ] Timestamps serialized as RFC 3339 UTC; money as integer minor unit + `currency` string; enums as `snake_case` strings; nullable fields always present in responses (never omitted)
- [ ] Error envelope shape unchanged (changing it is a platform-wide breaking change) — if changed, full protocol applied
- [ ] Collection endpoints use the `{ data, meta }` envelope defined in `performance.md`

## Async messaging resilience

- [ ] Every async transport declares `retry_strategy` with finite `max_retries` and bounded `max_delay` (no infinite retries)
- [ ] Every async transport declares a `failure_transport` distinct from the live transport (a DLQ exists)
- [ ] Unrecoverable failures (validation errors, missing aggregates, authorization rejections on async messages) throw `UnrecoverableMessageHandlingException` — never silently retried
- [ ] Handlers are idempotent: either naturally idempotent via conditional writes or deduplicated via a persisted message id
- [ ] Failed handler emits `error` log with `messageName()`, message id, exception class, `trace_id`; `messenger_handler_errors_total` increments
- [ ] Consumer workers run with `--limit`, `--time-limit`, `--memory-limit`, and `--failure-limit` — no unbounded long-running workers
- [ ] No blanket DLQ replay — replay is per-id after triage

## Security headers & CORS

- [ ] SecurityHeadersSubscriber present and emitting: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `X-XSS-Protection: 0`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy: camera=(), microphone=(), geolocation=()`
- [ ] `nelmio_cors.yaml` defines `defaults` AND `paths` — explicit origins via `%env(CORS_ALLOW_ORIGIN)%`
- [ ] `allow_credentials: true` only when refresh-cookie auth is used

## Rate limiting

- [ ] `POST /api/login` → 5/min per IP
- [ ] `POST /api/register` → 3/min per IP
- [ ] `POST /api/password/reset` → 3/5min per IP
- [ ] `POST /api/token/refresh` → 10/min per IP

## JWT

- [ ] Access token TTL = 15 min
- [ ] Refresh token TTL = 7 days
- [ ] Refresh token in `httpOnly` cookie
- [ ] RS256 algorithm
- [ ] JWT payload contains only `user_id`, `roles`, `exp` — no sensitive data
- [ ] Refresh tokens rotated on each use; deleted from DB on logout

## Testing presence (Tester runs them, but reviewer checks they exist)

- [ ] Integration test class per new controller in `tests/Integration/{Aggregate}/`
- [ ] Unit tests for domain rules in `tests/Unit/Domain/Model/`
- [ ] Tests assert HTTP response AND DB state
- [ ] Error paths tested: 422 missing fields, 409 duplicate, 401 unauthorized
- [ ] Database cleaned in `setUp()` via deletes in reverse FK order — never `TRUNCATE`
- [ ] In test env, all async transports configured as `in-memory://`

## Naming

- [ ] PHP classes PascalCase, methods camelCase
- [ ] API payload fields snake_case
- [ ] Tables/columns snake_case
- [ ] `CreateXxxCommand` / `CreateXxxCommandHandler`, `GetXxxQuery` / `GetXxxQueryHandler`, `XxxCreatedEvent`, `DbalXxxRepository`, `XxxRepositoryInterface`, `XxxNotFoundException`
- [ ] Every application service class name ends with `Service` (e.g. `UserFinderService`) — no generic names like `XxxManager`, `XxxHelper`, `XxxUtil`
- [ ] PHPUnit method names match the project's PHP-CS-Fixer config — `testDescriptiveCamelCase` under the default `php_unit_method_casing` rule, `test_descriptive_snake_case` only when that rule is disabled

## Definition of Done

- [ ] Every DoD item from the task file checked

---

## Sources

For deeper context on any rule above:
- Architecture, controllers, CQRS, naming, migrations → `backend.md`
- Indexes, pagination, N+1, response design → `performance.md`
- HTTP cache headers, Redis keys, TTLs, invalidation → `caching.md`
- Tracing, metrics, health endpoints, SLOs → `observability.md`
- API versioning, breaking-change protocol, OpenAPI contract → `api-contracts.md`
- CORS, validation layers, JWT, rate limiting, headers, error responses → `security.md`
- Secret classification, manifest, injection matrix, rotation → `secrets.md`
- Schema evolution, expand-contract, backfills, zero-downtime deploys → `data-migrations.md`
- Logging schema, redaction, middleware wiring → `logging.md`
- Hard security/git invariants → `invariants.md`
- Full code examples (controllers, scaffolds, async config) → `backend-reference.md`

If you find a rule violation that is NOT in this checklist, add it as `minor` in your review and include the file/line where the missing rule should live.
