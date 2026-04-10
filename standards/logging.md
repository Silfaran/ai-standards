# Logging Standards

## Philosophy

- Logs are **structured JSON** — never plain text strings
- Output to **stdout** — the container runtime captures and routes it (Docker, Kubernetes, etc.)
- Shipping to Elasticsearch, Datadog, Grafana Loki, or any other backend is an infrastructure concern — the application only writes to stdout
- Every command and event bus has a logging middleware — no exception handling is done in silence
- Query buses do **NOT** need logging middleware — they are read-only and failures surface to the caller

---

## Log Schema

Every log entry emitted from the Messenger bus middleware must contain these fields:

```json
{
  "datetime": "2026-04-10T14:35:22.000000+00:00",
  "level": "ERROR",
  "channel": "messenger",
  "message": "Message handling failed",
  "context": {
    "message_name": "login_service.command.register_user",
    "message_class": "App\\Application\\Command\\User\\RegisterUser\\RegisterUserCommand",
    "bus": "command.bus",
    "payload": {
      "email": "john@example.com",
      "first_name": "John",
      "password": "[REDACTED]"
    },
    "error": {
      "class": "App\\Domain\\Exception\\EmailAlreadyExistsException",
      "message": "Email john@example.com is already registered",
      "file": "/var/www/html/src/Application/Command/User/RegisterUser/RegisterUserCommandHandler.php",
      "line": 42,
      "trace": "..."
    }
  }
}
```

### Required fields

| Field | Type | Description |
|---|---|---|
| `message_name` | string | Result of `messageName()` or the FQCN if not implemented |
| `message_class` | string | Full PHP class name |
| `bus` | string | Bus name (`command.bus`, `event.bus`, `message.bus`) |
| `payload` | object | All public properties — sensitive fields redacted |
| `error.class` | string | Exception class |
| `error.message` | string | Exception message |
| `error.file` | string | File where exception was thrown |
| `error.line` | int | Line number |
| `error.trace` | string | Full stack trace |

### Sensitive field redaction

These field names are **always redacted** to `[REDACTED]`:

```php
private const SENSITIVE_FIELDS = [
    'password', 'password_hash', 'hashed_password',
    'token', 'access_token', 'refresh_token',
    'secret', 'api_key', 'credential', 'card_number',
];
```

**Never add exceptions to this list without explicit approval.** When in doubt, redact.

---

## LoggingMiddleware Implementation

One middleware class shared across all buses in each service:

```php
<?php

declare(strict_types=1);

namespace App\Infrastructure\Messenger\Middleware;

use Psr\Log\LoggerInterface;
use Symfony\Component\Messenger\Envelope;
use Symfony\Component\Messenger\Middleware\MiddlewareInterface;
use Symfony\Component\Messenger\Middleware\StackInterface;
use Symfony\Component\Messenger\Stamp\BusNameStamp;

final class LoggingMiddleware implements MiddlewareInterface
{
    private const SENSITIVE_FIELDS = [
        'password', 'password_hash', 'hashed_password',
        'token', 'access_token', 'refresh_token',
        'secret', 'api_key', 'credential', 'card_number',
    ];

    public function __construct(private readonly LoggerInterface $logger) {}

    public function handle(Envelope $envelope, StackInterface $stack): Envelope
    {
        $message = $envelope->getMessage();

        try {
            return $stack->next()->handle($envelope, $stack);
        } catch (\Throwable $e) {
            $this->logger->error('Message handling failed', [
                'message_name'  => $this->resolveMessageName($message),
                'message_class' => $message::class,
                'bus'           => $this->resolveBusName($envelope),
                'payload'       => $this->serializePayload($message),
                'error'         => [
                    'class'   => $e::class,
                    'message' => $e->getMessage(),
                    'file'    => $e->getFile(),
                    'line'    => $e->getLine(),
                    'trace'   => $e->getTraceAsString(),
                ],
            ]);

            throw $e;
        }
    }

    private function resolveMessageName(object $message): string
    {
        return method_exists($message, 'messageName')
            ? $message->messageName()
            : $message::class;
    }

    private function resolveBusName(Envelope $envelope): string
    {
        $stamp = $envelope->last(BusNameStamp::class);

        return $stamp instanceof BusNameStamp ? $stamp->getBusName() : 'unknown';
    }

    private function serializePayload(object $message): array
    {
        $payload = [];

        foreach (get_object_vars($message) as $key => $value) {
            if (in_array(strtolower($key), self::SENSITIVE_FIELDS, true)) {
                $payload[$key] = '[REDACTED]';
                continue;
            }

            $payload[$key] = match (true) {
                is_scalar($value) => $value,
                is_null($value)   => null,
                is_array($value)  => '[array]',
                is_object($value) => $value::class,
                default           => '[unknown]',
            };
        }

        return $payload;
    }
}
```

**Notes:**
- Rethrows the exception after logging — the middleware does **not** swallow errors
- `get_object_vars()` only accesses public properties — private properties are not logged
- Non-scalar values are represented as their type to keep logs scannable

---

## Wiring to Buses

In `config/packages/messenger.yaml`, add the middleware to **command, event, and message buses only**:

```yaml
framework:
    messenger:
        buses:
            command.bus:
                middleware:
                    - App\Infrastructure\Messenger\Middleware\LoggingMiddleware
            event.bus:
                middleware:
                    - App\Infrastructure\Messenger\Middleware\LoggingMiddleware
            message.bus:
                middleware:
                    - App\Infrastructure\Messenger\Middleware\LoggingMiddleware
            query.bus:
                # NO logging middleware — queries are read-only
                middleware: []
```

If a new bus is added, the middleware **must** be included — this is part of the Definition of Done for any feature that introduces a new bus (except query buses).

---

## Monolog Configuration

Output structured JSON to stdout:

```yaml
# config/packages/monolog.yaml
monolog:
    channels:
        - messenger

    handlers:
        main:
            type:      stream
            path:      php://stdout
            level:     debug
            formatter: monolog.formatter.json
            channels:  ['!event']

        messenger:
            type:      stream
            path:      php://stdout
            level:     debug
            formatter: monolog.formatter.json
            channels:  [messenger]

when@test:
    monolog:
        handlers:
            main:
                type: null
            messenger:
                type: null
```

**Suppress logs in test environment** — tests should not produce log output.

---

## Log Levels

| Situation | Level |
|---|---|
| Message handled successfully | Do not log (noise) |
| Handler threw a domain exception | `ERROR` |
| Handler threw an unexpected exception | `ERROR` |
| Message sent to dead letter queue | `CRITICAL` |
| Worker started / stopped | `INFO` (worker entrypoint, not middleware) |

Do not log successful message handling — it creates noise and costs money in paid log services.

---

## Shipping to External Services

The application only writes JSON to stdout. Shipping is an infrastructure concern:

| Target | How |
|---|---|
| **Elasticsearch** | Filebeat reads Docker container logs and ships to ES |
| **Datadog** | Datadog Agent reads Docker logs and tags by container |
| **Grafana Loki** | Promtail reads Docker logs and sends to Loki |
| **CloudWatch** | AWS log driver on the container |

No application code changes are needed to switch between these — only Docker/infrastructure configuration.

---

## What NOT to Log

- Successful message handling (too much noise)
- Sensitive fields — always redact (see list above)
- Internal IP addresses or server hostnames
- Full HTTP request/response bodies — log the command/event payload, not the HTTP layer
- Query bus results
