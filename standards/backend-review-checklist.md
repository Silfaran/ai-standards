# Backend Review Checklist

Closed list of verifiable rules for the Backend Reviewer agent. Each rule has a stable ID (`BE-*`, `SE-*`, `PE-*`, …) prefixed by the source-standard domain; quoting the ID is enough to disambiguate a violation. Each rule maps to a single, observable check on the diff.

The reviewer must NOT re-read the full standards — this checklist is the authoritative review surface. If a rule seems missing for the current diff, request it as a `minor` and flag it for inclusion in a future checklist update (new rules get the next free ID within their prefix — IDs are never reassigned).

> **Quality gates pre-requisite.** Mechanical checks (PHPStan level 9, PHP-CS-Fixer, `composer validate`, `composer audit`, migrations on clean Postgres, PHPUnit) are enforced by the pre-commit hook and GitHub Actions CI before the reviewer sees the diff. See [`quality-gates.md`](quality-gates.md). If CI is red, reject immediately with status `QUALITY-GATE-FAILED` and point the developer to the failing job — do not start the full review.

---

## Hard blockers (auto-reject, regardless of iteration)

- [ ] **BE-001** — Quality gates CI is green for the current commit (PHPStan L9, PHP-CS-Fixer, composer audit, migrations, PHPUnit)
- [ ] **BE-002** — PHPStan level 9 passes (zero errors) — confirm via CI, no baseline entries added to hide violations
- [ ] **BE-003** — PHP-CS-Fixer passes (zero violations) — confirm via CI
- [ ] **SE-001** — No string concatenation/interpolation in SQL — DBAL parameterized queries only
- [ ] **SE-002** — No CORS `*` in `nelmio_cors.yaml` — explicit origin allowlist via env
- [ ] **SC-001** — No secrets committed (`.env`, keys, tokens, fixtures with real credentials)
- [ ] **SE-003** — No SSL verification disabled (`verify => false`, `--insecure`)
- [ ] **SE-004** — No internal details leaked in error responses (stack traces, file paths, SQL errors)
- [ ] **LO-001** — No log entries with unredacted sensitive fields (`password`, `token`, `access_token`, `refresh_token`, `secret`, `api_key`, `credential`, `card_number`)
- [ ] **DM-001** — Migrations executed previously are NOT modified — new migration created instead

## Architecture (Hexagonal + DDD + CQRS)

