# Security Standards

## Philosophy

- Validate at the boundary, trust internally — inputs are validated at controllers and API entry points, not repeated in every layer
- Defense in depth — multiple layers of protection, never rely on a single control
- Least privilege — each service only has access to the resources it needs
- Fail closed — when in doubt, deny access and return a generic error
- Never leak internal details — stack traces, file paths, and SQL errors are never returned to the client

---

## Backend Security

### HTTP Response Headers

Every backend service must include these headers on all responses. Copy the subscriber from `ai-standards/scaffolds/SecurityHeadersSubscriber.php` to `src/Infrastructure/Http/EventSubscriber/SecurityHeadersSubscriber.php`.

| Header | Value | Why |
|---|---|---|
| `X-Content-Type-Options` | `nosniff` | Prevents MIME type sniffing attacks |
| `X-Frame-Options` | `DENY` | Prevents clickjacking via iframes |
| `X-XSS-Protection` | `0` | Disable legacy XSS filter (causes more harm than good in modern browsers) |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Limits referrer leakage |
| `Permissions-Policy` | `camera=(), microphone=(), geolocation=()` | Disables browser APIs the app doesn't need |

**Content-Security-Policy (CSP):** add only in production, via reverse proxy or dedicated middleware. CSP is complex and must be tailored per frontend — do not hardcode it in the backend.

---

### CORS Configuration

Use NelmioCorsBundle with explicit origins. **Never use `*` for `allow_origin`.**

```yaml
# config/packages/nelmio_cors.yaml
nelmio_cors:
    defaults:
        origin_regex: false
        allow_origin: ['%env(CORS_ALLOW_ORIGIN)%']
        allow_methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS']
        allow_headers: ['Content-Type', 'Authorization']
        allow_credentials: true
        max_age: 3600
    paths:
        '^/api/':
            origin_regex: false
            allow_origin: ['%env(CORS_ALLOW_ORIGIN)%']
```

In `.env`:
```
CORS_ALLOW_ORIGIN=http://localhost:5173
```

---

### Input Validation

There are **two distinct validation layers** — they are not the same and must not be mixed:

| Layer | Where | What it validates | Failure response |
|---|---|---|---|
| **Structural** | Controller (Infrastructure) | JSON valid? Fields present? Correct PHP types? | `400` / `422` |
| **Business** | Value Objects / Domain | Password strong enough? Email format valid? | Domain exception → `422` |

The controller acts as a **type guard** — it ensures the domain never receives `null` where it expects a `string`. The domain enforces business rules through Value Objects.

```php
public function __invoke(Request $request): JsonResponse
{
    // 1. STRUCTURAL VALIDATION — controller responsibility
    $data = json_decode($request->getContent(), true);

    if (!is_array($data)) {
        return new JsonResponse(['error' => 'Invalid JSON'], 400);
    }

    $firstName = $data['first_name'] ?? null;
    $email     = $data['email'] ?? null;
    $password  = $data['password'] ?? null;

    if (!is_string($firstName) || !is_string($email) || !is_string($password)) {
        return new JsonResponse(['error' => 'Missing required fields'], 422);
    }

    // 2. BUSINESS VALIDATION — happens inside the command handler via Value Objects
    //    e.g. Password::fromPlainText() throws InvalidPasswordException if rules fail
    //    e.g. Email::fromString() throws InvalidEmailException if format is wrong
    $command = new RegisterUserCommand($firstName, $email, $password);
    $this->commandBus->dispatch($command);

    return new JsonResponse(null, 201);
}
```

#### Controller rules

- Never trust `$request->getContent()` — always check type and presence
- Use `is_string()`, `is_int()`, `is_array()` — never assume types from the request
- Return `400` for malformed JSON, `422` for missing or wrong-type fields
- Never pass raw request data to a command constructor without checking types first
- **Trim** string inputs when appropriate (names, emails) — do it here, not in the domain
- **Never trim** passwords — whitespace is valid in passwords

