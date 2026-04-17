#!/usr/bin/env bash
#
# Pre-commit hook for a PHP/Symfony service.
#
# Install:
#   cp ai-standards/templates/hooks/pre-commit-backend.sh {service}/.git/hooks/pre-commit
#   chmod +x {service}/.git/hooks/pre-commit
#
# What it does (fast checks only — heavier checks run in CI):
#   1. PHP-CS-Fixer --dry-run on staged .php files
#   2. PHPStan on staged .php files
#   3. composer validate (if composer.json is staged)
#
# Fails fast — the first failing check aborts the commit.
# To bypass temporarily (not recommended): git commit --no-verify

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

STAGED_PHP=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.php$' || true)
STAGED_COMPOSER=$(git diff --cached --name-only --diff-filter=ACM | grep -E '^(composer\.(json|lock))$' || true)

# Nothing relevant staged → pass silently
if [ -z "$STAGED_PHP" ] && [ -z "$STAGED_COMPOSER" ]; then
    exit 0
fi

echo "→ pre-commit: running backend quality checks"

if [ -n "$STAGED_COMPOSER" ]; then
    if [ -x vendor/bin/composer ] || command -v composer >/dev/null 2>&1; then
        echo "→ composer validate"
        composer validate --strict --no-check-publish
    fi
fi

if [ -n "$STAGED_PHP" ]; then
    if [ -x vendor/bin/php-cs-fixer ]; then
        echo "→ php-cs-fixer (staged files)"
        vendor/bin/php-cs-fixer fix --dry-run --diff --path-mode=intersection -- $STAGED_PHP
    else
        echo "  skip: vendor/bin/php-cs-fixer not found (run composer install)" >&2
    fi

    if [ -x vendor/bin/phpstan ]; then
        echo "→ phpstan (staged files)"
        vendor/bin/phpstan analyse --no-progress --memory-limit=1G -- $STAGED_PHP
    else
        echo "  skip: vendor/bin/phpstan not found (run composer install)" >&2
    fi
fi

echo "→ pre-commit: OK"
