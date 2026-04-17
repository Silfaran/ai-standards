---
name: quality-gates-setup
description: Use when installing quality gates in a new or existing service — CI workflow, pre-commit hook, or Makefile quality targets. Covers the template-copy steps, placeholder substitution, required package.json scripts for frontends, and the single non-negotiable bar a service must meet.
paths: "**/.github/workflows/ci.yml, **/.github/workflows/ci.yaml, **/.git/hooks/pre-commit"
---

# Installing quality gates in a service

Three artifacts per service:
1. **Pre-commit hook** — `.git/hooks/pre-commit` (fast local checks on staged files).
2. **CI workflow** — `.github/workflows/ci.yml` (authoritative, runs on PR and push to master).
3. **Makefile quality targets** — `make lint`, `make static`, `make quality`.

Each copy is **verbatim from the template** — do not rewrite from memory. Templates live in [`ai-standards/templates/`](../../../templates/).

## Backend service (PHP / Symfony)

```bash
cd {service}

# CI
mkdir -p .github/workflows
cp ../ai-standards/templates/ci/backend-ci.yml.template .github/workflows/ci.yml

# Replace placeholders:
#   {service-name}      → e.g. login-service
#   {php-version}       → from ai-standards/standards/tech-stack.md
#   {postgres-image}    → from ai-standards/standards/tech-stack.md
#   {rabbitmq-image}    → from ai-standards/standards/tech-stack.md

# Pre-commit hook
cp ../ai-standards/templates/hooks/pre-commit-backend.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

# Makefile
cat ../ai-standards/templates/makefile/quality-backend.mk >> Makefile
```

The backend hook skips itself silently if no `.php` or `composer.*` files are staged, so it doesn't get in the way of non-code commits.

## Frontend service (Vue 3 / Vite / TypeScript)

```bash
cd {frontend-service}

# CI
mkdir -p .github/workflows
cp ../ai-standards/templates/ci/frontend-ci.yml.template .github/workflows/ci.yml

# Replace placeholders:
#   {service-name}     → e.g. login-front
#   {node-version}     → from ai-standards/standards/tech-stack.md

# Pre-commit hook
cp ../ai-standards/templates/hooks/pre-commit-frontend.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

# Makefile
cat ../ai-standards/templates/makefile/quality-frontend.mk >> Makefile
```

### Required `package.json` scripts

The frontend CI and hook call these scripts — the installation is incomplete until they exist:

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

If any are missing, add them before committing the CI file — otherwise CI will fail on the very first run with `missing script: lint`.

## Verifying installation

After copying, test each layer locally. All must pass before opening a PR.

```bash
# 1. Hook — make a trivial edit, stage it, try to commit
echo '// whitespace' >> src/Kernel.php && git add src/Kernel.php
git commit -m "test" --dry-run    # or a real commit

# 2. Makefile target
make quality

# 3. CI — push to a branch and watch the Actions tab
```

## Placeholder replacement helper

For consistency, replace placeholders in one pass with `sed`:

```bash
sed -i '' \
    -e "s/{service-name}/login-service/g" \
    -e "s/{php-version}/8.4/g" \
    -e "s/{postgres-image}/postgres:17/g" \
    -e "s/{rabbitmq-image}/rabbitmq:4-management/g" \
    .github/workflows/ci.yml
```

(macOS `sed` requires the empty string after `-i`. Drop the `''` on Linux.)

## Common installation mistakes

- **Wrong PHP/Node version.** Always copy the current minimum from [`tech-stack.md`](../../../standards/tech-stack.md) — do not hard-code a version from another service's CI file.
- **Forgetting to `chmod +x`.** Git will stage the hook as a regular file; it will not execute.
- **Missing frontend scripts.** Add the `package.json` scripts **before** committing the CI file.
- **Baselining to hide PHPStan level-9 violations.** Do not. Fix the underlying typing. If truly unavoidable, record the decision in `decisions.md` first.
- **Turning off a check "temporarily"** because a legacy file is noisy. Fix the legacy file in a separate PR; do not ship weakening.

## What the gates do NOT replace

- Architecture review (CQRS split, DDD aggregate boundaries, Hexagonal layering) — still reviewer territory.
- Design decisions (shadcn patterns, spec compliance) — reviewer + `design-decisions.md`.
- Security trade-offs (rate-limiter key choice, JWT payload composition) — reviewer + corresponding skill.

The gates are the **floor**, not the ceiling.

## See also

- [standards/quality-gates.md](../../../standards/quality-gates.md) — authoritative rules the gates enforce.
- [standards/new-service-checklist.md](../../../standards/new-service-checklist.md) — installation as a pre-first-commit requirement.
- `new-service-bootstrap` skill — the scaffold steps that should precede gate installation.
