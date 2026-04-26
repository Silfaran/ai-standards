# Backend Reference

> This file contains detailed code examples, scaffold implementations, and full configurations.
> Read this file only when you need to scaffold a new component or configure a feature for the first time.
> For rules and conventions, read `backend.md`.
> Version numbers embedded in examples below (PHP, PostgreSQL, Symfony) are the current minimums declared in [`tech-stack.md`](tech-stack.md). When that file is updated, update the matching examples here.

---

## Named Constructor Examples

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

---

## AppController

Copy from `ai-standards/scaffolds/AppController.php` to `src/Infrastructure/Http/AppController.php`.

**`services.yaml` wiring** — the two buses must be injected by name, not by type:

```yaml
App\Infrastructure\Http\AppController:
    abstract: true
    arguments:
        $commandBus: '@command.bus'
        $queryBus: '@query.bus'
```

**Usage example:**

```php
final class CreateBoardController extends AppController
{
    #[Route('/api/boards', methods: ['POST'])]
    public function __invoke(Request $request): JsonResponse
    {
        $body = $this->body($request);
        $data = $this->dispatchCommand(CreateBoardCommand::from($body));
        return $this->json($data, JsonResponse::HTTP_CREATED);
    }
}
```

---

## ApiExceptionSubscriber

Copy from `ai-standards/scaffolds/ApiExceptionSubscriber.php` to `src/Infrastructure/Http/EventSubscriber/ApiExceptionSubscriber.php`.

Adapt the `match` block for each service's domain exceptions. Rules:
- `InvalidArgumentException` → 422 is always present — covers command/query validation failures
- Add one `match` arm per domain exception — keep the mapping exhaustive and explicit
- Never return 500 from a domain exception — every expected failure must have a mapped HTTP status
- The `default => null` case leaves unmapped exceptions unhandled — Symfony returns 500

---

## Message Interfaces

Every command, query, domain event, and async message must implement an interface that enforces `messageName()`:

```php
// Sync commands — handled by command.bus within the same service
interface CommandInterface
{
    public function messageName(): string;
}

// Sync queries — handled by query.bus within the same service
interface QueryInterface
{
    public function messageName(): string;
}

// Domain events — raised by aggregates, published to RabbitMQ for other services
interface DomainEventInterface
{
    public function messageName(): string;
}

// Cross-service application messages — explicit async intent, not domain state
interface ApplicationMessageInterface
{
    public function messageName(): string;
}
```

**`messageName()` examples:**

```
login_service.command.register_user
login_service.query.get_user_by_email
login_service.event.user_registered
task_service.event.task_assigned
login_service.message.send_email
```

---

## Symfony Messenger Bus Configuration

When a service defines multiple buses:

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

Register handlers explicitly for the bus that matches the incoming stamp:

```yaml
# services.yaml
App\Application\Handler\SendEmailHandler:
    tags:
        - { name: messenger.message_handler, bus: message.bus }
```

---

## Exchanges

| Exchange | Type | Purpose |
|---|---|---|
| `events` | fanout | Domain events published by this service |
| `commands` | direct | Async commands between services (only if needed) |
| One per application message category | fanout | e.g. `emails` for `SendEmailEvent` |

Never route commands and events through the same exchange.

---

## Queues and Dead Letter Topology

Each service that consumes messages must declare:

| Queue | Purpose |
|---|---|
| `{service}.commands` | Async commands consumed by this service |
| `{service}.events` | Domain events consumed by this service |
| `{service}.commands.dead` | Failed commands after max retries |
| `{service}.events.dead` | Failed events after max retries |

Separate dead letter queues per type allow targeted monitoring and reprocessing.

---

## Retry and Dead Letter Configuration

- **Max retries:** 3
- **Retry delay:** 5 minutes (300,000 ms), constant (multiplier: 1)
- **After max retries:** message moved to the dead letter transport
- **Dead letter queues are NOT retried automatically**
- **`failure_transport` precedence — transport-level wins over framework-level.** Symfony Messenger lets you declare a global `framework.messenger.failure_transport: events_dead` AND a per-transport `transports.<name>.failure_transport: <name>_dead`. The per-transport setting **fully overrides** the global one for that transport — they do not stack. A service that mixes the two (e.g. global `events_dead` + per-transport `dispatch_dead` on a new `async_dispatch`) is correct, but visually surprising; add an inline YAML comment when introducing a per-transport override so the next reader does not assume both DLQs receive a copy of the failure.

```yaml
framework:
    messenger:
        default_bus: command.bus
        failure_transport: events_dead

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

## Cross-Service Message Contracts

When two services exchange a message:

1. Both must define the same class under the exact same FQCN: `App\Infrastructure\Messenger\Message\{MessageName}.php`
2. Both definitions must be byte-for-byte identical in constructor signature, property types, and `@param` PHPDoc
3. Any change to the constructor is a breaking change — must be coordinated
4. The `messageName()` return value must also match exactly

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

## Consumer Worker Services

Services that only consume messages (no HTTP layer):

**Dockerfile:**

```dockerfile
FROM php:8.5-cli   # NOT php-fpm — no HTTP server needed

