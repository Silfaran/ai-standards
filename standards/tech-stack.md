# Tech Stack

Single source of truth for technology choices and version requirements across the workspace.
Every other document (CLAUDE.md, README.md, agents, scaffolds) must reference this file instead of redefining versions.

## Versioning Policy

All versions listed here are **minimums**. Services are free — and encouraged — to run on newer patch and minor releases as long as they remain inside the same major line and all tests pass.

- **Minimum** means the floor: the listed version must build and run.
- **Open to update** means any newer compatible release is acceptable without changing the standards — bump the service and go.
- **Major version bumps** (e.g. PHP 8.x → 9.x, Symfony 8.x → 9.x) are **not** silent upgrades. They require updating this file first, followed by the checklist in [Upgrading a Major Version](#upgrading-a-major-version).

## Stack

| Layer | Technology | Minimum version | Notes |
|---|---|---|---|
| Backend runtime | PHP | 8.4 | Strict types, property hooks, asymmetric visibility |
| Backend framework | Symfony | 8.0 | MicroKernel, Messenger, Security |
| Frontend runtime | Node.js | 22 LTS | Used for build tooling and dev server |
| Frontend framework | Vue | 3.5 | Composition API, `<script setup>` |
| Frontend language | TypeScript | 5.6 | `strict` mode enforced |
| Frontend bundler | Vite | 6.0 | |
| UI components | shadcn/ui (Vue) | latest | No pinned version — track upstream |
| Database | PostgreSQL | 17 | One database per service |
| Messaging | RabbitMQ | 4.0 | Accessed via Symfony Messenger |
| Container runtime | Docker | 27 | Compose v2 required (`docker compose`, not `docker-compose`) |

## Architecture Patterns (non-versioned)

Enforced by standards, not suggested. Every agent validates against them:

- **Hexagonal Architecture** — Domain / Application / Infrastructure layering
- **DDD** — aggregates, value objects, domain events
- **CQRS** — commands and queries dispatched via separate buses
- **Event-Driven** — domain events published via Symfony Messenger

Details in [backend.md](backend.md) and [backend-reference.md](backend-reference.md).

## Where Versions Live in Code

When upgrading any component, these are the files to touch. Keep this list accurate — if you add a new place where a version is pinned, add it here.

### PHP / Symfony

- `{service}/Dockerfile` — `FROM php:X.Y-cli` or `php:X.Y-fpm`
- `{service}/composer.json` — `"require": { "php": "^8.4", "symfony/*": "^8.0" }`
- `ai-standards/standards/backend-reference.md` — example Dockerfiles and composer snippets
- `ai-standards/standards/new-service-checklist.md` — dependency examples for new services

### Node / Vue / Vite / TypeScript

- `{frontend-service}/Dockerfile` — `FROM node:XX-alpine`
- `{frontend-service}/package.json` — `"engines": { "node": ">=22" }`, plus `vue`, `vite`, `typescript` constraints
- `ai-standards/standards/frontend-reference.md` — example configs

### Database / Messaging / Infra

- `workspace/docker-compose.yml` (root shared infra) — `image: postgres:17`, `image: rabbitmq:4-management`
- `ai-standards/standards/new-service-checklist.md` — any version references

## Composer Constraint Convention

Use caret (`^`) constraints to express "minimum, open to update within the same major":

```json
{
  "require": {
    "php": "^8.4",
    "symfony/framework-bundle": "^8.0",
    "symfony/serializer": "^8.0",
    "symfony/property-access": "^8.0"
  }
}
```

Do **not** use wildcard major-minor locks like `"8.0.*"` — that pins the minor and blocks patch-compatible upgrades. Caret (`^8.0`) gives `>= 8.0.0, < 9.0.0`, which matches the policy.

## npm Constraint Convention

Use caret (`^`) for the same reason, and set `engines.node` to the minimum LTS:

```json
{
  "engines": { "node": ">=22" },
  "dependencies": {
    "vue": "^3.5.0",
    "vite": "^6.0.0",
    "typescript": "^5.6.0"
  }
}
```

## Upgrading a Major Version

1. Update the minimum version in the [Stack](#stack) table.
2. Update every file listed in [Where Versions Live in Code](#where-versions-live-in-code).
3. Run `make build && make test` at the workspace root — fix failures before committing.
4. If the upgrade introduces breaking changes (removed APIs, renamed classes), update:
   - [backend-reference.md](backend-reference.md) or [frontend-reference.md](frontend-reference.md) — code examples
   - [new-service-checklist.md](new-service-checklist.md) — if the failure modes change
   - Framework-level agent mistakes surfaced by the upgrade → add a one-liner to [`lessons-learned.md`](lessons-learned.md) (this file's neighbour). Project-specific gotchas caused by the upgrade go to the project docs repo under `{project-name}-docs/lessons-learned/` (see path in `{project-docs}/workspace.md` `lessons-learned:` key; `{project-docs}` comes from `ai-standards/.workspace-config-path`).
5. Commit the standards change and the per-service bumps together — never leave the workspace in a mixed-version state.

## Single Stack — Honest Limitation

This stack is opinionated. Switching to a different backend language or frontend framework requires rewriting the standards, scaffolds, and reference files. The orchestration patterns (agents, handoffs, spec-first) are portable; the implementation details here are not.
