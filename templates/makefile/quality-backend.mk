# Backend quality targets — append to a PHP/Symfony service Makefile.
#
# Install:
#   cat ai-standards/templates/makefile/quality-backend.mk >> {service}/Makefile
# Then run the new targets from the service directory:
#   make lint          — PHP-CS-Fixer dry-run
#   make static        — PHPStan level 9
#   make security      — composer audit
#   make quality       — all of the above + tests
#
# Authoritative rules: ai-standards/standards/quality-gates.md

.PHONY: lint lint-fix static security quality

lint:
	docker compose exec $(shell basename $(CURDIR)) vendor/bin/php-cs-fixer fix --dry-run --diff --verbose

lint-fix:
	docker compose exec $(shell basename $(CURDIR)) vendor/bin/php-cs-fixer fix

static:
	docker compose exec $(shell basename $(CURDIR)) vendor/bin/phpstan analyse --memory-limit=1G --no-progress

security:
	docker compose exec $(shell basename $(CURDIR)) composer audit --no-dev

quality: lint static test security
	@echo "→ backend quality: PASS"
