# Backend Standards

> Full code examples, scaffold implementations, and detailed configurations: `backend-reference.md`
> Copy-verbatim scaffold files: `ai-standards/scaffolds/`

## Code Architecture

All backend services follow Hexagonal Architecture + DDD + CQRS + Event-Driven.

### Layers

- **Domain** — aggregates, entities, value objects, domain events, repository interfaces, domain exceptions, **domain services** (pure business rules with no framework or I/O concerns beyond repository abstractions)
- **Application** — commands, queries, handlers, **application services** (use-case orchestrators — coordinate domain services, repositories and side effects)
- **Infrastructure** — Symfony, Doctrine DBAL, repository implementations, controllers, external services

> Services live on BOTH sides. The split is driven by responsibility, not by convention — see "Services — Domain vs Application placement" below for the decision rule. Historically some projects pushed all services into Application; that is incorrect under Hexagonal + DDD and produces artificial dependencies from pure rules to use-case code.

### CQRS

- **CommandBus** — write operations (synchronous via Symfony Messenger)
- **QueryBus** — read operations (synchronous via Symfony Messenger)
- **EventBus** — async domain events via RabbitMQ
- Never mix commands and queries

## Folder Structure

```
src/
├── Domain/
│   ├── Model/                     ← aggregates, entities, value objects
│   ├── Event/                     ← domain events
│   ├── Repository/                ← repository interfaces
│   ├── Exception/                 ← domain exceptions
│   └── Service/{Aggregate}/       ← domain services (pure business rules)
├── Application/
│   ├── Command/{Aggregate}/{ActionAggregate}/
│   │   ├── {ActionAggregate}Command.php
│   │   └── {ActionAggregate}CommandHandler.php
│   ├── Query/{Aggregate}/{ActionAggregate}/
│   │   ├── {ActionAggregate}Query.php
│   │   └── {ActionAggregate}QueryHandler.php
│   └── Service/{Aggregate}/       ← application services (use-case orchestrators)
└── Infrastructure/
    ├── Persistence/               ← DBAL repositories, Phinx migrations, seeds
    ├── Messenger/                 ← bus and token services
    ├── Http/                      ← one controller per command/query
    │   └── {Aggregate}/
    └── External/                  ← calls to external services
```

Both `Domain/Service/` and `Application/Service/` group classes by aggregate. The sub-folder is mandatory once a service count grows past 2-3 per layer, and recommended from the start for consistency.

Exclude `Migration/` and `Seed/` from Symfony service auto-discovery in `services.yaml`:

```yaml
App\:
    resource: '../src/'
    exclude:
        - '../src/Infrastructure/Persistence/Migration/'
        - '../src/Infrastructure/Persistence/Seed/'
```

## Named Constructors

Every class that should not be instantiated directly must use a **private constructor**:

- `static from(): self` — standard named constructor for value objects, commands, queries, DTOs
- `static create(): self` — **aggregates only**, new instance (raises domain events, sets timestamps)
- `static from(): self` — **aggregates only**, rehydration from DB (no domain events)
- Specific variants like `fromPlainText()` are acceptable when semantics differ significantly

## Commands and Queries

- Private constructor — only entry point is `static from()`
- `from()` validates the raw payload using `webmozart/assert`
- Invalid input throws `InvalidArgumentException` → `ApiExceptionSubscriber` maps it to 422
- No validation logic in controllers

## Services

Handlers **orchestrate**, they do NOT contain business logic. A handler reads like a short script: resolve aggregates → check access → call services → persist. A handler may call one or many services — the number is not a quality metric. The quality metric is "does the handler contain domain logic that is reusable, complex, or worth testing in isolation?". If yes, extract it.

Under Hexagonal + DDD + CQRS this codebase distinguishes two kinds of extracted services by their responsibility, and places them accordingly. **Every Command/Query Handler IS already an application service** — do not duplicate handlers with a parallel `{Action}UseCase` class. Explicit services exist only to host logic that does not fit inside a single handler.

### Services — Domain vs Application placement

