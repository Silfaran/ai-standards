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
| Backend runtime | PHP | 8.4 | Strict types, property hooks, asymmetric visibility. PHP 8.5 is welcome — verify PHP CS Fixer + PHPStan compatibility first (historically a 1–3 month lag after a new PHP minor) |
| Backend framework | Symfony | 8.0 | MicroKernel, Messenger, Security. 7.4 LTS is an acceptable conservative alternative when starting a project that will not track 8.x rapid releases |
| Backend test | PHPUnit | 13.0 | `readonly class` + `createMock()` compatibility — see backend.md §Services |
| Backend static | PHPStan | 2.0 | Level 9 across every service |
| Backend format | PHP CS Fixer | 3.90 | PSR-12 + custom rules. Verify compatibility when bumping PHP minor |
| Frontend runtime | Node.js | 22 LTS | Used for build tooling and dev server |
| Frontend framework | Vue | 3.5 | Composition API, `<script setup>` |
| Frontend language | TypeScript | 5.6 | `strict` mode enforced |
| Frontend bundler | Vite | 6.0 | |
| Frontend test | Vitest | 3.0 | jsdom env, `@vitest/coverage-v8` — see vitest-composable-test skill |
| Frontend CSS | Tailwind CSS | 4.0 | Via `@tailwindcss/vite` plugin. Oxide engine — config lives in `@theme` CSS, not `tailwind.config.js` |
| UI components | shadcn/ui (Vue) | latest | No pinned version — track upstream |
| Database | PostgreSQL | 17 | One database per service |
| Geo extension | PostGIS | 3.4 | Install when a service stores coordinates / does proximity search (`CREATE EXTENSION IF NOT EXISTS postgis;`). Ships as an extension to the PostgreSQL image — not a separate service |
| Messaging | RabbitMQ | 4.0 | Accessed via Symfony Messenger |
| Container runtime | Docker | 27 | Compose v2 required (`docker compose`, not `docker-compose`) |

### Optional per-project additions

These are NOT baseline — add them only when a project needs them, and only after the Postgres-first defaults have been validated insufficient. Picking a payment provider or a search engine before the feature exists is the most common form of speculative over-engineering in early-stage projects.

| Technology | When to add | Why not baseline |
|---|---|---|
| Stripe PHP SDK (`stripe/stripe-php`) | A project processes payments | Payment provider is a business/legal decision (fees, regulatory coverage, billing support) that is specific per project. Stripe is the default *recommendation* because of documentation quality and European coverage, not because it fits every case |
| Meilisearch or Elasticsearch | Postgres `tsvector` + `pg_trgm` has demonstrated real limitations on actual production data (>100k records, complex faceting, sub-100ms latency requirement) | External search doubles operational surface: another container, another data sync, another failure mode. Most projects never need it. See [Search strategy](#search-strategy) below |
| OpenTelemetry collector | Distributed tracing across services in production | The SDK is baseline (see `observability.md`); the collector is a deploy-time decision |

## Search strategy

Start every project with **PostgreSQL full-text search** (`tsvector` + `pg_trgm` for similarity). It handles:

- Tens of thousands of records with sub-100ms latency on properly indexed queries
- Prefix / similarity matching good enough for "typed incorrectly" tolerance
- Ranking (`ts_rank_cd`) sufficient for most product searches
- Zero operational overhead — already in the DB

**Move to an external search engine (Meilisearch first, Elasticsearch only if Meilisearch is outgrown) when** any of the following is true AND measured, not predicted:

- Production query p95 latency consistently > 200ms on tsvector after index tuning
- Faceted search with 5+ simultaneous filter dimensions is central to the UX
- Typo tolerance and "did you mean" ranking quality are core product differentiators
- Data volume has passed ~500k records with active growth

"We might need it later" is not a trigger. The migration path from Postgres FTS to Meilisearch is straightforward; the reverse is not. Err on the side of Postgres.

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
- When a service needs geo: use `postgis/postgis:17-3.4` image instead of `postgres:17` for that service's DB, or enable the extension in a migration (`CREATE EXTENSION IF NOT EXISTS postgis;`) when using the stock image

### Frontend tooling

- `{frontend-service}/package.json` — `vitest`, `@vitest/coverage-v8`, `tailwindcss`, `@tailwindcss/vite` versions
- `{frontend-service}/vite.config.ts` — `@tailwindcss/vite` plugin wiring
- `{frontend-service}/src/assets/main.css` — Tailwind 4 theme configuration via `@theme` block

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
   - Project-specific gotchas caused by the upgrade go to the project docs repo under `{project-name}-docs/lessons-learned/` (see path in `{project-docs}/workspace.md` `lessons-learned:` key; `{project-docs}` comes from `ai-standards/.workspace-config-path`). If a mistake recurs across projects, promote it to the matching standard/checklist in the same commit — do not keep a framework-level lessons-learned registry.
5. Commit the standards change and the per-service bumps together — never leave the workspace in a mixed-version state.

## Single Stack — Honest Limitation

This stack is opinionated. Switching to a different backend language or frontend framework requires rewriting the standards, scaffolds, and reference files. The orchestration patterns (agents, handoffs, spec-first) are portable; the implementation details here are not.
