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

# Prefer running inside the Docker service container when available, so developers
# do not need PHP/Composer installed on the host. Falls back to host binaries when
# the container is not running. If neither is available, skip with a warning — CI
# runs the full gate against a clean VM anyway.
SERVICE_NAME="$(basename "$REPO_ROOT")"
DOCKER_EXEC=""
if command -v docker >/dev/null 2>&1 \
    && docker compose ps --services --filter status=running 2>/dev/null | grep -qx "$SERVICE_NAME"; then
    DOCKER_EXEC="docker compose exec -T $SERVICE_NAME"
fi

run_php() {
    if [ -n "$DOCKER_EXEC" ]; then
        $DOCKER_EXEC "$@"
    elif command -v php >/dev/null 2>&1; then
        "$@"
    else
        return 127
    fi
}

if [ -n "$STAGED_COMPOSER" ]; then
    echo "→ composer validate"
    if ! run_php composer validate --strict --no-check-publish; then
        rc=$?
        if [ "$rc" -eq 127 ]; then
            echo "  skip: composer not available on host and no running service container" >&2
        else
            exit $rc
        fi
    fi
fi

if [ -n "$STAGED_PHP" ]; then
    echo "→ php-cs-fixer (staged files)"
    if ! run_php vendor/bin/php-cs-fixer fix --dry-run --diff --path-mode=intersection -- $STAGED_PHP; then
        rc=$?
        if [ "$rc" -eq 127 ]; then
            echo "  skip: php not available on host and no running service container (CI will catch it)" >&2
        else
            exit $rc
        fi
    fi

    echo "→ phpstan (staged files)"
    if ! run_php vendor/bin/phpstan analyse --no-progress --memory-limit=1G -- $STAGED_PHP; then
        rc=$?
        if [ "$rc" -eq 127 ]; then
            echo "  skip: php not available on host and no running service container (CI will catch it)" >&2
        else
            exit $rc
        fi
    fi
fi

echo "→ pre-commit: OK"
