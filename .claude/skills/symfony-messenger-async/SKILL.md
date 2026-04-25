---
name: symfony-messenger-async
description: Use when configuring Symfony Messenger buses (command/query/event/message), setting up RabbitMQ transports, defining domain events or async messages, writing a cross-service message contract, or scaffolding a consumer-only worker service.
paths: "**/config/packages/messenger.yaml, **/src/Infrastructure/Messenger/**, **/src/Application/Command/**, **/src/Application/Query/**"
---

# Symfony Messenger — buses, transports, retry, consumer workers

Async messaging in this project runs on Symfony Messenger + RabbitMQ + JSON serializer. These rules prevent the recurring failure modes: wrong bus routing, silent serializer crashes, duplicated message contracts, stuck dead-letter queues.

## When to use which bus

| Scenario | Bus |
|---|---|
| Write operation, same service | Sync `command.bus` |
| Read operation, same service | Sync `query.bus` |
| Domain event, other services react to it | Async via RabbitMQ (`event.bus`) |
| Cross-service application message (e.g. send email) | Async via RabbitMQ (`message.bus`) |
| Long-running background job | Async via RabbitMQ |

**Never mix domain events and cross-service commands on the same exchange.** Domain events are broadcast (fanout); application messages are directed (one producer, one consumer).

## Message interfaces — every message declares its name

```php
interface CommandInterface          { public function messageName(): string; }
interface QueryInterface            { public function messageName(): string; }
interface DomainEventInterface      { public function messageName(): string; }
interface ApplicationMessageInterface { public function messageName(): string; }
```

`messageName()` format: `{service_name}.{type}.{snake_case_action}`. Type is one of `command`, `query`, `event`, `message`.

Examples:

```
login_service.command.register_user
login_service.query.get_user_by_email
login_service.event.user_registered
login_service.message.send_email
task_service.event.task_assigned
```

## Bus configuration

```yaml
# config/packages/messenger.yaml
framework:
    messenger:
        default_bus: command.bus
        buses:
            command.bus: ~
            query.bus:
                middleware: []            # NO logging middleware — read-only
            event.bus:
                default_middleware:
                    enabled: true
                    allow_no_handlers: true
            message.bus:
                default_middleware:
                    enabled: true
                    allow_no_handlers: true
```

- `default_bus` **must** be set explicitly when multiple buses exist.
- `allow_no_handlers: true` on `event.bus` and `message.bus` so events can be dispatched without a local handler (the handler lives in another service).

## Handler registration — bus must be named

Autowiring alone is not enough. Tag each handler explicitly with the bus it belongs to:

```yaml
# services.yaml
App\Application\Handler\SendEmailHandler:
    tags:
        - { name: messenger.message_handler, bus: message.bus }
```

## RabbitMQ transport — required dependencies

Both packages must be in `composer.json` and `composer.lock`:

```json
"symfony/serializer": "^8.0",
"symfony/property-access": "^8.0"
```

Without them, `cache:clear` fails with `The service "messenger.transport.symfony_serializer" has a dependency on a non-existent service "serializer".`

All async transports **must** use the JSON serializer, not `PhpSerializer`:

```yaml
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
            delay: 300000       # 5 min, constant
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
```

## Exchanges, queues, dead letters

| Exchange | Type | Purpose |
|---|---|---|
| `events` | fanout | Domain events published by this service |
| `commands` | direct | Async commands between services (only if needed) |
| One per application message category | fanout | e.g. `emails` for `SendEmailEvent` |

| Queue | Purpose |
|---|---|
| `{service}.commands` | Async commands consumed |
| `{service}.events` | Domain events consumed |
| `{service}.commands.dead` | Failed commands after max retries |
| `{service}.events.dead` | Failed events after max retries |

Separate dead-letter queues per type allow targeted monitoring and reprocessing. Dead-letter queues are **NOT retried automatically**.

## Retry policy (default)

- Max retries: **3**
- Retry delay: **5 minutes** (300,000 ms), constant (`multiplier: 1`)
- After max retries → dead-letter transport
- `failure_transport: events_dead` in the messenger config

## Cross-service message contracts

When two services exchange a message:

1. Both define the class at the **same FQCN**: `App\Infrastructure\Messenger\Message\{MessageName}.php`.
2. The two files must be **byte-identical** in constructor signature, property types, and `@param` PHPDoc.
3. `messageName()` returns the same string on both sides.
4. Any change to the constructor is a breaking change — coordinate both services in the same release.

```php
// Both login-service/ and notification-service/ have IDENTICAL:
// src/Infrastructure/Messenger/Message/SendEmailEvent.php

final class SendEmailEvent implements ApplicationMessageInterface
{
    /** @param array<string, mixed> $variables */
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

## Consumer worker services (no HTTP layer)

**Dockerfile:**

```dockerfile
FROM php:8.5-cli   # NOT php-fpm — no HTTP server needed

RUN pecl install amqp && docker-php-ext-enable amqp

# cache:clear on start — dev volume mounts leave stale compiled config
# --no-debug — in APP_ENV=dev, TraceableEventDispatcher crashes messenger:consume on WorkerRunningEvent
# --time-limit=3600 — prevents memory leaks; restart: unless-stopped restarts the container
CMD ["sh", "-c", "php bin/console cache:clear --no-warmup && php bin/console messenger:consume async_events --no-debug --time-limit=3600"]
```

**docker-compose.yml** (service-level):

```yaml
services:
  notification-service:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: notification-service
    restart: unless-stopped      # REQUIRED — auto-restart after --time-limit
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

No Nginx sidecar — consumer workers have no HTTP interface.

## Tests — always use `in-memory://`

```yaml
when@test:
    framework:
        messenger:
            transports:
                async_events: 'in-memory://'
                email: 'in-memory://'
                events_dead: 'in-memory://'
```

If a test dispatches to a real RabbitMQ, the test suite becomes flaky and slow.

## See also

- [standards/backend.md](../../../standards/backend.md) — concise bus + handler rules.
- [standards/backend-reference.md](../../../standards/backend-reference.md) — full transport / exchange / queue reference with examples.
- `messenger-logging-middleware` skill — how to wire LoggingMiddleware to the new buses.
