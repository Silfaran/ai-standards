---
name: messenger-logging-middleware
description: Use when wiring the LoggingMiddleware to Symfony Messenger buses, configuring Monolog for structured JSON logs, adding a new Messenger bus that needs logging, or tightening the redaction list for sensitive payload fields.
paths: "**/LoggingMiddleware.php, **/config/packages/monolog.yaml, **/config/packages/messenger.yaml"
---

# Structured logging for Symfony Messenger

Every command, event, and cross-service message bus must be wrapped by `LoggingMiddleware`. Query buses must NOT — queries are read-only and their failures surface to the caller. Logs go to stdout as JSON; shipping is an infrastructure concern.

## The non-negotiable rules

1. Logs are **structured JSON**, never plain text.
2. Output to **stdout** — the container runtime handles the rest.
3. Every write-side bus (`command.bus`, `event.bus`, `message.bus`) has the middleware; `query.bus` does not.
4. Sensitive payload fields are **always** redacted — never add exceptions without explicit approval.
5. Successful message handling is **NOT** logged (costs money, adds noise).

## Copying the middleware

Copy from [`ai-standards/scaffolds/LoggingMiddleware.php`](../../../scaffolds/LoggingMiddleware.php) to `src/Infrastructure/Messenger/Middleware/LoggingMiddleware.php`. Do not rewrite from memory.

Behavior guaranteed by the scaffold:

- Rethrows after logging — never swallows the exception.
- `get_object_vars()` accesses only public properties — private state stays out of logs.
- Non-scalar values are represented as their type, keeping logs scannable.

## Wiring to buses

```yaml
# config/packages/messenger.yaml
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
                middleware: []       # NO logging — queries are read-only
```

Adding a new bus? The middleware **must** be included (unless it's a new query bus). This is part of the Definition of Done for any feature that introduces a new bus.

## Monolog configuration — JSON to stdout

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

Tests produce no log output — otherwise the PHPUnit output becomes unreadable.

## Log schema — required fields

Every error log entry from the middleware contains:

| Field | Type | Source |
|---|---|---|
| `message_name` | string | Result of `messageName()` |
| `message_class` | string | FQCN of the message |
| `bus` | string | `command.bus`, `event.bus`, `message.bus` |
| `payload` | object | Public properties — sensitive fields redacted |
| `error.class` | string | Exception class |
| `error.message` | string | Exception message |
| `error.file` | string | File path where it was thrown |
| `error.line` | int | Line number |
| `error.trace` | string | Full stack trace |

Example entry:

```json
{
  "datetime": "2026-04-10T14:35:22.000000+00:00",
  "level": "ERROR",
  "channel": "messenger",
  "message": "Message handling failed",
  "context": {
    "message_name": "login_service.command.register_user",
    "bus": "command.bus",
    "payload": {
      "email": "john@example.com",
      "password": "[REDACTED]"
    },
    "error": { "class": "...", "message": "...", "file": "...", "line": 42, "trace": "..." }
  }
}
```

## Redacted fields — never log these in clear

```php
private const SENSITIVE_FIELDS = [
    'password', 'password_hash', 'hashed_password',
    'token', 'access_token', 'refresh_token',
    'secret', 'api_key', 'credential', 'card_number',
];
```

When in doubt, redact. Adding a field to the **exception** list (things that should not be redacted) requires explicit developer approval.

## Log levels

| Situation | Level |
|---|---|
| Message handled successfully | **Do not log** — noise |
| Handler threw a domain exception | `ERROR` |
| Handler threw an unexpected exception | `ERROR` |
| Message sent to dead-letter queue | `CRITICAL` |
| Worker started / stopped | `INFO` (entrypoint, not middleware) |

## What NOT to log (ever)

- Successful message handling.
- Sensitive fields (see list above).
- Internal IPs or hostnames.
- Full HTTP request/response bodies — log the command/event payload, not the HTTP envelope.
- Query bus results.

## Shipping is infrastructure, not code

Logs go to stdout as JSON. Everything else — Elasticsearch, Datadog, Loki, CloudWatch — is wired at the Docker / infra level (Filebeat, Datadog Agent, Promtail, AWS log driver). No application code changes when the destination changes.

## See also

- [standards/logging.md](../../../standards/logging.md) — authoritative version with full schema.
- [scaffolds/LoggingMiddleware.php](../../../scaffolds/LoggingMiddleware.php) — the scaffold to copy.
- `symfony-messenger-async` skill — bus setup this middleware plugs into.