| Kind | Lives in | Responsibility | What it MAY do | What it MUST NOT do |
|---|---|---|---|---|
| **Domain Service** | `src/Domain/Service/{Aggregate}/` | Encode a pure business rule that doesn't fit in an entity or VO | Read aggregates; raise domain exceptions; depend on repository INTERFACES and other domain services | Import from `App\Infrastructure\*`; orchestrate multiple aggregates; start transactions; publish events; send emails; call external APIs |
| **Application Service** | `src/Application/Service/{Aggregate}/` | Orchestrate a use case or reusable multi-step flow across domain services, repositories and side effects | Call domain services; coordinate multiple repos; publish events; call `message.bus`; return DTOs | Contain raw business rules — those are delegated to domain services or value objects; import from framework-coupled infra beyond buses/dispatchers |

**Decision rule — ask two questions, in order:**

1. *Is the logic a pure rule about the domain itself — same output for the same inputs, no side effects, expressible with aggregates and VOs?* → **Domain Service** in `src/Domain/Service/`.
2. *Does the logic coordinate domain services + repositories + side effects for a repeatable use case?* → **Application Service** in `src/Application/Service/`.

Most extractions in a CQRS codebase land in Domain, because the typical "coordination" responsibility is already absorbed by the Command/Query Handler. Explicit application services appear when the same orchestration repeats in 2+ handlers, or the flow is too involved to keep inside the handler (invitation state machine, cascade delete, import pipeline).

### Examples by type

| Service | Kind | Why |
|---|---|---|
| `BoardFinderService`, `UserFinderService`, `TaskFinderService` | Domain | Encapsulates the invariant "a missing aggregate is exceptional" — no orchestration, no side effects |
| `BoardAccessAuthorizationService` | Domain | Encodes the rule "owner or active member with permission X" — reads domain objects, throws a domain exception |
| `TaskAssigneeValidatorService` | Domain | Validates an assignee candidate against domain invariants (active membership) — reusable rule |
| `TaskDueDateCalculatorService` | Domain | Derives a value from the domain with no side effects |
| `BoardDeletionService` | Application | Orchestrates cascade delete across 7 repositories and publishes an event — no single domain rule, it's a workflow |
| `BoardMemberInvitationService` | Application | Multi-step flow: authorize → state-machine check → reactivate-or-create member → send email → publish event |
| `ColumnDeletionService` | Application | Orchestrates the default-column guard → task relocation → column delete |

### Class declaration — `readonly class`, not `final`

Every service class MUST be declared `readonly class {Name}Service` — NOT `final`. Rationale: PHPUnit 13 rejects `createMock()` on `final` classes (`ClassIsFinalException`), which collides with handler unit tests that need to mock a collaborating service. `readonly` preserves immutability without blocking test doubles. This applies to both domain and application services.

Handler unit tests default to **composing the real service with a fake in-memory repository** (Option B) — the service is stateless and cheap to construct, and fakes are closer to integration than mocks. `createMock($service)` (Option A) is available as a fallback for a specific test where composing a fake is demonstrably noisier, and works because the class is non-`final`.

### One public method (`execute`) — no exceptions

**100% of services expose exactly ONE public method**: `execute()`. The constructor is the only other public member. Any additional method the service needs MUST be `private` and called from `execute()`. There are no exceptions — not for finders, not for authorization services, not for "twin signatures for composition efficiency", not for anything. If a second public method feels necessary, split into two services (e.g. the by-id finder `UserFinderService` and the by-email finder `UserFinderByEmailService` are two classes, not one).

### Services composition and DI

- Services inject repository INTERFACES (Domain), never implementations (Infrastructure)
- **Services MAY depend on other services.** Composition is preferred over duplication — do NOT reinvent logic that already lives in another service. An application service typically composes 1+ domain services (e.g. `BoardMemberInvitationService` → `BoardAccessAuthorizationService`). A domain service composes other domain services when useful, but NEVER composes an application service (that would invert the layer dependency rule)
- Handlers call services, not repositories directly — except for `save()`, `delete()` or genuinely nullable "if exists then X else Y" lookups

### Naming services

Every service class name MUST end with `Service` (e.g. `UserFinderService.php`). Use these patterns to make the service's purpose unambiguous:

| Pattern | Kind | Use for | Example |
|---|---|---|---|
| `{Aggregate}FinderService` | Domain | Default throw-on-miss lookup by id | `UserFinderService`, `BoardFinderService` |
| `{Aggregate}FinderBy{Key}Service` | Domain | Variant throw-on-miss lookups (by email, composite keys) — one class per key shape | `UserFinderByEmailService`, `BoardMemberFinderByBoardAndUserService` |
| `{Aggregate}AccessAuthorizationService` | Domain | Ownership / permission rule shared across handlers | `BoardAccessAuthorizationService` |
| `{Aggregate}{Topic}ValidatorService` | Domain | Reusable domain validation rule | `TaskAssigneeValidatorService` |
| `{Aggregate}{Topic}CalculatorService` | Domain | Derived/calculated values | `TaskDueDateCalculatorService` |
| `{Aggregate}{Operation}Service` | Application | Use-case orchestration (cascade delete, multi-step flow) | `BoardDeletionService`, `BoardMemberInvitationService`, `ColumnDeletionService` |
| `{Aggregate}{Topic}ReadService` | Application | Read-model composition across 3+ projections | `AccessibleBoardsReadService` |

If none of the patterns fit, choose a name that describes the ONE thing the service does — never invent generic names (`BoardManagerService`, `BoardHelperService`, `BoardUtilService` are all forbidden).

### When to extract logic from a handler to a service

Extract to a service if ANY of the following apply (and place according to the two-question rule above):

