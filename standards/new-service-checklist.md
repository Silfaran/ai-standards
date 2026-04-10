# New Service Scaffold Checklist

Every new PHP/Symfony service must pass this checklist **before the first commit**.
The single validation rule: `docker build .` (or `make build`) must succeed with exit code 0.

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

Required dependencies for async messaging (see `backend.md` — RabbitMQ & Messaging):
```json
"symfony/serializer": "8.0.*",
"symfony/property-access": "8.0.*"
```

---

## 8. Validate: `docker build .` must succeed before first commit

Run from the service root directory:

```bash
docker build --no-cache .
```

If it fails, fix the error before committing. A scaffold that does not build is broken by definition.

After validating locally, `make build` from the `ai-standards/` directory builds all services together —
use this to confirm no cross-service issues.

---

## 9. `make up` does NOT rebuild images

`make up` = `docker compose up -d` — it starts **existing** containers.
If source files changed (e.g., a new `Kernel.php`), the running container still uses the old image.

| Command | What it does |
|---|---|
| `make build` | Rebuilds all images |
| `make up` | Starts containers (no rebuild) |
| `make update` | `make build` + `make up` |

Always run `make build` (or `make update`) after modifying `composer.json`, `Dockerfile`, or any file
that affects the Docker image build context.