- [ ] **BE-004** — Folder layout: `Domain/`, `Application/`, `Infrastructure/` boundaries respected
- [ ] **BE-005** — Commands and queries are separated — never mixed in the same handler
- [ ] **BE-006** — Handlers call services (Domain or Application) or repositories directly — never inline extracted logic
- [ ] **BE-007** — Services expose exactly ONE public method (`execute`) plus the constructor — zero exceptions. Any additional method is `private` and called from `execute`. Multi-public services (twin signatures, overloaded variants, "convenience wrappers") split into separate classes
- [ ] **BE-008** — `[critical]` Service placement: domain services (pure rules) live in `src/Domain/Service/{Aggregate}/`; application services (use-case orchestrators) live in `src/Application/Service/{Aggregate}/`. A service under `Domain/Service/` MUST NOT import from `App\Infrastructure\*`, MUST NOT depend on framework classes beyond the ones it reads (PSR interfaces are fine), and MUST NOT orchestrate side effects (no event publishing, no email sending, no transactions). If it does any of these — move to `Application/Service/`
- [ ] **BE-009** — `[critical]` Fast disambiguator for Domain-vs-Application placement: a service that injects `Doctrine\DBAL\Connection`, `MessageBusInterface`, or any other transactional/side-effect primitive is Application by construction. A domain service MUST NOT hold any of these — if it does, move to `Application/Service/` regardless of what the name suggests
- [ ] **BE-010** — Services are declared `readonly class` — NOT `final` (PHPUnit 13 `createMock()` compatibility). `readonly` preserves immutability without blocking test doubles
- [ ] **BE-011** — Finder services (throw-on-miss aggregate lookups) live in Domain — `src/Domain/Service/{Aggregate}/{Aggregate}FinderService.php`
- [ ] **BE-012** — Handlers are not duplicated by a parallel `{Action}UseCase` class in `Application/Service/` — the handler IS the application service for that use case
- [ ] **BE-013** — Services inject repository INTERFACES (Domain), not implementations (Infrastructure)
- [ ] **BE-014** — Services MAY depend on other services — duplicating logic that already exists in another service is a violation (prefer composition). A domain service NEVER composes an application service (inverted-layer violation)
- [ ] **BE-015** — No inline `find + null check + throw` in handlers — a `{Aggregate}FinderService` owns the throw-on-miss lookup and the handler calls it
- [ ] **BE-016** — Repository interfaces expose ONLY nullable lookups (`findById(Id): ?Entity`, `findByEmail(...): ?Entity`, …) — throw-on-miss methods (`getById`, `findOrFail`) do NOT live on the repository
- [ ] **BE-017** — Every aggregate that has a throw-on-miss need has a `{Aggregate}FinderService` under `src/Domain/Service/{Aggregate}/` (canonical precedent: `UserFinderService` in login-service)
- [ ] **BE-018** — Finder services follow the one-execute rule: one finder = one lookup = one `execute()` method. Variant lookups live in separate `{Aggregate}FinderBy{Key}Service` classes (e.g. `UserFinderByEmailService`) — never a second method on an existing finder
- [ ] **BE-019** — Handlers do NOT orchestrate 2+ repositories for a single domain operation — logic extracted to a service (cascade deletes, cross-aggregate updates → typically Application)
- [ ] **BE-020** — Handlers do NOT contain authorization/ownership checks inline when the same check repeats across handlers — delegated to a shared domain service
- [ ] **BE-021** — Handlers do NOT contain branching business logic ("if exists reactivate else create", multi-step state transitions) — extracted to a service (Application if it orchestrates side effects; Domain if it's a pure rule)
- [ ] **BE-022** — Domain layer has zero Symfony/Doctrine imports
- [ ] **BE-023** — Aggregates use `static create()` (new, raises events) and `static from()` (rehydration, no events)
- [ ] **BE-024** — Value objects, commands, queries, DTOs use `private __construct` + `static from()`

## Controllers

- [ ] **BE-025** — Each controller extends `AppController`
- [ ] **BE-026** — One controller per command/query — no multi-action controllers
- [ ] **BE-027** — Controllers only call `dispatchCommand()` / `dispatchQuery()` — never call services directly
- [ ] **BE-028** — No business validation in controllers — only structural (JSON valid, fields present, types correct)
- [ ] **BE-029** — Type-guard the request: `is_string()`, `is_int()`, `is_array()` — never trust `$request->getContent()`
- [ ] **BE-030** — Returns `400` for malformed JSON, `422` for missing/wrong-type fields
- [ ] **BE-031** — Trims string inputs (names, emails) — never trims passwords
- [ ] **AC-001** — Every controller has OpenAPI/Swagger annotations
- [ ] **BE-032** — `services.yaml` injects `$commandBus: '@command.bus'` and `$queryBus: '@query.bus'` by name

## Authorization

- [ ] **AZ-001** — `[critical]` Every protected handler calls a Voter (`{Aggregate}Voter::can{Action}()`) before any side effect — no inline `if ($subject->role === ...)` checks
- [ ] **AZ-002** — `[critical]` Every multi-tenant repository method takes `tenantId` as the first parameter — no method that "filters by current tenant" implicitly
- [ ] **AZ-003** — Voters live in `src/Domain/Authorization/Voter/{Aggregate}Voter.php`, return `bool` (never throw), inject NO repositories, perform NO I/O
- [ ] **AZ-004** — `Subject` Value Object (`src/Domain/Authorization/Subject.php`) is built once in the controller from the JWT and propagated as a field of every Command/Query DTO — no global "current user" service consulted from a handler
- [ ] **AZ-005** — Multi-tenant tables declare `tenant_id UUID NOT NULL` and every supporting index includes `tenant_id` as the leading column
- [ ] **AZ-006** — Cross-tenant denials return 404 (preferred) or 403 — never reveal that a resource exists in another tenant
- [ ] **AZ-007** — 403 response body never includes denial reason, role names, or resource metadata — opaque "forbidden" only
- [ ] **AZ-008** — Authorization denials emit a span event with `authz.action`, `authz.decision=deny`, `authz.deny_reason`; metric `authz_denied_total{action, deny_reason}` increments (no subject_id label)
- [ ] **AZ-009** — Every protected action has at least three tests: allowed path, denied-by-role, denied-by-tenant — Voter unit tests are pure (no Symfony container)
- [ ] **AZ-010** — Service-to-service calls mint a service Subject with `tenantId='shared'` and a `service:*` role — never reuse a real user's Subject across services without the original JWT being forwarded
- [ ] **AZ-011** — Authorization decisions are NEVER cached in Redis or any TTL'd store — Voter calls are pure and fast; cached decisions outlive role revocations
- [ ] **AZ-012** — `Subject` is immutable (`readonly`) — no runtime role mutation (`$subject->roles[] = 'admin'`)

## Validation layering

- [ ] **BE-033** — Structural validation lives in the controller
- [ ] **BE-034** — Business invariants live in Value Objects (using `webmozart/assert`)
- [ ] **BE-035** — Domain exceptions exist for each business rule violation and are mapped in `ApiExceptionSubscriber`
- [ ] **BE-036** — No `match` arm missing in `ApiExceptionSubscriber` for any new domain exception
- [ ] **BE-037** — No domain exception returns 500 — every expected failure has a mapped HTTP status

## Database & migrations

- [ ] **BE-038** — New tables use `id UUID DEFAULT gen_random_uuid()` as PK
- [ ] **BE-039** — Snake_case for tables and columns
- [ ] **PE-001** — Index added for every column appearing in `WHERE`, `ORDER BY`, or as a UUID reference (the project's no-FK ADR means references are not indexed automatically — see `{project-docs}/decisions.md`)
- [ ] **BE-040** — No FOREIGN KEY / REFERENCES / ON DELETE clauses — per the project's no-FK ADR
- [ ] **PE-002** — On large tables: `CREATE INDEX CONCURRENTLY` instead of `CREATE INDEX`
- [ ] **DM-002** — On large tables: 3-step pattern for `NOT NULL` columns (add nullable → backfill → add NOT NULL)
- [ ] **BE-041** — No service queries another service's tables — each service owns its DB
- [ ] **BE-042** — Phinx seeds added for every new aggregate (realistic local data)

## Data migrations strategy

- [ ] **DM-003** — Migration is classified as non-breaking or breaking using the lists in `data-migrations.md` — classification is visible in the commit message or PR description
- [ ] **DM-004** — Breaking changes decomposed into expand → migrate → contract phases; the phase is declared in the commit message, and each phase is its own commit
- [ ] **DM-005** — Contract-phase commits (dropping / renaming / re-typing a populated column or table) use `refactor(db)!:` prefix and a `BREAKING CHANGE:` trailer
- [ ] **DM-006** — Compatibility matrix holds: the previous application version continues to work correctly against the new schema for the duration of the deploy window
- [ ] **DM-007** — No removal, rename, or non-widening type change of a column/table/index happens in the same migration that creates its replacement
- [ ] **DM-008** — No `NOT NULL` added to a populated column without a completed backfill in a prior phase
- [ ] **DM-009** — Backfills on tables larger than ~10k rows run as a background job (Symfony console command), not inline in the Phinx migration
- [ ] **DM-010** — Background-job backfills are idempotent, batched (≤10k rows per commit), ordered by primary key, and report progress (row count, errors, last processed id)
- [ ] **DM-011** — The migration is idempotent — running it twice leaves the schema in the same state
- [ ] **DM-012** — PR description answers "how do we undo this if it lands bad?" in one sentence — "revert the commit" is not acceptable for breaking migrations
- [ ] **DM-013** — No cross-service database access introduced — new data dependencies use the owning service's API or a domain-event projection

## Repositories & queries

- [ ] **PE-003** — All multi-row repository methods accept `int $limit = 20, int $offset = 0` — no unbounded list queries
- [ ] **PE-004** — No queries inside loops (N+1) — use `IN (...)` batch queries
- [ ] **PE-005** — `SELECT` only the columns the response needs (no `SELECT *` in API-facing queries)
- [ ] **SE-005** — No raw SQL string interpolation — placeholders only

## API responses

- [ ] **AC-002** — List endpoints accept `?page=` (1-based) and `?per_page=` (default 20, max 100)
- [ ] **AC-003** — List responses include envelope: `{ "data": [...], "meta": { "total", "page", "per_page" } }`
- [ ] **AC-004** — Status codes match: 200/201/204/400/401/403/404/409/422/429/500
- [ ] **AC-005** — Error body shape: `{ "error": "message", "details": [...] }`

## Async messaging (when applicable)

- [ ] **BE-043** — Every command/query/event/message implements `messageName()` returning `{service_name}.{type}.{snake_case_action}`
- [ ] **BE-044** — Async transports use `messenger.transport.symfony_serializer` — never `PhpSerializer`
- [ ] **BE-045** — `default_bus` set explicitly when multiple buses exist
- [ ] **BE-046** — Cross-service messages: identical FQCN + constructor + `messageName()` in both services
- [ ] **BE-047** — `composer.json` and `composer.lock` in sync after dependency changes

## Caching

- [ ] **CA-001** — Every `GET` endpoint sets an explicit `Cache-Control` header — no framework default inherited silently
- [ ] **CA-002** — Per-user authenticated reads use `private, no-cache`; sensitive per-user data (tokens, payments, settings) uses `no-store`
- [ ] **CA-003** — Write endpoints (`POST`/`PUT`/`PATCH`/`DELETE`) explicitly set `no-store`
- [ ] **CA-004** — Cacheable `GET` responses emit either `ETag` or `Last-Modified` and honor `If-None-Match` / `If-Modified-Since` with `304`
- [ ] **CA-005** — `Vary` header declared on responses that differ by `Accept-Language`, `Authorization`, or any other header
- [ ] **CA-006** — No auth/session/PII/token values written to a shared Redis cache without a per-user key
- [ ] **CA-007** — Redis keys follow `{service}:{aggregate}:{operation}:{identifier}[:v{n}]`, lowercase, colon-separated
- [ ] **CA-008** — Every Redis key has an explicit TTL — no infinite keys
- [ ] **CA-009** — Every cached entity has an invalidation path on write (`$cache->delete(...)` in the write handler or via event listener) — TTL alone is not the invalidation strategy
- [ ] **CA-010** — Hot keys have stampede protection documented (soft TTL + lock, jittered TTL, or background refresh) — choice recorded in the spec's Technical Details
- [ ] **CA-011** — Redis is never the source of truth — data loss on cache restart must be recoverable from the primary store

## Secrets management

- [ ] **SC-002** — Every env var in the diff that matches the secret categories in `secrets.md` has a row in the project's `secrets-manifest.md` (owner, category, environments, source, rotation, `last_rotated`)
- [ ] **SC-003** — Secrets are read exclusively from process environment variables — no direct calls to provider SDKs (AWS Secrets Manager, Vault, etc.) from application code
- [ ] **SC-004** — Every required secret read uses a fail-fast helper that throws when the value is missing or empty — no silent fallbacks to `null` or empty string
- [ ] **SC-005** — `.env.example` lists every new secret with a placeholder (`CHANGE_ME`) and a category comment; no real value is committed
- [ ] **SC-006** — No secret value is baked into a Docker image (`COPY .env`, `ENV SECRET=...` in a Dockerfile) or passed as a CLI argument
- [ ] **SC-007** — No secret value is written to disk, logged, emitted as a span attribute, or used as a metric label
- [ ] **SC-008** — Frontend diffs: no secret placed in a `VITE_*` variable (API keys, OAuth client secrets, private URLs, private identifiers)
- [ ] **SC-009** — JWT/crypto key rotation uses a two-key window (current + previous) during the rotation window; the manifest lists both env vars
- [ ] **SC-010** — Any new secret category extends the redaction list in `logging.md` in the same commit

## Internationalization

- [ ] **IN-001** — Locale negotiated ONCE in middleware (URL param → user preference → `Accept-Language` → default), bound to the request as a `Locale` value object — never re-negotiated per layer
- [ ] **IN-002** — Every locale-varying response sets `Content-Language` AND `Vary: Accept-Language` (the latter is mandatory for cacheable responses; see CA-005)
- [ ] **IN-003** — User-facing strings come from translation files / catalogs — no hardcoded user-facing English/Spanish in handlers, controllers, exceptions surfaced to the API
- [ ] **IN-004** — Translation functions called with STATIC keys only — `t($dynamicKey)` is forbidden (extraction tools cannot find them)
- [ ] **IN-005** — `[critical]` Translatable entity columns follow Option A (`translations` polymorphic table) or Option B (JSONB column) — separate columns per locale (`name_es`, `name_en`) is forbidden
- [ ] **IN-006** — Every translatable entity records its `source_locale` — the locale the original was written in, never machine-translated, final fallback
- [ ] **IN-007** — Repositories returning translatable entities for display take `Locale` as an explicit parameter and resolve the fallback chain inside — handlers never read raw JSONB or `translations` rows
- [ ] **IN-008** — `translations` rows record `source` (`human` / `machine` / `user`) — machine translations have a TTL or invalidation path; human edits promote them to `human`
- [ ] **IN-009** — A missed translation emits a structured log entry with `event=i18n.missing`, `requested_locale`, `served_locale`, `key` — never silently substituted
- [ ] **IN-010** — API error responses use a stable `error` code AND a localized `message` — clients switch on the code, never on the human text
- [ ] **IN-011** — Plurals, dates, numbers, currency formatted via `Symfony Translator` (ICU) / `IntlDateFormatter` / `NumberFormatter` — manual `date('d/m/Y')`, `number_format()`, currency-symbol concatenation are forbidden
- [ ] **IN-012** — System reference data (countries, currencies, locale names) read from `Symfony\Component\Intl\*` — no hardcoded country lists in source
- [ ] **IN-013** — A new supported locale is enabled in configuration ONLY after UI string files exist for it (machine-or-human-translated, marked for review)

## Personal data (PII) & GDPR

- [ ] **GD-001** — `[critical]` Every new column whose content is PII has a row in `{project-docs}/pii-inventory.md` (field, tier, legal_basis, purpose, retention, processors, dsar_export, rtbf_action) — no inventory row = hard reject
- [ ] **GD-002** — `[critical]` Sensitive-PII columns are encrypted at rest via `SensitivePiiCipher` (libsodium AEAD; key from `secrets.md` `PII_ENCRYPTION_KEY`); column type is `BYTEA` — plaintext `text` columns for sensitive fields are forbidden
- [ ] **GD-003** — Sensitive-PII NEVER appears in list-endpoint projections; detail endpoints return masked values (`****1234`) unless an explicit Voter rule grants "view sensitive" permission
- [ ] **GD-004** — Every read of a decrypted Sensitive-PII value emits `event=pii.access` with `field`, `subject_id`, `actor_id`, `purpose`, `trace_id` — the value itself is NEVER logged
- [ ] **GD-005** — PII fields NEVER appear in URLs, query strings, headers (other than `Authorization`), error messages, span attributes, metric labels, or log lines (Internal-PII allowed only as the hashed `user_id`)
- [ ] **GD-006** — A new PII field added to the inventory triggers a same-commit update of the redaction list in `logging.md`
- [ ] **GD-007** — Hash-based deduplication uses a peppered hash (`PII_DEDUP_PEPPER` from secrets manifest) — never `md5(email)` raw
- [ ] **GD-008** — Repository methods enforce projection (`SELECT id, display_name`) instead of `SELECT *` for endpoints that don't need PII columns
- [ ] **GD-009** — `DsarExportService` test fixture exercises every inventory row with `dsar_export=yes` — a new field omitted from the export is a defect
- [ ] **GD-010** — `ForgetUserCommand` reads the inventory at runtime (`rtbf_action`) — no hardcoded delete/anonymize lists per service
- [ ] **GD-011** — Every external sub-processor introduced (Stripe, SendGrid, OpenAI, Twilio, …) has an inventory entry naming the affected fields and the processor's region — hardcoded SDK instantiation without inventory entry is a hard reject
- [ ] **GD-012** — Consent-gated processing queries the `ConsentLedger` aggregate before the first byte of work — no "we'll honour the next batch" deferred consent
- [ ] **GD-013** — Backups copying prod data to staging or analytics MUST run a redaction pipeline first — direct restores of Sensitive-PII into non-prod environments are forbidden
- [ ] **GD-014** — A spec that crosses a DPIA threshold (large-scale special categories, automated decisions with legal effect, LLM personalization on PII) has a completed DPIA in `{project-docs}/dpia/` before implementation merges

## LLM integration

- [ ] **LL-001** — `[critical]` Every LLM call goes through `LlmGatewayInterface` (Domain) — no direct SDK imports (`Anthropic\Sdk\Client`, `OpenAI\Client`, `Gemini\Client`) in handlers, services or controllers
- [ ] **LL-002** — Prompt templates live in `src/Domain/Llm/Prompt/{Purpose}Prompt.php` as classes with `VERSION` constant, `system()`, `user(...)`, optional `jsonSchema()` — no inline string interpolation of prompts in handlers
- [ ] **LL-003** — `LlmRequest::purpose` is bounded (a constant or enum value), never a dynamic string — the metric label cardinality must stay finite
- [ ] **LL-004** — Structured generation calls set `jsonSchema` and read `LlmResponse->parsed` — handlers MUST NOT call `json_decode($response->content)` themselves
- [ ] **LL-005** — Adapter validates the parsed JSON against the schema and throws `LlmInvalidResponseException` on mismatch — never silently passes malformed payloads to the handler
- [ ] **LL-006** — Adapter retries ONLY on 408/429/5xx + transport errors with exponential jittered backoff and `max_retries=2` (override only with documented reason); NEVER retries 4xx, validation failures, or content-filter rejections
- [ ] **LL-007** — Every provider+model pair has a circuit breaker; handlers have a graceful degradation path on `LlmCircuitOpenException`
- [ ] **LL-008** — Handlers driving writes via LLM are idempotent (BE-051) — retry loops cannot double-insert
- [ ] **LL-009** — `[critical]` Every LLM call emits an `llm.call` child span with `llm.provider`, `llm.model`, `llm.purpose`, `llm.prompt_version`, `llm.input_tokens`, `llm.output_tokens`, `llm.cost_micro_dollars`, `llm.finish_reason`, `llm.latency_ms` — NEVER the prompt text or response body
- [ ] **LL-010** — Cost metrics emitted: `llm_calls_total`, `llm_input_tokens_total`, `llm_output_tokens_total`, `llm_cost_micro_dollars_total`, `llm_latency_seconds`, `llm_errors_total` — labels limited to `provider`, `model`, `purpose`, `finish_reason` / `error_class`
- [ ] **LL-011** — Static prefixes (system prompt + injected catalogs) come FIRST in the message list with the provider's cache marker set; cache hits are observable as `llm.cache_read_tokens > 0`
- [ ] **LL-012** — `[critical]` `PiiPromptGuard` invoked synchronously in `complete()` for any purpose that may receive PII — the guard checks `pii-inventory.md` AND the `ConsentLedger`; bypass only via inventory `processors` exemption
- [ ] **LL-013** — Tool-use loops capped (default 5 iterations) — `LlmToolLoopExhaustedException` thrown if exceeded; tool-driven writes go through Voters (AZ-001)
- [ ] **LL-014** — Unit tests mock `LlmGatewayInterface` and assert handlers consume the parsed shape; real-provider tests (if any) sit behind `@group llm-real` and a daily budget — never in default CI

## Payments & money

- [ ] **PA-001** — `[critical]` Every monetary value uses the `Money` value object (integer minor units + ISO 4217 currency) — no `float`, no `NUMERIC(x,2)` columns, no string-formatted "12.34" in storage, transport or arithmetic
- [ ] **PA-002** — Money columns ALWAYS pair `amount_minor BIGINT` with `currency CHAR(3)`; CHECK constraint enforces ISO 4217 format; one-column shapes (`amount_eur`) are forbidden
- [ ] **PA-003** — Currency mismatches in `Money::add/subtract` throw `CurrencyMismatchException` — no silent coercion
- [ ] **PA-004** — Money splits use a sum-preserving algorithm (largest-remainder method); `split` MUST never lose minor units to truncation
- [ ] **PA-005** — `[critical]` Every PSP mutation call (charge, refund, payout, subscription change) carries a deterministic `Idempotency-Key` derived from the aggregate id and attempt number — no random keys, no missing keys
- [ ] **PA-006** — `[critical]` Webhook handlers verify the provider signature on the RAW request body BEFORE parsing JSON or persisting anything — invalid signature returns 401 + `webhook_signature_invalid` log + drop
- [ ] **PA-007** — `[critical]` Webhook handlers check `processed_webhooks(provider, event_id)` first; duplicate events return 200 immediately; the insert into `processed_webhooks` happens in the SAME DB transaction as the state change, BEFORE returning 200
- [ ] **PA-008** — Webhook handlers tolerate out-of-order events: state changes guard against current-state checks (`if (alreadyCompleted) return`) — never trust event arrival order
- [ ] **PA-009** — `[critical]` Every change to a tracked balance produces an immutable `ledger_entries` row; ledger entries grouped by `transaction_id` MUST sum to zero per currency, asserted at write time
- [ ] **PA-010** — Ledger rows are append-only — UPDATE / DELETE on `ledger_entries` is forbidden in code; corrections are NEW entries with `cause_type='adjustment'`
- [ ] **PA-011** — Account names are stable strings; renaming an account requires reversal entries on the old name and new entries on the new name in the same transaction (no in-place rename)
- [ ] **PA-012** — Every payment object (Charge, Subscription, Refund, Payout, Dispute) has an explicit state machine enforced by the aggregate; database `CHECK` constraint mirrors the allowed states; transitions go through aggregate methods (no direct status assignment)
- [ ] **PA-013** — Subscriptions are webhook-driven — no polling cron synthesises subscription state; the system reads its own row, not the provider's API, in hot paths
- [ ] **PA-014** — Refunds are first-class aggregates referencing the original Charge; the Charge's derived state (`partially_refunded` / `refunded`) is computed from the sum of its refunds — no in-place charge mutation
- [ ] **PA-015** — Pricing lives in the database (`prices` table with `valid_from`/`valid_until`), never hardcoded in PHP — pricing logic that is genuinely a function lives in a Domain `PriceCalculatorService` that returns `Money`
- [ ] **PA-016** — API responses serialize money as `{ "amount_minor": <int>, "currency": "XXX" }` — the serializer refuses `Money` → `float` conversions
- [ ] **PA-017** — Reconciliation runs daily (or hourly), compares ledger account balances to provider-reported balances, raises `ReconciliationDivergenceFound` (SEV-2) on non-zero delta — "small delta, ignoring" is forbidden
- [ ] **PA-018** — Multi-party split charges record both legs (`platform_revenue:<tenant>`, `payout_pending:<recipient>`) at capture time; payout settlement debits `payout_pending` against `psp_clearing`
- [ ] **PA-019** — Payment-affecting handlers emit span attributes `payment.provider`, `payment.kind`, `payment.status_after` and metrics `payments_total`, `payments_amount_minor_total`, `payments_failures_total`, `webhook_duplicate_total`, `reconciliation_delta_minor` — labels bounded; no customer identifiers
- [ ] **PA-020** — PSP webhook secret stored as `{PROVIDER}_WEBHOOK_SECRET` in `secrets-manifest.md` with rotation policy; signing helper centralised per provider; HTTP webhooks rejected with 426 on dev/staging

## File & media storage

- [ ] **FS-001** — `[critical]` Binary content lives in object storage, NEVER in a database column (`bytea` for avatars, contracts, videos is forbidden)
- [ ] **FS-002** — Buckets are either fully public OR fully private — never mixed via "smart" prefix policies. Per-environment naming: `{project}-public-{env}`, `{project}-private-{env}`
- [ ] **FS-003** — Public buckets disallow anonymous PUT — uploads ALWAYS go through presigned URLs minted by the backend
- [ ] **FS-004** — Object keys contain the owner identifier (user/tenant/contract) — keys like `uploads/abc.jpg` with no scoping are a defect
- [ ] **FS-005** — User-supplied filenames are NEVER used raw at the leaf — system renames to `{aggregate_id}.{ext}` or moves the original name to object metadata
- [ ] **FS-006** — `[critical]` Presigned URLs are scoped (single key, single method, content-type whitelist, max-bytes); TTL ≤ 15 minutes for browser-handed URLs (background batch ≤ 1 h with documented justification)
- [ ] **FS-007** — Quotas (per-user + per-tenant) enforced at presign time — without it, the only enforcement is the bill
- [ ] **FS-008** — Upload aggregate transitions: `pending → uploaded → scanning → available | quarantined | scan_failed | mime_mismatch`. Handlers serving downloads check `status = available` — never serve `pending`/`scanning`/`quarantined`
- [ ] **FS-009** — `[critical]` Voter (AZ-001) runs BEFORE minting any private-bucket presigned GET URL — handing the URL to the wrong subject bypasses every later check
- [ ] **FS-010** — `Content-Disposition: attachment` forced on sensitive private downloads (DNI, contract) — never inline rendering of user-controlled bytes from the same origin
- [ ] **FS-011** — Magic-byte verification runs after upload — the client `Content-Type` is NEVER trusted; mismatch transitions Upload to `mime_mismatch`, deletes the object, alerts
- [ ] **FS-012** — Antivirus scan (ClamAV / VirusTotal / cloud-native) runs async on every private-bucket upload; result delivered via domain event consumed by the Upload aggregate; periodic re-scans scheduled
- [ ] **FS-013** — Variants (thumbnails, transcodes, captions) tracked in `upload_variants(upload_id, variant_kind, bucket, key)`; deleting the original cascades; variants live in a bucket with shorter retention
- [ ] **FS-014** — Video sources live in a separate bucket with a lifecycle rule deleting them N days after `Video.status = available` (override only via documented ADR)
- [ ] **FS-015** — Video playback URLs are signed by default (CDN signed cookies for HLS, signed URL for MP4); public video requires explicit ADR
- [ ] **FS-016** — Captions are first-class variants per locale (`captions_{locale}.vtt`); auto-generated captions flagged `source='machine'` (see i18n.md), promotable to `human`
- [ ] **FS-017** — Soft-delete: Upload transitions to `deleted` + `deleted_at`; nightly job deletes the object N days later (default 7) — RTBF (`gdpr-pii.md`) deletes immediately
- [ ] **FS-018** — Orphan detection: nightly job lists buckets, compares to `uploads` rows; orphan keys deleted after 30-day grace; orphan rows trigger an incident
- [ ] **FS-019** — Span attributes per call: `storage.bucket`, `storage.operation`, `storage.object_size_bytes`, `storage.error_class` — NEVER the presigned URL or full key
- [ ] **FS-020** — Metrics: `storage_operations_total`, `storage_bytes_uploaded_total`, `storage_bytes_downloaded_total`, `storage_objects_quarantined_total`, `video_transcode_duration_seconds`, `video_transcode_failures_total` — bounded labels (bucket, operation, outcome, mime_class, failure_class)
- [ ] **FS-021** — Bucket names are env-config, never hardcoded in source — same code, different bucket per environment
- [ ] **FS-022** — Presigned URLs are NEVER logged at any level — they are short-lived capabilities

## Logging

- [ ] **LO-002** — LoggingMiddleware wired into `command.bus`, `event.bus`, `message.bus`
- [ ] **LO-003** — Query buses do NOT have logging middleware
- [ ] **LO-004** — Logs are structured JSON to `php://stdout` — never plain text
- [ ] **LO-005** — In `when@test`, monolog handler `type: null` (no log noise in tests)
- [ ] **LO-006** — No successful-handling logs (noise)
- [ ] **LO-007** — Sensitive fields redacted in payloads (see hard blockers above)

## Observability

- [ ] **OB-001** — Every inbound HTTP request has a server span with `http.route` (template, not rendered path), `http.request.method`, `http.response.status_code`, and `service.name` / `service.version`
- [ ] **OB-002** — Every DBAL query emits a client span named by SQL operation (`SELECT boards`) — never with literal values
- [ ] **OB-003** — Every command/query/message handler wraps execution in a Messenger span
- [ ] **OB-004** — Every outgoing HTTP client call emits a span and propagates `traceparent` / `tracestate`
- [ ] **OB-005** — No span attribute carries passwords, tokens (access/refresh/API), request bodies with PII, or full SQL with literals
- [ ] **OB-006** — Every log line includes `trace_id`, `service.name`, `service.version`; `span_id` when inside a span
- [ ] **OB-007** — `http_server_requests_total`, `http_server_errors_total`, `http_server_request_duration_seconds` exposed per route/method (no high-cardinality labels like `user_id`, `trace_id`)
- [ ] **OB-008** — `messenger_handler_duration_seconds`, `messenger_handler_errors_total`, `messenger_queue_depth` exposed with `bus`/`message`/`transport` labels only
- [ ] **OB-009** — `/health/liveness` (process-only) and `/health/readiness` (DB + cache + broker pings; returns 503 with failing check JSON) both present and unauthenticated
- [ ] **OB-010** — Every user-facing service has an SLO documented in project docs — no un-measured user-facing routes

## API Contracts

- [ ] **AC-006** — Every public endpoint lives under `/api/v{major}/...` — no un-versioned public routes
- [ ] **AC-007** — OpenAPI annotations complete for every controller (request schema, response schema per status, error envelope, query params, headers) — drift from implementation is a blocker
- [ ] **AC-008** — No breaking change (removed/renamed/re-typed field, narrower validation, changed status code) without following the breaking-change protocol (see `api-contracts.md`)
- [ ] **AC-009** — Deprecated endpoints/fields emit `Deprecation` + `Sunset` headers (and `Link: ...; rel="successor-version"` when applicable) and are marked `deprecated: true` in OpenAPI
- [ ] **AC-010** — Every call to a deprecated endpoint/field emits a `warn` log with `event=api.deprecated.usage` and the caller identity
- [ ] **AC-011** — Timestamps serialized as RFC 3339 UTC; money as integer minor unit + `currency` string; enums as `snake_case` strings; nullable fields always present in responses (never omitted)
- [ ] **AC-012** — Error envelope shape unchanged (changing it is a platform-wide breaking change) — if changed, full protocol applied
- [ ] **AC-013** — Collection endpoints use the `{ data, meta }` envelope defined in `performance.md`

## Async messaging resilience

- [ ] **BE-048** — Every async transport declares `retry_strategy` with finite `max_retries` and bounded `max_delay` (no infinite retries)
- [ ] **BE-049** — Every async transport declares a `failure_transport` distinct from the live transport (a DLQ exists)
- [ ] **BE-050** — Unrecoverable failures (validation errors, missing aggregates, authorization rejections on async messages) throw `UnrecoverableMessageHandlingException` — never silently retried
- [ ] **BE-051** — Handlers are idempotent: either naturally idempotent via conditional writes or deduplicated via a persisted message id
- [ ] **BE-052** — Failed handler emits `error` log with `messageName()`, message id, exception class, `trace_id`; `messenger_handler_errors_total` increments
- [ ] **BE-053** — Consumer workers run with `--limit`, `--time-limit`, `--memory-limit`, and `--failure-limit` — no unbounded long-running workers
- [ ] **BE-054** — No blanket DLQ replay — replay is per-id after triage

## Security headers & CORS

- [ ] **SE-006** — SecurityHeadersSubscriber present and emitting: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `X-XSS-Protection: 0`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy: camera=(), microphone=(), geolocation=()`
- [ ] **SE-007** — `nelmio_cors.yaml` defines `defaults` AND `paths` — explicit origins via `%env(CORS_ALLOW_ORIGIN)%`
- [ ] **SE-008** — `allow_credentials: true` only when refresh-cookie auth is used

## Rate limiting

- [ ] **SE-009** — `POST /api/login` → 5/min per IP
- [ ] **SE-010** — `POST /api/register` → 3/min per IP
- [ ] **SE-011** — `POST /api/password/reset` → 3/5min per IP
- [ ] **SE-012** — `POST /api/token/refresh` → 10/min per IP

## JWT

- [ ] **SE-013** — Access token TTL = 15 min
- [ ] **SE-014** — Refresh token TTL = 7 days
- [ ] **SE-015** — Refresh token in `httpOnly` cookie
- [ ] **SE-016** — RS256 algorithm
- [ ] **SE-017** — JWT payload contains only `user_id`, `roles`, `exp` — no sensitive data
- [ ] **SE-018** — Refresh tokens rotated on each use; deleted from DB on logout

## Testing presence (Tester runs them, but reviewer checks they exist)

- [ ] **BE-055** — Integration test class per new controller in `tests/Integration/{Aggregate}/`
- [ ] **BE-056** — Unit tests for domain rules in `tests/Unit/Domain/Model/`
- [ ] **BE-057** — Tests assert HTTP response AND DB state
- [ ] **BE-058** — Error paths tested: 422 missing fields, 409 duplicate, 401 unauthorized
- [ ] **BE-059** — Database cleaned in `setUp()` via deletes in reverse FK order — never `TRUNCATE`
- [ ] **BE-060** — In test env, all async transports configured as `in-memory://`

## Naming

- [ ] **BE-061** — PHP classes PascalCase, methods camelCase
- [ ] **BE-062** — API payload fields snake_case
- [ ] **BE-063** — Tables/columns snake_case
- [ ] **BE-064** — `CreateXxxCommand` / `CreateXxxCommandHandler`, `GetXxxQuery` / `GetXxxQueryHandler`, `XxxCreatedEvent`, `DbalXxxRepository`, `XxxRepositoryInterface`, `XxxNotFoundException`
- [ ] **BE-065** — Every application service class name ends with `Service` (e.g. `UserFinderService`) — no generic names like `XxxManager`, `XxxHelper`, `XxxUtil`
- [ ] **BE-066** — PHPUnit method names match the project's PHP-CS-Fixer config — `testDescriptiveCamelCase` under the default `php_unit_method_casing` rule, `test_descriptive_snake_case` only when that rule is disabled

## PHP / PHPStan idioms

- [ ] **BE-068** — Avoid `match` for closed, low-cardinality (≤6) value-to-value mappings where PHPStan cannot prove the scrutinee narrow (e.g. a Value Object method like `Priority::rank()` whose storage is `string`). Prefer a `private const array MAP = [...]` with `return self::MAP[$this->value];`. `match` either trips `match.unhandled` (no default + string scrutinee) or `match.alwaysTrue` (default becomes unreachable after input narrowing) at level 9. The array lookup has the same runtime cost, is shorter, and side-steps both errors. Applies to both new code and refactors. Two prior incidents in task-manager: (a) narrowed enum + unreachable default, (b) string VO with covered literals but no narrowing.

## Definition of Done

- [ ] **BE-067** — Every DoD item from the task file checked

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
- Voter pattern, Subject VO, tenant scoping, service-to-service identity → `authorization.md`
- Locale negotiation, translations storage, fallback chain, plurals/dates/currency formatting → `i18n.md`
- PII classification, encryption at rest, DSAR export, RTBF workflow, consent ledger, sub-processors → `gdpr-pii.md`
- LlmGatewayInterface, prompt templates, JSON-mode validation, prompt cache, PiiPromptGuard, tool use → `llm-integration.md`
- Money VO, ledger discipline, webhook idempotency, state machines, reconciliation, splits → `payments-and-money.md`
- Bucket layout, presigned URLs, antivirus, magic-byte, video pipeline, variants, retention → `file-and-media-storage.md`

If you find a rule violation that is NOT in this checklist, add it as `minor` in your review and include the file/line where the missing rule should live — the orchestrator will assign the next free ID in the matching prefix.
