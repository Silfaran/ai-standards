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

## Docker

The service `Dockerfile` must run migrations automatically on container start before launching `php-fpm`:

```dockerfile
CMD ["sh", "-c", "php vendor/bin/phinx migrate --environment=default && php-fpm"]
```

This ensures the database schema is always up to date when the container starts, regardless of environment.

## RabbitMQ & Messaging

### When to use async messaging

Async messaging via RabbitMQ is **optional** — only introduce it when a feature genuinely requires it.
Do not add async infrastructure speculatively. Sync buses are the default.

| Scenario | Use |
|---|---|
| Write operation within one service | Sync `command.bus` |
| Read operation within one service | Sync `query.bus` |
| Domain event that other services must react to | Async via RabbitMQ |
| Cross-service application message (e.g. send email) | Async via RabbitMQ |
| Long-running background job | Async via RabbitMQ |

---

### Message types and base contracts

Every async message **must** implement an interface that enforces a `messageName()` method.
This string is used as the serialization type discriminator — never rely on the PHP FQCN for cross-service identification.

```php
// Domain events — raised by aggregates, consumed by other services
interface DomainEventInterface
{
    public function messageName(): string;
}

// Cross-service application messages — explicit intent, not domain state
interface ApplicationMessageInterface
{
    public function messageName(): string;
}
```

**`messageName()` naming convention:**
```
{service_name}.{type}.{snake_case_name}

Examples:
  login_service.event.user_registered
  login_service.event.user_logged_in
  task_service.event.task_assigned
  login_service.message.send_email
```

The `type` segment is always one of: `event`, `command`, `message`.

---

### Serializer

**All async transports MUST use `messenger.transport.symfony_serializer`** (JSON), never the default `PhpSerializer`.

**Why this is critical:**
- `PhpSerializer` (default) embeds a `BusNameStamp` with the origin bus name (e.g. `event.bus`) in the serialized payload. When the consumer service receives it, Symfony tries to route the message to that bus — which does not exist in the consumer → crash. This failure is silent in logs and very hard to debug.
- JSON serializer does not embed bus stamps — the consumer handles the message without any cross-service bus dependency.
- JSON is readable in the RabbitMQ Management UI.
- JSON is language-agnostic for future non-PHP consumers.

**Required dependencies** (add to every service that uses async messaging):
```json
"symfony/serializer": "8.0.*",
"symfony/property-access": "8.0.*"
```

**Transport configuration** (`messenger.yaml`):
```yaml
transports:
    async_events:
        dsn: '%env(RABBITMQ_URL)%'
        serializer: messenger.transport.symfony_serializer
        options: ...
```

**Always run `composer update` after adding these dependencies to regenerate `composer.lock`.**
Never edit `composer.json` manually and leave the lock file out of sync — the Docker build will fail.

---

### Symfony Messenger bus configuration

When a service defines multiple buses (e.g. `command.bus`, `event.bus`, `message.bus`):

1. Always set `default_bus` explicitly — Symfony requires it when more than one bus is defined:
```yaml
framework:
    messenger:
        default_bus: command.bus
        buses:
            command.bus: ~
            event.bus:
                default_middleware:
                    enabled: true
                    allow_no_handlers: true
            message.bus:
                default_middleware:
                    enabled: true
                    allow_no_handlers: true
```

2. Use a dedicated `message.bus` (not `event.bus`) to dispatch cross-service application messages.
This ensures no domain-event bus stamp leaks into the payload.

3. In consumer services (e.g. `notification-service`), register the handler explicitly for the bus that matches the incoming stamp:
```yaml
# services.yaml
App\Application\Handler\SendEmailHandler:
    tags:
        - { name: messenger.message_handler, bus: message.bus }
```

---

### Exchanges

| Exchange | Type | Purpose |
|---|---|---|
| `events` | fanout | Domain events published by this service |
| `commands` | direct | Async commands between services (only if needed) |
| One per application message category | fanout | e.g. `emails` for `SendEmailEvent` |

Never route commands and events through the same exchange. Add a dedicated exchange per distinct message category.

---

### Queues and dead letter topology

Each service that consumes messages must declare:

| Queue | Purpose |
|---|---|
| `{service}.commands` | Async commands consumed by this service |
| `{service}.events` | Domain events consumed by this service |
| `{service}.commands.dead` | Failed commands after max retries |
| `{service}.events.dead` | Failed events after max retries |

**Why separate dead letter queues per type:**
A failed command (an action that did not execute) has a different urgency and recovery strategy than a failed event (a notification that was not delivered). Separating them allows targeted monitoring and reprocessing as the system grows.

Example for `notification-service`:
```
notification_service.events           ← consumes SendEmailEvent
notification_service.events.dead      ← emails that failed after 3 retries
```

---

### Retry and dead letter configuration

- **Max retries:** 3
- **Retry delay:** 5 minutes (300,000 ms), constant (multiplier: 1)
- **After max retries:** message moved to the dead letter transport
- **Dead letter queues are NOT retried automatically** — they require explicit manual or tooling intervention