#### Domain rules

- Business invariants live in **Value Objects** — not in controllers, not in handlers
- Use `webmozart/assert` inside Value Objects for precondition checks
- Domain exceptions are caught by the controller and mapped to HTTP responses

---

### Rate Limiting

Use Symfony RateLimiter on authentication endpoints:

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
```

Apply in the controller:

```php
public function __construct(
    private readonly MessageBusInterface $commandBus,
    private readonly RateLimiterFactory $loginLimiter,
) {}

public function __invoke(Request $request): JsonResponse
{
    $limiter = $this->loginLimiter->create($request->getClientIp() ?? 'unknown');

    if (!$limiter->consume()->isAccepted()) {
        return new JsonResponse(['error' => 'Too many attempts. Please try again later.'], 429);
    }

    // ... proceed with login
}
```

#### Which endpoints need rate limiting

| Endpoint | Limit | Why |
|---|---|---|
| `POST /api/login` | 5/min per IP | Prevent brute force |
| `POST /api/register` | 3/min per IP | Prevent mass account creation |
| `POST /api/password/reset` | 3/5min per IP | Prevent email spam |
| `POST /api/token/refresh` | 10/min per IP | Prevent token cycling abuse |

Public read endpoints (`GET`) generally do not need rate limiting in early stages. Add it when abuse is observed.

---

### JWT Security

| Setting | Value | Why |
|---|---|---|
| Access token lifetime | 15 minutes | Short window limits damage from stolen tokens |
| Refresh token lifetime | 7 days | Reasonable session length |
| Refresh token storage | `httpOnly` cookie | Not accessible from JavaScript — prevents XSS theft |
| Algorithm | RS256 | Asymmetric — only the backend can sign, anyone can verify |

#### Rules

- Access tokens are **stateless** — the backend never stores them
- Refresh tokens are **stored in the database** — can be revoked individually
- On logout, **delete the refresh token** from the database and clear the cookie
- Never include sensitive data in the JWT payload — only `user_id`, `roles`, `exp`
- Rotate refresh tokens on each use — issue a new refresh token when the old one is used

---

### Error Responses

Never expose internal details in API error responses:

```php
// WRONG — leaks internals
return new JsonResponse([
    'error' => 'SQLSTATE[23505]: Unique violation: 7 ERROR: duplicate key value...',
    'file' => '/var/www/html/src/Infrastructure/Persistence/DbalUserRepository.php',
    'trace' => '...',
], 500);

// CORRECT — generic message, log the details internally
return new JsonResponse([
    'error' => 'An unexpected error occurred.',
], 500);
```

#### HTTP status codes to use

| Situation | Code | Response body |
|---|---|---|
| Success with body | 200 | `{ data }` |
| Created | 201 | `null` or `{ id }` |
| No content (delete, logout) | 204 | empty |
| Malformed request body | 400 | `{ "error": "Invalid JSON" }` |
| Not authenticated | 401 | `{ "error": "Unauthorized" }` |
| Forbidden (wrong role) | 403 | `{ "error": "Forbidden" }` |
| Not found | 404 | `{ "error": "Resource not found" }` |
| Business conflict (duplicate) | 409 | `{ "error": "Email already registered" }` |
| Validation failed | 422 | `{ "error": "Validation failed", "details": [...] }` |
| Rate limited | 429 | `{ "error": "Too many attempts" }` |
| Server error | 500 | `{ "error": "An unexpected error occurred" }` |

---

### SQL Injection Prevention

DBAL parameterized queries are mandatory. The existing standard (Doctrine DBAL) handles this:

```php
// CORRECT — parameterized
$this->connection->fetchOne(
    'SELECT COUNT(*) FROM users WHERE email = ?',
    [$email],
);

