---
name: rate-limiting-auth
description: Use when adding or adjusting Symfony RateLimiter on authentication endpoints (login, register, password reset, token refresh), or when diagnosing why an auth endpoint is being abused or brute-forced without protection.
paths: "**/config/packages/rate_limiter.yaml, **/LoginController.php, **/RegisterController.php, **/PasswordResetController.php, **/RefreshTokenController.php"
---

# Rate limiting authentication endpoints

Every auth endpoint is a brute-force target. Symfony's `RateLimiter` blocks abuse at the controller boundary — before the command bus, before the database. Add it by default on anything that issues or validates credentials.

## Which endpoints need rate limiting

| Endpoint | Limit | Reason |
|---|---|---|
| `POST /api/login` | **5/min per IP** | Prevent brute force on credentials |
| `POST /api/register` | **3/min per IP** | Prevent mass account creation |
| `POST /api/password/reset` | **3/5min per IP** | Prevent email spam and enumeration |
| `POST /api/token/refresh` | **10/min per IP** | Prevent token-cycling abuse |

Public read endpoints (`GET`) do not need rate limiting by default. Add it when abuse is observed.

## Configuration

```yaml
# config/packages/rate_limiter.yaml
framework:
    rate_limiter:
        login_attempts:
            policy: sliding_window
            limit: 5
            interval: '1 minute'

        register_attempts:
            policy: sliding_window
            limit: 3
            interval: '1 minute'

        password_reset_attempts:
            policy: sliding_window
            limit: 3
            interval: '5 minutes'

        token_refresh_attempts:
            policy: sliding_window
            limit: 10
            interval: '1 minute'
```

Use **sliding_window** — fixed windows can be bypassed by hitting the limit at the end of one window and again at the start of the next.

## Applying in a controller

```php
final class LoginController extends AppController
{
    public function __construct(
        private readonly MessageBusInterface $commandBus,
        private readonly RateLimiterFactory $loginLimiter,   // matches rate_limiter key
    ) {}

    #[Route('/api/login', methods: ['POST'])]
    public function __invoke(Request $request): JsonResponse
    {
        $limiter = $this->loginLimiter->create($request->getClientIp() ?? 'unknown');

        if (!$limiter->consume()->isAccepted()) {
            return new JsonResponse(['error' => 'Too many attempts. Please try again later.'], 429);
        }

        // ... proceed with login
    }
}
```

Return **HTTP 429** (`Too Many Requests`) with a generic message. Never reveal which limiter was hit or how many attempts remain in the error body.

## Wiring the limiter as a service argument

Symfony auto-generates factory services named `limiter.{key}`. Bind them by argument name in `services.yaml`:

```yaml
services:
    _defaults:
        bind:
            $loginLimiter: '@limiter.login_attempts'
            $registerLimiter: '@limiter.register_attempts'
            $passwordResetLimiter: '@limiter.password_reset_attempts'
            $tokenRefreshLimiter: '@limiter.token_refresh_attempts'
```

## Key identifier — what goes into `create()`

The argument passed to `$limiter->create($key)` identifies the bucket:

- For anonymous auth endpoints → `$request->getClientIp() ?? 'unknown'`.
- For authenticated actions → `$request->getClientIp() . ':' . $userId` to avoid one user's attempts exhausting a shared IP bucket.
- Never use raw user input as the key — that allows an attacker to rotate keys.

Behind a proxy/load balancer, configure `framework.trusted_proxies` so `getClientIp()` returns the real client IP.

## Storage

Default storage is an in-memory cache adapter, which does **not** survive process restarts and does **not** share state between multiple PHP-FPM workers. For real deployments, point the rate limiter to Redis:

```yaml
framework:
    rate_limiter:
        login_attempts:
            policy: sliding_window
            limit: 5
            interval: '1 minute'
            cache_pool: cache.redis_rate_limiter
```

With Redis, all FPM workers and all service replicas share the same counters. Without it, a distributed attacker can split attempts across workers and effectively 5x the limit.

## Never

- Never reset the limiter after a successful login. Successful auth does **not** clear the counter — that would let an attacker brute-force one password, validate with a known-good set, and reset.
- Never surface the remaining attempts to the client. Opaque failure is the goal.
- Never rate-limit reads (`GET /api/me`, `GET /api/tasks`) by default — this creates user-visible flakiness without a security benefit.

## See also

- [standards/security.md](../../../standards/security.md) — rate limiting table and full endpoint list.
- `jwt-security` skill — the reason `/api/token/refresh` exists and why its limit is higher.