# No pdo_pgsql, no pgsql if no database
# Install amqp extension for RabbitMQ
RUN pecl install amqp && docker-php-ext-enable amqp

# Clear Symfony cache on start — prevents stale compiled cache from volume mounts
CMD ["sh", "-c", "php bin/console cache:clear --no-warmup && php bin/console messenger:consume async_events --no-debug --time-limit=3600"]
```

**Why `cache:clear`:** dev volume mounts can leave stale compiled config from a previous image, causing silent failures.

**Why `--no-debug`:** in `APP_ENV=dev`, Symfony wraps the event dispatcher with `TraceableEventDispatcher`, which crashes `messenger:consume` on `WorkerRunningEvent`.

**Why `--time-limit=3600`:** prevents memory leaks. Container `restart: unless-stopped` restarts automatically.

**`docker-compose.yml`** (inside the service directory, e.g. `notification-service/docker-compose.yml`):

```yaml
services:
  notification-service:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: notification-service
    restart: unless-stopped   # REQUIRED — auto-restart after --time-limit
    volumes:
      - .:/var/www/html
    env_file:
      - .env
    networks:
      - workspace-network

networks:
  workspace-network:
    external: true
```

No Nginx companion container — worker services have no HTTP interface.
The service connects to RabbitMQ and Mailpit via `workspace-network` (started by the root infrastructure compose).

---

## PHPUnit Configuration

```xml
<phpunit bootstrap="tests/bootstrap.php" cacheDirectory=".phpunit.cache"
         colors="true" failOnDeprecation="true" failOnNotice="true" failOnWarning="true">
    <php>
        <ini name="display_errors" value="1" />
        <ini name="error_reporting" value="-1" />
        <env name="APP_ENV" value="test" force="true" />
        <env name="KERNEL_CLASS" value="App\Kernel" force="true" />
        <!-- DATABASE_URL: the value below is the LOCAL Docker default (consumed when
             no env var is set, e.g. inside `docker compose exec`). CI must NOT
             inherit this value — it points to the Docker compose service hostname,
             unreachable on a plain GitHub Actions runner. CI exports its own
             DATABASE_URL via the workflow `env:` block pointing at its postgres
             service container. Do NOT add `force="true"` here, or CI will resolve
             a hostname that does not exist (`could not translate host name`). -->
        <env name="DATABASE_URL" value="postgresql://workspace:workspace@trades-postgres:5432/{service}_test?serverVersion=18" />
        <!-- Async transport ALWAYS in-memory in tests — `force="true"` is correct
             here because we want tests to ignore whatever runtime is configured. -->
        <env name="MESSENGER_TRANSPORT_DSN" value="in-memory://" force="true" />
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

Two rules that catch teams every time:

- Use `<env>` tags, not `<server>` — `<server>` does not work reliably in Docker containers.
- **Never add `force="true"` to `DATABASE_URL` (or any value that legitimately differs between local Docker and CI).** The Docker service hostname (`trades-postgres`, `postgres`, `db`, ...) does not resolve on a GitHub Actions runner. CI workflows already export `DATABASE_URL` via the `env:` block pointing at the runner's `services.postgres` container on `localhost:5432` — `force="true"` would overwrite that and the integration suite would fail with `could not translate host name`. Keep the `force="true"` only on values that are correct EVERYWHERE (e.g. `APP_ENV=test`, `MESSENGER_TRANSPORT_DSN=in-memory://`).

### `tests/bootstrap.php`

```php
<?php

declare(strict_types=1);

use Symfony\Component\Dotenv\Dotenv;

require dirname(__DIR__).'/vendor/autoload.php';

// Skip bootEnv when no .env file is present (CI passes env vars directly via the
// workflow `env:` block; Symfony Dotenv would throw `PathException` otherwise
// because .env is gitignored per the secrets policy — only .env.example is
// committed). Locally, .env exists and is loaded normally.
if (file_exists(dirname(__DIR__).'/.env')) {
    (new Dotenv())->bootEnv(dirname(__DIR__).'/.env');
}
```

The `file_exists` guard is mandatory. Without it CI fails before the first test runs:

```
Error in bootstrap script: Symfony\Component\Dotenv\Exception\PathException:
Unable to read the "/home/runner/work/{service}/{service}/.env" environment file.
```

This is a recurring trap — every service that copies `bootstrap.php` from another scaffold inherits the bug. Always copy the version with the guard.

---

## Integration Test Example

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

---

## Testing Async Messages

In `when@test`, all async transports must be `in-memory://`:

```yaml
when@test:
    framework:
        messenger:
            transports:
                async_events: 'in-memory://'
                email: 'in-memory://'
                events_dead: 'in-memory://'
```

Assert dispatched messages:

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

## Unit Test Example

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

---

## Composer Recipes Cleanup

When running `composer require` or `composer update`, Symfony Flex may append recipe boilerplate to `.env` and create config files.

**Always review and clean up after adding dependencies:**
- Remove any auto-appended blocks from `.env` that duplicate or conflict with existing variables
- Remove or simplify generated config files that reference env vars not needed by this service
- Never leave `composer.json` and `composer.lock` out of sync — the Docker build will fail
