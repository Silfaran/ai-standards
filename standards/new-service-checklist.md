# New Service Scaffold Checklist

Every new PHP/Symfony service must pass this checklist **before the first commit**.
The single validation rule: `docker build .` (or `make build`) must succeed with exit code 0.

Use [`tech-stack.md`](tech-stack.md) for the authoritative minimum versions — do not pin to a minor here unless there is a specific reason.

These items were derived from real failures encountered when bootstrapping `task-service`.

---

## 1. `src/Kernel.php` exists

```php
<?php

declare(strict_types=1);

namespace App;

use Symfony\Bundle\FrameworkBundle\Kernel\MicroKernelTrait;
use Symfony\Component\HttpKernel\Kernel as BaseKernel;

class Kernel extends BaseKernel
{
    use MicroKernelTrait;
}
```

Without this file, `cache:clear` fails immediately with `Class "App\Kernel" not found`.

---

## 2. `config/bundles.php` — only enabled bundles have config

Never copy `bundles.php` from another service without verifying each bundle:

| If you enable this bundle | You must also have |
|---|---|
| `SecurityBundle` | `config/packages/security.yaml` + no unused `config/routes/security.yaml` |
| `LexikJWTAuthenticationBundle` | `config/packages/lexik_jwt_authentication.yaml` + JWT keys in `.env` |
| `FrameworkBundle` | `config/packages/framework.yaml` |
| `DoctrineBundle` | `config/packages/doctrine.yaml` |
| `NelmioCorsBundle` | `config/packages/nelmio_cors.yaml` |

If a bundle has no config file, remove it from `bundles.php`. Do not leave it enabled "for future use" — it will break the build.

---

## 3. `config/routes.yaml` — only reference existing directories

```yaml
# WRONG — src/Infrastructure/Http/ does not exist yet
controllers:
    resource:
        path: ../src/Infrastructure/Http/
        namespace: App\Infrastructure\Http
    type: attribute

# CORRECT — leave empty until controllers are implemented
# Routes will be added here when controllers are implemented
```

If the `Http/` directory does not exist, remove the reference. Symfony will throw a `FileNotFoundException` during `cache:clear`.

---

## 4. `config/routes/` — remove files for disabled bundles

If `SecurityBundle` is not in `bundles.php`, delete `config/routes/security.yaml`.
Each file in `config/routes/` that references a bundle service will crash if that bundle is not loaded.

---

## 5. `.env` — clean up Symfony Flex pollution

After `composer install` or `composer require`, Symfony Flex automatically appends blocks to `.env`.
**Always review and remove any block that does not apply to this service.**

Common pollution to remove:

```dotenv
# Remove if not using Doctrine as messenger transport
###> symfony/messenger ###
MESSENGER_TRANSPORT_DSN=doctrine://default?auto_setup=0
###< symfony/messenger ###

# Remove if this service has no HTTP routing with absolute URL generation
###> symfony/routing ###
DEFAULT_URI=http://localhost
###< symfony/routing ###
```

Every env var that survives this cleanup and matches a secret category (see [`secrets.md`](secrets.md) → "What counts as a secret") MUST:

- appear in `.env.example` with a placeholder value and a one-line category comment;
- get a row in the project's `secrets-manifest.md` (owner, category, environments, source, rotation);
- be loaded via a fail-fast helper in application code — no silent fallbacks.

A service that boots with a missing required secret is a deployment bug, not a soft warning.

---

## 6. `composer.json` + `composer.lock` must always be in sync

**Never edit `composer.json` manually** to add a package. The Docker build runs `composer install`,
which installs only what is in `composer.lock`. If a package is in `composer.json` but not in
`composer.lock`, the build fails with:

```
Your lock file does not contain a compatible set of packages.
```

Always use `composer require` (or run it via Docker if PHP is not installed locally):

```bash
docker run --rm \
  -v /path/to/service:/app \
  composer:2 require vendor/package:"version" \
  --no-interaction \
  --ignore-platform-req=ext-amqp
```

---

## 7. `symfony/serializer` must be in `composer.json` when using async messaging

If `messenger.yaml` uses `serializer: messenger.transport.symfony_serializer`, the `symfony/serializer`
package must be in `composer.json` and `composer.lock`. Without it, `cache:clear` fails with:

```
The service "messenger.transport.symfony_serializer" has a dependency on a non-existent service "serializer".
```

Required dependencies for async messaging (see `backend.md` — RabbitMQ & Messaging). Use caret (`^`) constraints as defined in [`tech-stack.md`](tech-stack.md) — never lock to a specific minor:
```json
"symfony/serializer": "^8.0",
"symfony/property-access": "^8.0"
```

---

## 8. Validate: `docker build .` must succeed before first commit

Run from the service root directory:

```bash
docker build --no-cache .
```