```yaml
framework:
    messenger:
        default_bus: command.bus
        failure_transport: events_dead   # use commands_dead for command transports

        transports:
            async_events:
                dsn: '%env(RABBITMQ_URL)%'
                serializer: messenger.transport.symfony_serializer
                options:
                    exchange:
                        name: events
                        type: fanout
                    queues:
                        my_service.events: ~
                retry_strategy:
                    max_retries: 3
                    delay: 300000
                    multiplier: 1

            events_dead:
                dsn: '%env(RABBITMQ_URL)%'
                serializer: messenger.transport.symfony_serializer
                options:
                    exchange:
                        name: events.dead
                        type: direct
                    queues:
                        my_service.events.dead: ~

when@test:
    framework:
        messenger:
            transports:
                async_events: 'in-memory://'
                events_dead: 'in-memory://'
```

---

### Cross-service message contracts

When two services exchange a message:

1. **Both must define the same class** under the **exact same FQCN**: `App\Infrastructure\Messenger\Message\{MessageName}.php`
2. Both definitions must be **byte-for-byte identical** in constructor signature, property types, and `@param` PHPDoc annotations (required for PHPStan level 9)
3. Any change to the constructor is a **breaking change** — must be coordinated and deployed simultaneously in both services
4. The `messageName()` return value must also match exactly — it is the JSON type discriminator

```php
// login-service/src/Infrastructure/Messenger/Message/SendEmailEvent.php
// notification-service/src/Infrastructure/Messenger/Message/SendEmailEvent.php
// Both files must be identical:

final class SendEmailEvent implements ApplicationMessageInterface
{
    /**
     * @param array<string, mixed> $variables
     */
    public function __construct(
        public readonly string $to,
        public readonly string $subject,
        public readonly string $template,
        public readonly array $variables = [],
    ) {}

    public function messageName(): string
    {
        return 'login_service.message.send_email';
    }
}
```

---

### Consumer worker services

Services that only consume messages (no HTTP layer) follow different infrastructure rules:

**Dockerfile:**
```dockerfile
FROM php:8.4-cli   # NOT php-fpm — no HTTP server needed

# No pdo_pgsql, no pgsql if no database
# Install amqp extension for RabbitMQ
RUN pecl install amqp && docker-php-ext-enable amqp

# Clear Symfony cache on start — CRITICAL when using volume mounts in dev.
# Without this, the container may boot with stale compiled cache from a previous
# build, causing silent failures (wrong serializer, missing buses, etc.)
CMD ["sh", "-c", "php bin/console cache:clear --no-warmup && php bin/console messenger:consume async_events --no-debug --time-limit=3600"]
```

**Why `cache:clear` on every start:**
In development, the source code is mounted as a Docker volume. The compiled Symfony cache
(`var/cache/`) is also part of that volume. If the cache was generated by a previous image
(with a different configuration), the new container will use stale compiled config — causing
silent failures that are very hard to trace. Always clear it on startup.

**Why `--no-debug`:**
In `APP_ENV=dev`, Symfony wraps the event dispatcher with `TraceableEventDispatcher`.
This causes a fatal crash in `messenger:consume` when the worker receives a `WorkerRunningEvent`.
The `--no-debug` flag disables it without changing the environment.

**Why `--time-limit=3600`:**
Prevents memory leaks from accumulating over long-running processes. The container's `restart: unless-stopped` policy ensures the worker is restarted automatically after each cycle.

**`docker-compose.yml` requirements for worker containers:**
```yaml
notification-service:
    restart: unless-stopped   # REQUIRED — restarts after crashes or time-limit exits
    depends_on:
        - rabbitmq
        # also depend on any other service it connects to (e.g. mailpit in dev)
```

**No Nginx companion container** — worker services have no HTTP interface.

---

### Composer recipes and `.env` pollution

When running `composer require` or `composer update`, Symfony Flex may append recipe boilerplate
to `.env` and create new config files (e.g. `config/packages/routing.yaml` with `DEFAULT_URI`).

**Always review and clean up after adding dependencies:**
- Remove any auto-appended blocks from `.env` that duplicate or conflict with existing variables
- Remove or simplify generated config files that reference env vars not needed by this service
  (e.g. `routing.yaml` with `DEFAULT_URI` is not needed in a worker-only service)
- Never leave `composer.json` and `composer.lock` out of sync — the Docker build will fail with
  `"Required package X is not present in the lock file"`

## Testing

### Philosophy

- **Integration tests by default** — they test real behavior through the HTTP layer
- **Unit tests only** when integration is impractical: pure domain logic with complex rules, external services that can't be stubbed at the transport level (emails, third-party APIs)
- Every feature must have tests before it is considered complete

### Test structure

```
tests/
├── bootstrap.php
├── Unit/
│   └── Domain/
│       └── Model/
│           └── PasswordTest.php        ← domain rule tests
└── Integration/
    └── {Aggregate}/
        └── {Action}{Aggregate}ControllerTest.php   ← HTTP endpoint tests
```

### PHPUnit configuration

`phpunit.dist.xml` defines two test suites and environment overrides:

```xml
<phpunit bootstrap="tests/bootstrap.php" cacheDirectory=".phpunit.cache"
         colors="true" failOnDeprecation="true" failOnNotice="true" failOnWarning="true">
    <php>
        <ini name="display_errors" value="1" />
        <ini name="error_reporting" value="-1" />
        <env name="APP_ENV" value="test" force="true" />
        <env name="KERNEL_CLASS" value="App\Kernel" force="true" />
        <env name="DATABASE_URL" value="postgresql://workspace:workspace@postgres:5432/workspace?serverVersion=17" force="true" />
    </php>

    <testsuites>
        <testsuite name="unit">
            <directory>tests/Unit</directory>
        </testsuite>
        <testsuite name="integration">
            <directory>tests/Integration</directory>
        </testsuite>
    </testsuites>

    <source>
        <include>
            <directory>src</directory>
        </include>
    </source>
</phpunit>
```

**Important:** Use `<env>` tags, not `<server>` — `<server>` does not work reliably in Docker containers.

---

### Integration tests

Integration tests extend `WebTestCase` and test the full HTTP request/response cycle.

```php
final class RegisterUserControllerTest extends WebTestCase
{
    private KernelBrowser $client;
    private Connection $connection;

    protected function setUp(): void
    {
        $this->client = self::createClient();
        /** @var Connection $connection */
        $connection = static::getContainer()->get(Connection::class);
        $this->connection = $connection;
        // Clean state before each test
        $this->connection->executeStatement('DELETE FROM refresh_tokens');
        $this->connection->executeStatement('DELETE FROM users');
    }

    public function testRegisterWithValidDataReturns201AndUserIsPersisted(): void
    {
        $this->client->request(
            'POST',
            '/api/register',
            [],
            [],
            ['CONTENT_TYPE' => 'application/json'],
            (string) json_encode([
                'first_name' => 'John',
                'last_name' => 'Doe',
                'email' => 'john@example.com',
                'password' => 'Password1!',
            ]),
        );

        self::assertResponseStatusCodeSame(201);

        $count = $this->connection->fetchOne(
            'SELECT COUNT(*) FROM users WHERE email = ?',
            ['john@example.com'],
        );
        self::assertSame(1, (int) $count);
    }
}
```

#### Rules

- **One test class per controller** — matches the one-controller-per-action pattern
- **Clean the database in `setUp()`** — delete in reverse FK order, never truncate (avoids lock issues)
- **Assert both the HTTP response and the database state** — a 201 alone does not prove persistence
- **Test error paths**: missing fields (422), duplicate data (409), invalid input (422), unauthorized (401)
- **Use `(string) json_encode()`** for request bodies — always cast to string
- **PHPDoc `@var` annotations** on container gets for PHPStan compliance

#### Testing async messages

In `when@test`, all async transports must be configured as `in-memory://`:

```yaml
when@test:
    framework:
        messenger:
            transports:
                async_events: 'in-memory://'
                email: 'in-memory://'
                events_dead: 'in-memory://'
```

Then assert dispatched messages in tests:

```php
public function testRegisterDispatchesSendEmailEvent(): void
{
    $this->client->request('POST', '/api/register', [], [], ['CONTENT_TYPE' => 'application/json'],
        (string) json_encode([...]),
    );

    self::assertResponseStatusCodeSame(201);

    /** @var InMemoryTransport $transport */
    $transport = static::getContainer()->get('messenger.transport.email');

    $envelopes = $transport->get();
    self::assertCount(1, $envelopes);

    $message = $envelopes[0]->getMessage();
    self::assertInstanceOf(SendEmailEvent::class, $message);
    self::assertSame('john@example.com', $message->to);
}
```

---

### Unit tests

Unit tests extend `TestCase` (not `WebTestCase`) and test pure domain logic in isolation.

```php
final class PasswordTest extends TestCase
{
    public function test_valid_password_is_accepted(): void
    {
        $password = Password::fromPlainText('Password1!', fn (string $p) => 'hashed_' . $p);
        self::assertSame('hashed_Password1!', $password->hashedValue());
    }

    public function test_password_shorter_than_8_chars_throws(): void
    {
        $this->expectException(InvalidPasswordException::class);
        Password::fromPlainText('Pw1!', fn (string $p) => $p);
    }
}
```

#### Rules

- **No Symfony kernel, no database, no HTTP** — if you need any of these, write an integration test instead
- Use closures or anonymous classes to stub dependencies (e.g. password hasher)
- Test all validation branches — valid input, each invalid case, edge cases (boundary values, empty strings)
- Test that domain exceptions carry useful details (error lists, messages)
- Method naming: `test_descriptive_snake_case` for readability

---

### Test database

- Database name: same as production but tests use `DATABASE_URL` from `phpunit.dist.xml`
- Phinx `test` environment runs migrations against the test database
- Never share state between tests — each test cleans up in `setUp()`
- Seeds are for local dev only — tests create their own data

### Makefile commands

Every service must provide:

```makefile
make test              # run all tests (unit + integration)
make test-unit         # run only unit tests
make test-integration  # run only integration tests
```

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
