#!/usr/bin/env bash
#
# Pre-commit hook for a Vue 3 / Vite / TypeScript service.
#
# Install:
#   cp ai-standards/templates/hooks/pre-commit-frontend.sh {service}/.git/hooks/pre-commit
#   chmod +x {service}/.git/hooks/pre-commit
#
# What it does (fast checks only — heavier checks run in CI):
#   1. ESLint on staged files
#   2. Prettier --check on staged files
#   3. vue-tsc on full project if any .ts/.vue changed (types cross files)
#
# Fails fast — the first failing check aborts the commit.
# To bypass temporarily (not recommended): git commit --no-verify

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

STAGED=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(ts|vue|js|mjs)$' || true)

if [ -z "$STAGED" ]; then
    exit 0
fi

echo "→ pre-commit: running frontend quality checks"

if [ -x node_modules/.bin/eslint ]; then
    echo "→ eslint (staged files)"
    node_modules/.bin/eslint --max-warnings=0 -- $STAGED
else
    echo "  skip: node_modules/.bin/eslint not found (run npm install)" >&2
fi

if [ -x node_modules/.bin/prettier ]; then
    echo "→ prettier --check (staged files)"
    node_modules/.bin/prettier --check -- $STAGED
else
    echo "  skip: node_modules/.bin/prettier not found" >&2
fi

# Type checking must run on the whole project — a type change in one file breaks others
if [ -x node_modules/.bin/vue-tsc ]; then
    echo "→ vue-tsc --noEmit (full project)"
    node_modules/.bin/vue-tsc --noEmit
else
    echo "  skip: node_modules/.bin/vue-tsc not found" >&2
fi

echo "→ pre-commit: OK"
