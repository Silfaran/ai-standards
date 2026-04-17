---
name: cors-nelmio-configuration
description: Use when configuring NelmioCorsBundle, editing nelmio_cors.yaml, adding a new frontend origin to a backend, or debugging CORS preflight failures (missing Access-Control-Allow-Origin, failed OPTIONS request, silent network errors from the browser) in a Symfony service.
paths: "**/nelmio_cors.yaml, **/config/packages/nelmio_cors.yaml"
---

# CORS with NelmioCorsBundle — the silent failure

NelmioCorsBundle has two recurring gotchas that cause CORS to fail silently — no useful error, just a generic network failure in the browser. Get both right every time.

## Gotcha #1 — `paths` overrides `defaults`, it does not merge

When a request matches an entry under `paths`, NelmioCorsBundle uses **only** the fields declared there. It does **not** merge with `defaults`. If `paths` only declares `allow_origin`, the response will have no `allow_methods`, no `allow_headers`, and no `Access-Control-Allow-Origin` for non-GET methods.

**Rule:** duplicate every field from `defaults` into each entry under `paths`.

```yaml
# WRONG — paths overrides defaults, allow_methods/allow_headers end up empty
nelmio_cors:
    defaults:
        allow_origin: ['%env(CORS_ALLOW_ORIGIN)%']
        allow_methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS']
        allow_headers: ['Content-Type', 'Authorization']
        allow_credentials: true
        max_age: 3600
    paths:
        '^/api/':
            allow_origin: ['%env(CORS_ALLOW_ORIGIN)%']

# CORRECT — paths duplicates all fields
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
            allow_methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS']
            allow_headers: ['Content-Type', 'Authorization']
            allow_credentials: true
            max_age: 3600
```

## Gotcha #2 — `origin_regex` must be set in BOTH `defaults` and `paths`

When you need a regex origin (multiple frontends on different ports), `origin_regex: true` has to be present in **both** blocks. Setting it only in `defaults` is ignored once `paths` matches.

```yaml
nelmio_cors:
    defaults:
        origin_regex: true
        allow_origin: ['%env(CORS_ALLOW_ORIGIN)%']
        # ...
    paths:
        '^/':
            origin_regex: true          # required here too
            allow_origin: ['%env(CORS_ALLOW_ORIGIN)%']
            # ... plus the rest of the fields
```

In `.env` use a regex when multiple origins must be allowed:

```dotenv
CORS_ALLOW_ORIGIN=^http://localhost:(3001|3002)$
```

## Never use `*`

```yaml
allow_origin: ['*']   # Forbidden in this project
```

Always use explicit origins (or a regex), driven from an env var — see [security.md](../../../standards/security.md) for the full rule.

## Adding a new frontend origin — checklist

For every backend this new frontend calls:

1. Find `CORS_ALLOW_ORIGIN` in the backend `.env`.
2. Add the new origin. If there are multiple, switch to regex form: `^http://localhost:(3001|3002)$`.
3. Confirm `origin_regex: true` is present in both `defaults` and `paths` when using regex.
4. **Recreate the backend container** — `docker compose up -d <service>` from the service directory. `docker restart` does NOT re-read `.env`. If the restart-vs-up trap is the issue, see the `docker-env-reload` skill.
5. Verify: browser DevTools → Network → filter XHR/Fetch → look for the preflight `OPTIONS` request. Response must include `Access-Control-Allow-Origin` and `Access-Control-Allow-Methods`.

## Where the frontend port comes from

Use `workspace.md` as the source of truth for frontend ports. Never assume Vite's default 5173 — the dev server port is configured per project and listed in `workspace.md` under Service Ports.

## See also

- [standards/security.md](../../../standards/security.md) — full CORS section and security headers.
- [standards/new-service-checklist.md](../../../standards/new-service-checklist.md) items 11–12 — the same rules in checklist form.
