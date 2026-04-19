# Backend Standards

> Full code examples, scaffold implementations, and detailed configurations: `backend-reference.md`
> Copy-verbatim scaffold files: `ai-standards/scaffolds/`

## Code Architecture

All backend services follow Hexagonal Architecture + DDD + CQRS + Event-Driven.

### Layers

- **Domain** — aggregates, entities, value objects, domain events, repository interfaces, domain exceptions
- **Application** — commands, queries, handlers, application services
- **Infrastructure** — Symfony, Doctrine DBAL, repository implementations, controllers, external services

### CQRS

- **CommandBus** — write operations (synchronous via Symfony Messenger)
- **QueryBus** — read operations (synchronous via Symfony Messenger)
- **EventBus** — async domain events via RabbitMQ
- Never mix commands and queries

## Folder Structure

```
src/
├── Domain/
│   ├── Model/              ← aggregates, entities, value objects
│   ├── Event/              ← domain events
│   ├── Repository/         ← repository interfaces
│   └── Exception/          ← domain exceptions
├── Application/
│   ├── Command/{Aggregate}/{ActionAggregate}/
│   │   ├── {ActionAggregate}Command.php
│   │   └── {ActionAggregate}CommandHandler.php
│   ├── Query/{Aggregate}/{ActionAggregate}/
│   │   ├── {ActionAggregate}Query.php
│   │   └── {ActionAggregate}QueryHandler.php
│   └── Service/            ← application services grouped by aggregate
└── Infrastructure/
    ├── Persistence/        ← DBAL repositories, Phinx migrations, seeds
    ├── Messenger/          ← bus and token services
    ├── Http/               ← one controller per command/query
    │   └── {Aggregate}/
    └── External/           ← calls to external services
```

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

## Application Services

Handlers **orchestrate**, they do NOT contain business logic. A handler reads like a short script: resolve aggregates → check access → call services → persist. A handler may call one or many services — the number is not a quality metric. The quality metric is "does the handler contain domain logic that is reusable, complex, or worth testing in isolation?". If yes, extract it.

- Handlers call application services, not repositories directly
- One service, one responsibility, one `execute()` method — always named `execute`
- Services inject repository interfaces, never implementations
- **Services MAY depend on other services.** A service can compose other services to reuse existing logic (e.g. an `InviteBoardMemberService` calls `BoardAccessAuthorizationService` internally). Composition is preferred over duplication — do NOT reinvent logic that already lives in another service

### Naming services

Every application service class name MUST end with `Service` (e.g. `UserFinderService.php`). Use these patterns to make the service's purpose unambiguous:

| Pattern | Use for | Example |
|---|---|---|
| `{Aggregate}FinderService` | Throw-on-miss lookups (by id, email, composite keys) — repositories stay nullable, the finder throws | `UserFinderService`, `BoardFinderService` |
| `{Aggregate}AccessAuthorizationService` | Ownership / permission checks shared across handlers | `BoardAccessAuthorizationService` |
| `{Aggregate}{Operation}Service` | A specific domain operation with orchestration or branching | `BoardDeletionService`, `BoardMemberInvitationService` |
| `{Aggregate}{Topic}ValidatorService` | Reusable domain validation | `TaskAssigneeValidatorService` |
| `{Aggregate}{Topic}CalculatorService` | Derived/calculated values | `TaskDueDateCalculatorService` |

If none of the patterns fit, choose a name that describes the ONE thing the service does — never invent generic names (`BoardManagerService`, `BoardHelperService`, `BoardUtilService` are all forbidden).

### When to extract logic from a handler to a service

Extract to a service if ANY of the following apply:

- The same sequence (find + check + throw, authorization check, cross-repo orchestration) appears in 2+ handlers
- The handler coordinates 2+ repositories for a single domain operation (cascade delete, cross-aggregate update)
- The handler enforces a domain rule beyond simple field validation (ownership/authorization, state-transition guard, uniqueness across non-trivial conditions)
- The handler contains branching business logic ("if already exists, reactivate; else create", multi-step transitions)
- A query composes a read model across 3+ repositories/projections

Do NOT extract when:

- The handler has a single repository call plus one `save()` — that IS the operation
- The handler only fetches one aggregate via `getById()` and returns it as a query response

### Repositories: nullable lookups only

Repository interfaces are pure data-access abstractions. They know how to load and persist aggregates; they have no opinion on whether absence is an error, because that decision is domain semantics and belongs in a service.

- Repository id lookups return `?Entity` ALWAYS: `findById(Id): ?Entity`, `findByEmail(...): ?Entity`, etc.
- Repositories MUST NOT expose throw-on-miss methods (`getById`, `findOrFail`, `getOrThrow`, …). The repository interface stays nullable-only.
- Throw-on-miss lives in a `{Aggregate}FinderService`. Example signature: `BoardFinderService::findById(BoardId): Board` (throws `BoardNotFoundException`). The finder may expose any number of throw-on-miss lookups — `findByEmail`, `findByBoardAndUser`, etc.
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
- Method naming: `test_descriptive_snake_case`

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
| Application Service | `UserFinderService` |
| Controller | `CreateUserController` |
| Exception | `UserNotFoundException` |
