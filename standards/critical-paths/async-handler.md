# Critical path — Async message handler

Use when the diff adds or modifies a Symfony Messenger handler reachable on an **async** transport — domain-event consumers (`event.bus → async_events`), cross-service application messages (`message.bus → ...`), or async write commands following ADR-009 (`async.command.bus → async_*`). Combine with other paths for cross-cutting concerns (PII, files, payments, LLM, signature).

## When to load this path

**PRIMARY trigger** (load this path as core when):
- A new class implements `App\Domain\Event\DomainEventInterface`, an `ApplicationMessageInterface`, or an `AsyncCommandInterface`
- A new `#[AsMessageHandler(bus: '<async-bus>')]` handler
- A new `WorkerMessageFailedEvent` subscriber

**SECONDARY trigger** (load only when no primary path covers the diff already):
- A new transport / queue / exchange / routing rule in `config/packages/messenger.yaml`
- A new long-running worker in any `docker-compose.yml`
- A modification to the retry strategy / DLQ config of an existing transport

**DO NOT load when**:
- The diff only modifies tests
- The diff only modifies `*.md`
- The handler is fully synchronous (`#[AsMessageHandler(bus: 'command.bus')]` without async transport — use `crud-endpoint.md` instead)

## Backend

### Hard blockers
- BE-001 Quality gates green
- BE-002 PHPStan L9 zero errors
- BE-003 PHP-CS-Fixer zero violations
- SE-001 No string concatenation in SQL
- SC-001 No secrets committed
- LO-001 No unredacted sensitive fields in logs
- DM-001 Migrations append-only (when the handler persists)

### Architecture & Domain purity
- BE-004 Folder layout Domain/Application/Infrastructure
- BE-005 Commands and queries separated
- BE-007 Services expose one public `execute` method
- BE-009 Doctrine / MessageBus → Application
- BE-010 Services declared `readonly class`
- BE-065 Service classes end with `Service` (Domain + Application; no `XxxChecker`/`XxxPadder`/`XxxValidator`)
- BE-022 Domain has zero Symfony / Doctrine imports
- BE-069 Domain exception factories accept primitives or Domain types only — never Symfony / Doctrine types as parameters
- BE-023 Aggregates use `static create()` / `static from()`
- BE-024 VOs / commands / queries use `private __construct` + `static from()`

### Message contracts
- BE-043 `messageName()` returns `{service}.{type}.{snake_case_action}` — covers commands, queries, events, messages
- BE-046 Cross-service messages: identical FQCN + constructor + `messageName()` in both services
- AC-008 No breaking change to message constructor without breaking-change protocol — additive fields with defaults only

### Transports & wiring
- BE-044 Transports use `messenger.transport.symfony_serializer` — never `PhpSerializer`
- BE-045 `default_bus` set explicitly when multiple buses exist
- BE-047 `composer.json` and `composer.lock` in sync (after adding `symfony/messenger`, `symfony/serializer`, `symfony/property-access`, transport dependencies)
- LO-002 LoggingMiddleware wired on every write bus (`command.bus`, `async.command.bus`, `event.bus`, `message.bus`) — `query.bus` excluded

### Resilience — retry, DLQ, idempotency
- BE-048 Every async transport declares `retry_strategy` with finite `max_retries` and bounded `max_delay` (no infinite retries)
- BE-049 Every async transport declares a `failure_transport` distinct from the live transport (DLQ exists, separate exchange / queue)
- BE-050 Unrecoverable failures (validation, missing aggregates, authorization rejections, permanent provider errors) throw `UnrecoverableMessageHandlingException` — never silently retried
- BE-051 Handler is idempotent: either naturally idempotent (state-machine guard, conditional write `INSERT … ON CONFLICT DO NOTHING`) or deduplicated via a persisted message id / idempotency key
- BE-072 `UnrecoverableMessageHandlingException` wrapping passes the original exception as `$previous`; failure-reason mappers unwrap `getPrevious()` before `instanceof` classification — otherwise every wrapped failure is classified as `unknown:UnrecoverableMessageHandlingException`