- The same sequence (find + check + throw, authorization check, cross-repo orchestration) appears in 2+ handlers
- The handler coordinates 2+ repositories for a single domain operation (cascade delete, cross-aggregate update) → typically Application
- The handler enforces a domain rule beyond simple field validation (ownership/authorization, state-transition guard, uniqueness across non-trivial conditions) → typically Domain
- The handler contains branching business logic ("if already exists, reactivate; else create", multi-step transitions) → Application (it's orchestration) unless the branch is a pure domain rule
- A query composes a read model across 3+ repositories/projections → Application

Do NOT extract when:

- The handler has a single repository call plus one `save()` — that IS the operation
- The handler only fetches one aggregate via the finder and returns it as a query response

### Repositories: nullable lookups only

Repository interfaces are pure data-access abstractions. They know how to load and persist aggregates; they have no opinion on whether absence is an error, because that decision is domain semantics and belongs in a domain service.

- Repository id lookups return `?Entity` ALWAYS: `findById(Id): ?Entity`, `findByEmail(...): ?Entity`, etc.
- Repositories MUST NOT expose throw-on-miss methods (`getById`, `findOrFail`, `getOrThrow`, …). The repository interface stays nullable-only.
- Throw-on-miss lives in a **domain** `{Aggregate}FinderService` at `src/Domain/Service/{Aggregate}/`. **One finder, one lookup, one `execute()` method** — the generic service rule applies without exception. Example: `BoardFinderService::execute(BoardId): Board` (throws `BoardNotFoundException`).
- Variant lookups on the same aggregate are **separate service classes** named `{Aggregate}FinderBy{Key}Service`. Canonical pair: `UserFinderService::execute(UserId): User` (default by id) and `UserFinderByEmailService::execute(Email): User` (variant by email) are two distinct classes — never merged, never a second method.
- Handlers and other services call the finder for reads where absence is an error. They call the repository directly for `save()`, `delete()`, and for lookups that are genuinely nullable by design (branch: "if exists then X else Y").

The `find + null check + throw` pattern does NOT belong in handlers — it lives in the finder. Canonical precedent: `UserFinderService` in login-service. This is the pattern to replicate for every aggregate that has a throw-on-miss need.

## Controllers

- Extend `AppController` — copy from `ai-standards/scaffolds/AppController.php` if it doesn't exist
- Provides `dispatchCommand()`, `dispatchQuery()`, `body()`, `json()`, `noContent()`, `created()`
- Only interact with buses via `dispatchCommand()` / `dispatchQuery()` — never call services directly
- Build commands/queries via `SomeCommand::from(...)` — no validation logic in the controller
- One controller per command/query — always
- All controllers must have OpenAPI/Swagger annotations
- `services.yaml` wiring: inject `$commandBus: '@command.bus'` and `$queryBus: '@query.bus'` by name

### ApiExceptionSubscriber

Every service must include the subscriber — copy from `ai-standards/scaffolds/ApiExceptionSubscriber.php` if it doesn't exist. Rules:

- `InvalidArgumentException` → 422 is always present — covers command/query validation failures
- Add one `match` arm per domain exception — keep the mapping exhaustive and explicit
- Never return 500 from a domain exception — every expected failure must have a mapped HTTP status

## Command Handlers

- Tagged to `command.bus` via `services.yaml` — autowiring alone is not enough
- MAY return data via HandledStamp when the HTTP layer needs it

## Database

- **Each service owns its own database** — never share or directly query another service's tables
- PostgreSQL with Doctrine DBAL only — no ORM
- Phinx for migrations and seeds
- Migrations: `src/Infrastructure/Persistence/Migration/`
- Seeds: `src/Infrastructure/Persistence/Seed/` — local dev only, never run in production
- Never modify already executed migrations — always create a new one
- Each service with a database must have at least one seed with realistic test data

## New Service Scaffold

Before committing a new service, verify it passes `ai-standards/standards/new-service-checklist.md`.
The single validation rule: `docker build .` must succeed with exit code 0.

## Docker

Each service has its own `docker-compose.yml` inside its directory. The root `docker-compose.yml` at the workspace root contains only shared infrastructure (PostgreSQL, RabbitMQ, Mailpit). All compose files share a `workspace-network` external network. See `devops-agent.md` for the full architecture.

Every service that uses a database must have its **own database** — services must never share a database. The `DATABASE_URL` must point to a service-specific database (e.g. `login`, `task`), not a shared one.

The service `Dockerfile` must run migrations on container start:

```dockerfile
CMD ["sh", "-c", "php vendor/bin/phinx migrate --environment=default && php-fpm"]
```

## RabbitMQ & Messaging

> Full configuration (exchanges, queues, dead letter, retry, cross-service contracts, consumer workers): see `backend-reference.md`

### When to use async messaging

| Scenario | Use |
|---|---|
| Write operation within one service | Sync `command.bus` |
| Read operation within one service | Sync `query.bus` |
| Domain event that other services must react to | Async via RabbitMQ |
| Cross-service application message (e.g. send email) | Async via RabbitMQ |
| Long-running background job | Async via RabbitMQ |

### Key rules

- Every command, query, domain event, and async message must implement an interface with `messageName()`
- `messageName()` format: `{service_name}.{type}.{snake_case_action}` — type: `command`, `query`, `event`, `message`
- All async transports MUST use `messenger.transport.symfony_serializer` (JSON), never `PhpSerializer`
- When defining multiple buses, always set `default_bus` explicitly
- Use a dedicated `message.bus` (not `event.bus`) for cross-service application messages
- Cross-service messages must have identical FQCN, constructor signature, and `messageName()` in both services
- Required dependencies for async: `symfony/serializer` + `symfony/property-access`
- Always run `composer update` after adding dependencies to regenerate `composer.lock`
- Never leave `composer.json` and `composer.lock` out of sync — Docker build will fail

### Resilience — retries, DLQ, poison messages

Every async transport declares an explicit retry policy and a dead-letter transport. A consumer that crashes on a malformed message without a DLQ blocks the entire queue — this is the most common async production incident and is prevented at configuration time.

```yaml
# config/packages/messenger.yaml
framework:
  messenger:
    transports:
      async_events:
        dsn: '%env(MESSENGER_TRANSPORT_DSN)%'
        options:
          exchange: { name: events, type: topic }
          queues: { task-service.events: { binding_keys: ['*.event.*'] } }
        retry_strategy:
          max_retries: 3
          delay: 1000          # 1 s
          multiplier: 2        # 1 s, 2 s, 4 s
          max_delay: 10000
        failure_transport: failed_events

      failed_events:
        dsn: 'doctrine://default?queue_name=failed_events'
```

Mandatory rules:

- **Every async transport** (`async_events`, `async_messages`, any service-specific transport) declares `retry_strategy` with a finite `max_retries` and a bounded `max_delay`. No infinite retries — a failed handler retries at most 3 times by default.
- **Every async transport** declares a `failure_transport`. The DLQ may be a Doctrine-backed queue for inspection (`failed_events`, `failed_messages`). It is NEVER the same transport as the live one.
- **Unrecoverable errors throw `UnrecoverableMessageHandlingException`.** These skip retries and go straight to the DLQ. Validation failures, missing aggregates, and authorization rejections on async messages are all unrecoverable — retrying them will never succeed.
- **Idempotent handlers.** Every handler is safe to execute more than once for the same message. Either the operation is naturally idempotent (state transition guarded by a conditional write) or the handler deduplicates on a message id persisted alongside the write.
- **Failure is observable.** A failed message emits a log at `error` level with the full `messageName()`, the message id, the exception class, and the `trace_id`. The `messenger_handler_errors_total` metric increments (see [`observability.md`](observability.md)).
- **DLQ size is alerted on.** The `failure_transport` queue depth is a first-class metric. The project's SLOs treat "DLQ depth > 0 for N minutes" as an incident.
- **Replay is manual, audited, and explicit.** `messenger:failed:show`, `messenger:failed:retry` (one id at a time for small volumes; scripted replay with explicit id list for larger ones). Never blanket-retry an entire DLQ without first triaging — a poison message will crash the consumer again.

### Consumer workers — resource discipline

- Each consumer runs with `--limit=100 --time-limit=3600 --memory-limit=256M` (or stricter). Long-running PHP workers leak, bounded restarts are the cheapest fix.
- `--failure-limit` is set so a consumer that hits too many failures in a row exits and lets the supervisor restart it from a clean state.
- Consumer deployments run **before** producers so there is never a producer enqueuing messages that no consumer can handle.
- The supervisor (systemd, supervisord, k8s) restarts the worker on exit with a backoff — never a tight loop.

### Queue-depth visibility

Every async transport exposes its depth as a metric (`messenger_queue_depth`, labeled by `transport` and `queue`). Unbounded depth growth is the earliest signal that consumers are falling behind; catching it on the metric is cheaper than catching it on user reports. See [`observability.md`](observability.md) for the metric definition.

## Testing

> Full test examples (integration, unit, async messages, PHPUnit config): see `backend-reference.md`

### Philosophy

- **Integration tests by default** — test real behavior through the HTTP layer
- **Unit tests only** when integration is impractical: pure domain logic, external services
- Every feature must have tests before it is considered complete

### Test structure

```
tests/
├── bootstrap.php
├── Unit/
│   └── Domain/Model/       ← domain rule tests
└── Integration/
    └── {Aggregate}/
        └── {Action}{Aggregate}ControllerTest.php
```

### Integration test rules

- One test class per controller
- Clean the database in `setUp()` — delete in reverse FK order, never truncate
- Assert both the HTTP response and the database state
- Test error paths: missing fields (422), duplicate data (409), invalid input (422), unauthorized (401)
- Use `(string) json_encode()` for request bodies
- PHPDoc `@var` annotations on container gets for PHPStan
- In `when@test`, all async transports must be `in-memory://`
- Use `<env>` tags in `phpunit.dist.xml`, not `<server>`

### Unit test rules

- No Symfony kernel, no database, no HTTP — if you need these, write an integration test
- Use closures or anonymous classes to stub dependencies
- Test all validation branches — valid input, each invalid case, edge cases
- Method naming: `testDescriptiveCamelCase` — matches PHP-CS-Fixer's default `php_unit_method_casing` rule (`camelCase`). Use `test_descriptive_snake_case` only when the project has explicitly disabled that CS-Fixer rule

### Makefile commands

Every service must provide: `make test`, `make test-unit`, `make test-integration`

## Standard Libraries

| Purpose | Library |
|---|---|
| Input assertion / validation | `webmozart/assert` |
| UUID generation | `ramsey/uuid` |
| JWT authentication | `lexik/jwt-authentication-bundle` |
| Database migrations | `robmorgan/phinx` |
| HTTP client | Symfony `HttpClient` |
| Message bus | `symfony/messenger` |
| Message serialization (cross-service) | `symfony/serializer` + `symfony/property-access` |
| Testing | `phpunit/phpunit` + `symfony/browser-kit` |
| Static analysis | `phpstan/phpstan` (level 9) |
| Code formatting | `friendsofphp/php-cs-fixer` |
| API documentation | `nelmio/api-doc-bundle` + `zircote/swagger-php` |

## Naming Conventions

| Type | Example |
|---|---|
| Command | `CreateUserCommand` |
| Command Handler | `CreateUserCommandHandler` |
| Query | `GetUserQuery` |
| Query Handler | `GetUserQueryHandler` |
| Domain Event | `UserCreatedEvent` |
| Aggregate | `User` |
| Value Object | `UserId` |
| Repository Interface | `UserRepositoryInterface` |
| Repository Implementation | `DbalUserRepository` |
| Domain Service | `UserFinderService`, `BoardAccessAuthorizationService` |
| Application Service | `BoardDeletionService`, `BoardMemberInvitationService` |
| Controller | `CreateUserController` |
| Exception | `UserNotFoundException` |
