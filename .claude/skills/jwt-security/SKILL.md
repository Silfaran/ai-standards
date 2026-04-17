---
name: jwt-security
description: Use when implementing JWT authentication, refresh-token rotation, login/logout endpoints, Lexik JWT configuration, refresh-token storage and revocation, or deciding how the frontend should store the access token.
paths: "**/config/packages/lexik_jwt_authentication.yaml, **/config/packages/security.yaml, **/*RefreshToken*, **/LoginController.php, **/LogoutController.php"
---

# JWT lifecycle and storage

Short-lived access tokens, revocable refresh tokens, asymmetric signing. The only acceptable deviations from this are documented in `decisions.md` — ask before changing anything below.

## Lifetimes

| Setting | Value | Why |
|---|---|---|
| Access token lifetime | **15 minutes** | Short window limits damage from stolen tokens |
| Refresh token lifetime | **7 days** | Reasonable session length |
| Refresh token storage | **`httpOnly` cookie** | Not accessible from JavaScript — prevents XSS theft |
| Algorithm | **RS256** | Asymmetric — backend signs, anyone verifies with the public key |

## Rules

- Access tokens are **stateless** — the backend never stores them. If you find yourself writing an access-token table, stop.
- Refresh tokens **are** stored in the database — so they can be revoked individually.
- On logout: delete the refresh token from the database **and** clear the `httpOnly` cookie. Both, not one.
- **Rotate refresh tokens on every use** — issue a new refresh token when the old one is consumed. The old one is invalidated.
- Never put sensitive data in the JWT payload. Payload fields limited to: `user_id`, `roles`, `exp`. No email, no name, no tenant data.

## Frontend token storage — depends on the frontend's role

Not every frontend stores the access token the same way. Choose based on how the frontend gets the token.

| Frontend type | Access token storage | Why |
|---|---|---|
| Auth frontend (`login-front`, etc.) | `localStorage` | Receives the token directly from the login form. 15-min TTL limits the exposure window. |
| Consumer frontends (`task-front`, others) | Memory only (`ref`) | Recovers the token via `POST /api/token/refresh` on page load — never touches `localStorage`. |

| Storage | XSS risk | CSRF risk | Complexity |
|---|---|---|---|
| `localStorage` | Vulnerable (JS reads it) | Immune | Simple |
| Memory (`ref`) | Lost on reload → recovered via refresh cookie | Immune | Moderate |
| `httpOnly` cookie | Immune | Vulnerable (needs CSRF token) | Complex |

In all configurations, the **refresh** token lives in an `httpOnly` cookie. The access-token-in-memory pattern for consumer frontends relies on the refresh cookie to re-hydrate the session on page reload.

## Symfony configuration checklist

- `LexikJWTAuthenticationBundle` in `bundles.php` only when `config/packages/lexik_jwt_authentication.yaml` exists.
- JWT keys in `.env` (or better, passed in via `env_file`). Never commit keys.
- `security.yaml` firewall wired to the JWT authenticator.
- Refresh-token repository uses DBAL (no ORM), matching the project's persistence standard.

## Axios 401 → refresh → retry flow

On the frontend, the `setupInterceptors()` module intercepts 401s and silently refreshes. See the `vue-composable-mutation` skill and [frontend-reference.md](../../../standards/frontend-reference.md) for the full interceptor code. Key invariants:

- Use `_retry` flag on the request config to prevent an infinite refresh loop.
- Set `withCredentials: true` on the Axios instance so the refresh cookie is sent.
- On refresh failure → clear the access token and redirect to login via the auth store.

## Rate limiting on auth endpoints

JWT security is only as strong as the endpoints that issue tokens. Always rate-limit:

- `POST /api/login` — 5/min per IP.
- `POST /api/token/refresh` — 10/min per IP.
- `POST /api/password/reset` — 3/5min per IP.

See the `rate-limiting-auth` skill for the Symfony RateLimiter setup.

## Common mistakes that this skill exists to prevent

- Storing the refresh token in `localStorage` (immediately accessible to XSS → session takeover).
- Returning the refresh token in the JSON body instead of in a cookie (same failure mode).
- Omitting refresh-token rotation — one stolen token lasts 7 days.
- Putting `email` or `name` in the JWT payload. The payload is readable; anyone with the token sees these.
- Forgetting to delete the DB refresh-token row on logout — the cookie is cleared but the row is still valid.
- Rotating only the access token on refresh, reusing the same refresh token.

## See also

- [standards/security.md](../../../standards/security.md) — authoritative JWT section.
- [standards/frontend-reference.md](../../../standards/frontend-reference.md) — Axios interceptor implementation.
- `rate-limiting-auth` skill — rate-limit setup for the auth endpoints.
- `vue-composable-mutation` skill — frontend auth-store + token handling.
