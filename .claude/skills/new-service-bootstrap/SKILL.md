---
name: new-service-bootstrap
description: Use when scaffolding a new PHP/Symfony service from scratch — before the first `docker build`, before the first commit — or when diagnosing why a freshly-created service fails to boot. Covers Kernel.php, bundles.php, routes.yaml, Flex pollution, composer.lock sync, and the minimum validation bar.
paths: "**/src/Kernel.php, **/config/bundles.php, **/config/routes.yaml, **/composer.json"
---

# Bootstrapping a new PHP/Symfony service

Every new service must pass this checklist **before the first commit**. The single validation rule: `docker build .` must exit 0.

These items come from real failures encountered when bootstrapping `task-service`. Skipping any of them produces errors that look unrelated but trace back here.

## 1. `src/Kernel.php` must exist

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

Without it, `cache:clear` fails immediately with `Class "App\Kernel" not found`.

## 2. `config/bundles.php` — only enabled bundles have config

Never copy `bundles.php` from another service without checking each bundle:

| Bundle enabled | Must also have |
|---|---|
| `SecurityBundle` | `config/packages/security.yaml` + no stale `config/routes/security.yaml` |
| `LexikJWTAuthenticationBundle` | `config/packages/lexik_jwt_authentication.yaml` + JWT keys in `.env` |
| `FrameworkBundle` | `config/packages/framework.yaml` |
| `DoctrineBundle` | `config/packages/doctrine.yaml` |
| `NelmioCorsBundle` | `config/packages/nelmio_cors.yaml` |

If a bundle has no config file, remove it from `bundles.php`. Do not leave it enabled "for future use" — it breaks the build.

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

Symfony throws `FileNotFoundException` during `cache:clear` if the directory is missing.

## 4. `config/routes/` — remove files for disabled bundles

If `SecurityBundle` is not in `bundles.php`, delete `config/routes/security.yaml`. Each file in `config/routes/` that references a bundle service will crash if the bundle is not loaded.

## 5. `.env` — clean up Symfony Flex pollution after `composer install` / `composer require`

Flex appends blocks to `.env`. Review and remove anything that does not apply to this service.

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

## 6. `composer.json` + `composer.lock` must stay in sync

Never edit `composer.json` manually to add a package. The Docker build runs `composer install`, which installs only what is in `composer.lock`. Package in `composer.json` but missing from `composer.lock` = build fails with:

```
Your lock file does not contain a compatible set of packages.
```

Always use `composer require`. If PHP is not installed locally, use Docker:

```bash
docker run --rm \
  -v /path/to/service:/app \
  composer:2 require vendor/package:"^version" \
  --no-interaction \
  --ignore-platform-req=ext-amqp
```

## 7. Async messaging deps — `symfony/serializer` must be installed

If `messenger.yaml` uses `serializer: messenger.transport.symfony_serializer`, both packages must be in `composer.json` and `composer.lock`:

```json
"symfony/serializer": "^8.0",
"symfony/property-access": "^8.0"
```

Use caret (`^`) — not `8.0.*`. See [tech-stack.md](../../../standards/tech-stack.md) for the full version policy.

## 8. Validate with `docker build .`

```bash
docker build --no-cache .
```

If it fails, fix the error before committing. A scaffold that does not build is broken by definition.

Also verify the service's `docker-compose.yml` starts:

```bash
cd {service-directory}
docker compose up -d     # infrastructure must be running
```

And confirm no cross-service issues from the ai-standards root:

```bash
cd ai-standards
make build
```

## 9. `make up` does NOT rebuild images

| Command | Effect |
|---|---|
| `make build` | Rebuilds all images |
| `make up` | Starts existing containers only |
| `make update` | `make build` + `make up` |

Run `make build` (or `make update`) after modifying `composer.json`, `Dockerfile`, or any file in the Docker build context.

## See also

- [standards/new-service-checklist.md](../../../standards/new-service-checklist.md) — authoritative version with extended examples.
- [standards/tech-stack.md](../../../standards/tech-stack.md) — version constraints policy.
- `docker-env-reload` skill — related Docker trap.