// WRONG — string concatenation
$this->connection->fetchOne(
    "SELECT COUNT(*) FROM users WHERE email = '$email'",
);
```

**Never use string concatenation or interpolation in SQL queries.** DBAL parameterized queries are the only allowed method.

---

### Dependency Auditing

Run `composer audit` regularly. Add it to CI:

```yaml
# In CI pipeline
composer audit --no-dev
```

Flag any vulnerability with severity `high` or `critical` as a blocker.

---

## Frontend Security

### Environment Variables

**Every `VITE_*` variable is bundled into the JavaScript and visible to anyone.** Never put secrets in `VITE_*` variables.

| Safe to put in `VITE_*` | Never put in `VITE_*` |
|---|---|
| API base URL | API keys |
| Allowed redirect origins | Secret tokens |
| Feature flags (public) | Database URLs |
| App version | Private keys |

### XSS Prevention

Vue 3 escapes all template interpolation (`{{ }}`) by default. The main risk is `v-html`:

```vue
<!-- SAFE — Vue escapes this automatically -->
<p>{{ userInput }}</p>

<!-- DANGEROUS — renders raw HTML, XSS risk -->
<p v-html="userInput"></p>
```

#### Rules

- **Never use `v-html` with user-provided content** — only with trusted, developer-written HTML
- If you must render rich text, sanitize it with a library like `DOMPurify` before passing to `v-html`
- Never use `innerHTML` directly in composables or services
- `@click` handlers on Vue components are safe — Vue's event system doesn't execute injected scripts

### Authentication Token Storage

Token storage is unified across every frontend (auth and consumer) — see ADR-001:

- **Access token:** memory only (Pinia `ref<string|null>`). Never written to `localStorage` or `sessionStorage`.
- **Refresh token:** `httpOnly` secure cookie issued by the auth service. Never readable from JavaScript.
- **Session bootstrap:** every frontend calls `POST /api/token/refresh` from `AuthStore.initialize()` before mounting the app. If the cookie is valid, the new access token is loaded into memory. If not, the user sees the login form (auth frontend) or is redirected to the auth frontend (consumer frontends).

| Storage method | XSS risk | CSRF risk | Notes |
|---|---|---|---|
| `localStorage` | Vulnerable (JS can read it) | Immune | **Forbidden** for access tokens |
| Memory (`ref`) | Contains blast radius — lost on reload, recovered via refresh cookie | Immune | Canonical |
| `httpOnly` cookie | Immune | Needs CSRF protection | Used for the refresh token only |

**Mitigations:**
- Access token TTL is short (15 min) so a leaked token's damage window is bounded.
- Refresh token is invisible to JavaScript, so XSS cannot steal it.
- All frontends follow the same pattern — there is no auth-frontend exception. A reviewer who sees `localStorage.setItem('access_token', ...)` anywhere in the diff must reject it.

### Redirect Validation

Always validate redirect URLs against an allowlist before navigating:

```ts
function isAllowedRedirect(url: string): boolean {
  const allowed = (import.meta.env.VITE_ALLOWED_REDIRECT_ORIGINS ?? '')
    .split(',')
    .map((o: string) => o.trim())
    .filter(Boolean)

  try {
    const { origin } = new URL(url)
    return allowed.includes(origin)
  } catch {
    return false
  }
}
```

**Never redirect to a URL from query parameters without validating the origin.** Open redirect is an OWASP Top 10 vulnerability.

### Dependency Auditing

Run `npm audit` regularly. Add it to CI:

```bash
npm audit --omit=dev
```

Flag any vulnerability with severity `high` or `critical` as a blocker.

---

## Shared Rules (Backend + Frontend)

1. **Never log sensitive data** — passwords, tokens, API keys, card numbers (see `logging.md` for the redaction list)
2. **Never commit secrets to git** — `.env` files are in `.gitignore`. Use `.env.example` for documentation
3. **All communication over HTTPS in production** — HTTP is only acceptable in local development
4. **Never disable SSL verification** — not even in tests or staging
5. **Principle of least privilege** — database users should only have the permissions they need (no `SUPERUSER`)
6. **Keep dependencies updated** — run `composer audit` and `npm audit` in CI pipelines
