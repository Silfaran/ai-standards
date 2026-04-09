# Backend Standards

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

**Important:** Exclude `Migration/` and `Seed/` from Symfony service auto-discovery in `services.yaml`:
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

```php
final class Email {
    private function __construct(private readonly string $value) {}
    public static function from(string $value): self { ... }
}

final class LoginUserCommand {
    private function __construct(public readonly string $email, ...) {}
    /** @param array<string, mixed> $payload */
    public static function from(array $payload): self { Assert::...; return new self(...); }
}

final class User {
    private function __construct(...) {}
    public static function create(...): self { /* raises domain events */ }
    public static function from(...): self   { /* rehydrates from DB */ }
}
```

## Commands and Queries

- Private constructor — only entry point is `static from()`
- `from()` validates the raw payload using `webmozart/assert`
- Invalid input throws `InvalidArgumentException` → `ApiExceptionSubscriber` maps it to 422
- No validation logic in controllers

## Application Services

- Handlers call application services, not repositories directly
- One service, one responsibility, one `execute()` method — always named `execute`
- Services inject repository interfaces, never implementations
- If a nullable result is acceptable, call the repository directly — no service needed
- Handlers can call multiple services; services can call other services

## Controllers

- Extend `AppController` — provides `dispatchCommand()`, `dispatchQuery()`, `body()`, `json()`, `noContent()`, `created()`
- Only interact with buses via `dispatchCommand()` / `dispatchQuery()` — never call services directly
- Build commands/queries via `SomeCommand::from(...)` — no validation logic in the controller
- One controller per command/query — always
- All controllers must have OpenAPI/Swagger annotations

## Command Handlers

- Tagged to `command.bus` via `services.yaml` — autowiring alone is not enough
- MAY return data via HandledStamp when the HTTP layer needs it — not a CQRS violation here

## Database

- PostgreSQL with Doctrine DBAL only — no ORM
- Phinx for migrations and seeds
- Migrations: `src/Infrastructure/Persistence/Migration/`
- Seeds: `src/Infrastructure/Persistence/Seed/` — local dev only, never run in production
- Never modify already executed migrations — always create a new one
- Each service with a database must have at least one seed with realistic test data

## Testing

- PHPUnit integration tests by default
- Unit tests only when integration is not possible (external services, emails, etc.)
- Test database: configure `workspace_test` via `phpunit.dist.xml` + Phinx `test` environment
- `phpunit.dist.xml` must use `<env>` (not `<server>`) to set `APP_ENV=test` when running in Docker

## Standard Libraries

| Purpose | Library |
|---|---|
| Input assertion / validation | `webmozart/assert` |
| UUID generation | `ramsey/uuid` |
| JWT authentication | `lexik/jwt-authentication-bundle` |
| Database migrations | `robmorgan/phinx` |
| HTTP client | Symfony `HttpClient` |
| Message bus | `symfony/messenger` |
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