### Failure subscriber (when the feature uses one)
- BE-070 Idempotency-key recompute uses `$message->occurredAt` (or equivalent command-time field), NOT the real clock. State-transition timestamps DO use the real clock — the two `$now` values are intentionally different
- BE-071 Aggregate state transitions on async failure (`markRetrying`, `markDeadLettered`, `markFailed`, …) run inside a synchronous `WorkerMessageFailedEvent` listener — the row is updated BEFORE the framework acks the message to the failure transport. Post-worker hooks, batch reconciliation, or cron sweeps leave orphan `pending` rows
- BE-052 Failed handler (or failure subscriber) emits an `error` log with `messageName()`, message id, exception class, `trace_id`; `messenger_handler_errors_total` increments

### Workers (when the feature ships consumer workers)
- BE-053 Workers run `messenger:consume` with `--limit`, `--time-limit`, `--memory-limit`, `--failure-limit` — no unbounded long-running workers
- BE-054 No blanket DLQ replay — replay is per-id after triage

### Logging / PII
- LO-001 No unredacted sensitive fields in logs (covers Internal-PII per `gdpr-pii.md`); failed-handler error log MUST NOT include the raw payload if it contains PII — log `recipient_id` / pseudonymous identifier only
- LO-007 `LoggingMiddleware::SENSITIVE_FIELDS` extended in the same diff that introduces a new payload field whose tier is Internal-PII or Sensitive-PII

### Testing presence (Tester runs them, reviewer checks they exist)
- BE-056 Unit tests for domain rules (state machine transitions, idempotency-key formula, failure-reason mapping)
- BE-060 In test env, every async transport is `'in-memory://'` — `async_events`, `async_dispatch`, every per-feature transport, AND every paired `*_dead` failure transport
- BE-067 Definition of Done items checked

## Coverage map vs full checklist

This path covers these sections of `backend-review-checklist.md`:

- §Hard blockers — BE-001, BE-002, BE-003, SE-001, SC-001, LO-001, DM-001 (DM-001 only when the handler persists)
- §Architecture & Domain purity — BE-004, BE-005, BE-007, BE-009, BE-010, BE-022, BE-023, BE-024, BE-065, BE-069 (Domain layering, aggregates, VOs, exception factories — BE-006/BE-008/BE-011..BE-021 are NOT loaded; consult §Architecture if the diff touches them)
- §Message contracts — BE-043 + BE-046 + AC-008 (messageName, FQCN, breaking changes)
- §Transports & wiring — BE-044, BE-045, BE-047 + LO-002 (Symfony serializer, default_bus, composer sync, LoggingMiddleware)
- §Resilience — BE-048..BE-051 + BE-072 (retry, DLQ, idempotency, UnrecoverableMessageHandlingException wrapping)
- §Failure subscriber — BE-070, BE-071, BE-052 (idempotency-key recompute clock, sync state transition, error log shape)
- §Workers — BE-053, BE-054 (consume bounds, no blanket DLQ replay)
- §Logging / PII — LO-001, LO-007 (sensitive fields, SENSITIVE_FIELDS extension)
- §Testing presence — BE-056, BE-060, BE-067

This path does NOT cover. Load the corresponding checklist section ONLY when the diff touches:

- `tests/` directory (beyond the testing-presence stubs above) → load §Testing
- The CRUD shape of a synchronous Application service that publishes the message → load `crud-endpoint.md` (path)
- Migration adding the projection/state table the handler writes to → load §Migrations (DM-*)
- Caching of the materialised projection → load §Caching

## What this path does NOT cover

Open additional paths when the handler also touches:
- Personal data → [`pii-write-endpoint.md`](pii-write-endpoint.md) (e.g. an event consumer that writes a user-data projection)
- Files / generated documents → [`file-upload-feature.md`](file-upload-feature.md) (async transcode, antivirus pipeline, signed-document storage)
- Money → [`payment-endpoint.md`](payment-endpoint.md) (async escrow finalization, webhook handlers from a PSP)
- LLM calls → [`llm-feature.md`](llm-feature.md) (async classification, generation, translation jobs)
- Signed documents → [`signature-feature.md`](signature-feature.md) (async signature webhooks, document generation)
- Authorization on the originating action → [`auth-protected-action.md`](auth-protected-action.md) (when the producer is HTTP and gates the publish)

## Compositional usage

A "send welcome email on user_registered" feature combines this path with `pii-write-endpoint.md` (the welcome notification carries the user's email handle). A "render a PDF contract on contract_signed" feature combines this path with `file-upload-feature.md` + `signature-feature.md`. The reviewer NEVER skips a rule that appears in this path; it narrows the search, it does not relax the bar.
