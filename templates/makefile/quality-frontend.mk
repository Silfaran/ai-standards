# Frontend quality targets — append to a Vue 3 / Vite service Makefile.
#
# Install:
#   cat ai-standards/templates/makefile/quality-frontend.mk >> {service}/Makefile
# Then run the new targets from the service directory:
#   make lint          — ESLint
#   make format        — Prettier --check
#   make type-check    — vue-tsc --noEmit
#   make security      — npm audit (high/critical)
#   make quality       — all of the above + tests
#
# Authoritative rules: ai-standards/standards/quality-gates.md

.PHONY: lint lint-fix format format-fix type-check security quality

lint:
	docker compose exec $(shell basename $(CURDIR)) npm run lint

lint-fix:
	docker compose exec $(shell basename $(CURDIR)) npm run lint -- --fix

format:
	docker compose exec $(shell basename $(CURDIR)) npm run format:check

format-fix:
	docker compose exec $(shell basename $(CURDIR)) npm run format

type-check:
	docker compose exec $(shell basename $(CURDIR)) npm run type-check

security:
	docker compose exec $(shell basename $(CURDIR)) npm audit --omit=dev --audit-level=high

quality: lint format type-check test security
	@echo "→ frontend quality: PASS"