If it fails, fix the error before committing. A scaffold that does not build is broken by definition.

Also verify the service's own `docker-compose.yml` starts correctly:

```bash
# From the service directory (infrastructure must be running)
docker compose up -d
```

After validating locally, `make build` from the `ai-standards/` directory builds all services —
use this to confirm no cross-service issues.

---

## 9. Quality gates installed — before the first commit

Every service must ship with its quality gates wired from day one. See [quality-gates.md](quality-gates.md) for the authoritative rules and the `quality-gates-setup` skill for the install steps. Minimum:

- CI workflow at `.github/workflows/ci.yml` — copied from the matching template in `ai-standards/templates/ci/` with placeholders replaced.
- Pre-commit hook at `.git/hooks/pre-commit`, executable (`chmod +x`).
- Makefile quality targets appended from `ai-standards/templates/makefile/`.
- For frontend services: the `package.json` scripts required by the hook and CI (`lint`, `format:check`, `format`, `type-check`, `test`, `build`).

Verify:
```bash
make quality   # from the service directory — all checks pass locally
```

Do not commit a service that fails `make quality` or whose CI has not been installed.

---

## 10. `make up` does NOT rebuild images

`make up` = `docker compose up -d` — it starts **existing** containers.
If source files changed (e.g., a new `Kernel.php`), the running container still uses the old image.

| Command | What it does |
|---|---|
| `make build` | Rebuilds all images |
| `make up` | Starts containers (no rebuild) |
| `make update` | `make build` + `make up` |

Always run `make build` (or `make update`) after modifying `composer.json`, `Dockerfile`, or any file
that affects the Docker image build context.

---

## New Frontend Service — Integration Checklist

When adding a new frontend application that calls existing backend services, verify these before testing.

### 11. CORS — add the new origin to every backend this frontend calls

Every backend using NelmioCorsBundle has an allowlist of permitted origins. A new frontend at a new port or domain will receive silent CORS rejections — the app gets no useful error, only a generic network failure.

For each backend this frontend calls:

1. Find `CORS_ALLOW_ORIGIN` in the backend `.env`
2. Add the new origin — use a regex when multiple origins must be allowed:
   ```dotenv
   CORS_ALLOW_ORIGIN=^http://localhost:(3001|3002)$
   ```
3. Ensure `origin_regex: true` is set in `nelmio_cors.yaml` (both `defaults` and `paths` blocks)
4. Recreate the backend container to apply the change (see item 13)

To diagnose: open DevTools → Network, filter XHR/Fetch, look for a failed preflight (`OPTIONS`) request or a response missing the `Access-Control-Allow-Origin` header.

**Use `{project-docs}/workspace.md` as the source of truth for frontend ports** (resolve `{project-docs}` from `ai-standards/.workspace-config-path`) — never assume default framework ports (e.g. Vite's 5173). The actual dev server port is configured per project and listed there.

---

### 12. NelmioCorsBundle `paths` must duplicate full config — not just `allow_origin`


NelmioCorsBundle's `paths` section **overrides** `defaults` entirely when a path matches — it does NOT merge with defaults. If the `paths` block only specifies `allow_origin`, the matched request will have no `allow_methods`, no `allow_headers`, and the `Access-Control-Allow-Origin` header will be missing.

```yaml
# WRONG — paths overrides defaults, so allow_methods/allow_headers are empty
nelmio_cors:
    defaults:
        allow_origin: ['%env(CORS_ALLOW_ORIGIN)%']
        allow_methods: ['GET', 'OPTIONS']
        allow_headers: ['Content-Type', 'Authorization']
    paths:
        '^/':
            allow_origin: ['%env(CORS_ALLOW_ORIGIN)%']

# CORRECT — paths duplicates all config
nelmio_cors:
    defaults:
        allow_origin: ['%env(CORS_ALLOW_ORIGIN)%']
        allow_methods: ['GET', 'OPTIONS']
        allow_headers: ['Content-Type', 'Authorization']
        allow_credentials: true
        max_age: 3600
    paths:
        '^/':
            allow_origin: ['%env(CORS_ALLOW_ORIGIN)%']
            allow_methods: ['GET', 'OPTIONS']
            allow_headers: ['Content-Type', 'Authorization']
            allow_credentials: true
            max_age: 3600
```

---

### 13. Docker env var changes require container recreation, not restart

`docker restart <service>` restarts the existing container with its **original** environment. It does NOT re-read `.env` files or `env_file` entries from `docker-compose.yml`.

| Command | Re-reads env_file / .env |
|---|---|
| `docker restart <service>` | No |
| `docker compose up -d <service>` | Yes (recreates the container) |

**Always use `docker compose up -d`** from the service directory after changing any `.env` file or environment variable referenced in its `docker-compose.yml`.

Verify the change was applied:

```bash
docker exec <service> printenv VARIABLE_NAME
```
