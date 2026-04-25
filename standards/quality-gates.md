# Quality Gates

Deterministic enforcement of the rules that the reviewer agents check probabilistically.
Three layers: local (pre-commit), service-level (`make quality`), and CI (GitHub Actions). Each layer has a single job — fail fast when a rule is violated.

## Why three layers

| Layer | Who runs it | When | What it catches |
|---|---|---|---|
| Pre-commit hook | Developer machine | Every `git commit` | Formatter, linter, static analysis — on **staged files only** |
| `make quality` | Developer, CI | Before push / in CI job | Full suite across the service |
| GitHub Actions CI | GitHub | Every PR and push to `master` | Same as `make quality` but on a clean VM against real Postgres/RabbitMQ |

The pre-commit hook is a convenience to fail fast in ~3 seconds. CI is the authority — a commit that passes locally but fails CI is a bug in the hook, not in CI.

## The non-negotiable bar

A commit is "quality-gate-passing" when, for its service, **all** of the following succeed:

### Backend (PHP / Symfony)

- `composer validate --strict` — `composer.json` and `composer.lock` in sync.
- `vendor/bin/php-cs-fixer fix --dry-run --diff` — formatting matches project rules.
- `vendor/bin/phpstan analyse --memory-limit=1G` — **level 9**, no violations, no warnings downgraded.
- `php vendor/bin/phinx migrate --environment=default` against a clean Postgres — migrations apply cleanly.
- `vendor/bin/phpunit` — every unit and integration test passes.
- `composer audit --no-dev` — no `high` / `critical` advisories.

PHPStan level 9 is **non-negotiable**. Do not drop to level 8 "just for this PR". Do not add baselines to hide errors — fix them.

### Frontend (Vue 3 / Vite / TypeScript)

- `npm run lint` — ESLint, zero warnings (`--max-warnings=0`).
- `npm run format:check` — Prettier passes without diff.
- `npm run type-check` — `vue-tsc --noEmit`, strict mode, no `any`.
- `npm run test` — all Vitest tests pass.
- `npm run build` — Vite build completes (smoke check).
- `npm audit --omit=dev --audit-level=high` — no `high` / `critical` advisories.

TypeScript strict mode is enforced in `tsconfig.app.json`. Do not opt out with `skipLibCheck`, `// @ts-ignore`, or `as any`. Use `unknown` + type guards.

## Installing the gates in a service

The templates live in [`../templates/`](../templates/) in ai-standards. Install them per service — they are copied, not symlinked, so each service's git repo owns its own workflow.

### Backend service

```bash
# 1. CI
mkdir -p .github/workflows
cp ai-standards/templates/ci/backend-ci.yml.template .github/workflows/ci.yml
# Replace placeholders: {service-name}, {php-version}, {postgres-image}, {rabbitmq-image}

# 2. Pre-commit hook
cp ai-standards/templates/hooks/pre-commit-backend.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

# 3. Makefile quality targets
cat ai-standards/templates/makefile/quality-backend.mk >> Makefile
```

### Frontend service

```bash
mkdir -p .github/workflows
cp ai-standards/templates/ci/frontend-ci.yml.template .github/workflows/ci.yml
# Replace placeholders: {service-name}, {node-version}

cp ai-standards/templates/hooks/pre-commit-frontend.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

cat ai-standards/templates/makefile/quality-frontend.mk >> Makefile
```

### Package.json scripts required by the frontend hooks + CI

```json
{
  "scripts": {
    "lint": "eslint . --max-warnings=0",
    "format:check": "prettier --check \"src/**/*.{ts,vue,js,css}\"",
    "format": "prettier --write \"src/**/*.{ts,vue,js,css}\"",
    "type-check": "vue-tsc --noEmit",
    "test": "vitest run",
    "build": "vite build"
  }
}
```

## Workspace-level orchestration

The root `ai-standards/Makefile` wraps the per-service gates:

| Target | What it does |
|---|---|
| `make lint` | PHP-CS-Fixer dry-run on every backend service + ESLint + Prettier check on every frontend service |
| `make static` | PHPStan level 9 on every backend + `vue-tsc --noEmit` on every frontend |
| `make test` | Unit + integration tests on every service (already existed) |
| `make quality` | `lint` + `static` + `test` — the full gate bar across the workspace |

Running `make quality` from `ai-standards/` is the one-shot local equivalent of the CI pipeline.

## Drift validators (consuming projects)

Several standards (`secrets.md`, `gdpr-pii.md`, `feature-flags.md`, `audit-log.md`) declare that the codebase must stay in sync with an inventory document under `{project-docs}/`. Reviewer agents catch most drift, but a tooling layer is what makes the contract reliable instead of "remember to update the doc".

The `scripts/project-checks/` directory in ai-standards ships four bash validators a consuming project copies into its own `scripts/checks/` and wires into CI:

| Script | Inventory it validates | Source standard |
|---|---|---|
| `check-secret-drift.sh` | `secrets-manifest.md` | `secrets.md` (SC-002) |
| `check-pii-inventory-drift.sh` | `pii-inventory.md` | `gdpr-pii.md` (GD-001, GD-011) |
| `check-flag-drift.sh` | `feature-flags.md` | `feature-flags.md` (FF-001) |
| `check-audit-action-drift.sh` | `audit-actions.md` | `audit-log.md` (AU-009) |

Wire them via the project's `Makefile`:

```makefile
.PHONY: check-drift
check-drift:
	@scripts/checks/check-secret-drift.sh
	@scripts/checks/check-pii-inventory-drift.sh
	@scripts/checks/check-flag-drift.sh
	@scripts/checks/check-audit-action-drift.sh
```

Run `make check-drift` as part of `make quality` (or as a separate CI job — see `scripts/project-checks/README.md`). Non-zero exit fails the build with the list of missing inventory entries.

The provider list inside `check-pii-inventory-drift.sh` is curated per project — extend it as new sub-processors are introduced. Allowlists for legitimate exceptions live in `scripts/checks/secret-drift-allowlist.txt` and `scripts/checks/audit-action-drift-allowlist.txt`.

## Never bypass

- Never `git commit --no-verify` to skip the hook. If the hook is broken, fix it.
- Never merge a PR with failing CI. Red = red.
- Never add PHPStan baselines / `// @phpstan-ignore-next-line` without a linked issue and an explicit decision in `decisions.md`.
- Never lower strict mode settings (`strict: false`, `strictNullChecks: false`, etc.) to ship a feature.

## Review-time responsibility

Reviewer agents keep running their checklist — that catches design and architecture issues CI cannot see. The gates here catch mechanical issues **before** the reviewer looks at the code, freeing the reviewer to focus on what humans are better at.

## See also

- [new-service-checklist.md](new-service-checklist.md) — item that requires gates to be installed.
- [backend.md](backend.md) / [frontend.md](frontend.md) — the rules the gates enforce.
- [backend-review-checklist.md](backend-review-checklist.md) / [frontend-review-checklist.md](frontend-review-checklist.md) — what the reviewer agent still checks beyond the gates.
- Skill `quality-gates-setup` — step-by-step installation in a new service.
- [`../scripts/project-checks/README.md`](../scripts/project-checks/README.md) — drift validator usage, customisation, and CI wiring.
