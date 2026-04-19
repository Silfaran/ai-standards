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
- [ ] Handlers call application services, never repositories from controllers
- [ ] Application services have ONE `execute()` method, ONE responsibility
- [ ] Services inject repository INTERFACES (Domain), not implementations (Infrastructure)
- [ ] Services MAY depend on other services — duplicating logic that already exists in another service is a violation (prefer composition)
- [ ] No inline `find + null check + throw` in handlers — repository exposes `getById()` (throws) and the handler calls it
- [ ] Repository interfaces expose `getById(Id): Entity` (throw-on-miss) for every aggregate where lookup-by-id exists; `findById(Id): ?Entity` is kept only for genuine "maybe exists" flows
- [ ] Handlers do NOT orchestrate 2+ repositories for a single domain operation — logic extracted to a service (cascade deletes, cross-aggregate updates)
- [ ] Handlers do NOT contain authorization/ownership checks inline when the same check repeats across handlers — delegated to a shared service
- [ ] Handlers do NOT contain branching business logic ("if exists reactivate else create", multi-step state transitions) — extracted to a service
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
- [ ] Index added for every column appearing in `WHERE`, `ORDER BY`, or as a UUID reference (no FK constraints — see ADR-007)
- [ ] No FOREIGN KEY / REFERENCES / ON DELETE clauses (ADR-007)
- [ ] On large tables: `CREATE INDEX CONCURRENTLY` instead of `CREATE INDEX`
- [ ] On large tables: 3-step pattern for `NOT NULL` columns (add nullable → backfill → add NOT NULL)
- [ ] No service queries another service's tables — each service owns its DB
- [ ] Phinx seeds added for every new aggregate (realistic local data)

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

## Logging

- [ ] LoggingMiddleware wired into `command.bus`, `event.bus`, `message.bus`
- [ ] Query buses do NOT have logging middleware
- [ ] Logs are structured JSON to `php://stdout` — never plain text
- [ ] In `when@test`, monolog handler `type: null` (no log noise in tests)
- [ ] No successful-handling logs (noise)
- [ ] Sensitive fields redacted in payloads (see hard blockers above)

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

## Definition of Done

- [ ] Every DoD item from the task file checked

---

## Sources

For deeper context on any rule above:
- Architecture, controllers, CQRS, naming, migrations → `backend.md`
- Indexes, pagination, N+1, response design → `performance.md`
- CORS, validation layers, JWT, rate limiting, headers, error responses → `security.md`
- Logging schema, redaction, middleware wiring → `logging.md`
- Hard security/git invariants → `invariants.md`
- Full code examples (controllers, scaffolds, async config) → `backend-reference.md`

If you find a rule violation that is NOT in this checklist, add it as `minor` in your review and include the file/line where the missing rule should live.
