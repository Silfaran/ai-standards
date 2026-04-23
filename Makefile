INFRA_COMPOSE = docker compose -f ../docker-compose.yml

# Resolve the project docs directory from the pointer file.
# `.workspace-config-path` is created by `/init-project` and contains a single
# relative path (e.g. `../task-manager-docs`) to the project's docs repo where
# `workspace.mk` and `workspace.md` live. Gitignored — per-workspace.
PROJECT_DOCS := $(shell cat .workspace-config-path 2>/dev/null)

-include $(PROJECT_DOCS)/workspace.mk

ALL_SERVICES = $(BACKEND_SERVICES) $(FRONTEND_SERVICES)

.PHONY: up down build update infra-up infra-down test test-unit test-integration lint static quality smoke smoke-dynamic logs ps

# --- Framework self-checks ---

smoke:
	@./scripts/smoke-tests.sh

# Dynamic smoke — exercises the /build-plan orchestrator against a minimal
# fixture, intercepts the first Agent spawn, asserts the model tier +
# context-bundle invariants. Real API tokens — local only, run manually
# before cutting a release or after changing agents/commands. See tests/README.md.
smoke-dynamic:
	@./tests/harness/run-smoke.sh

# --- Infrastructure (shared: PostgreSQL, RabbitMQ, Mailpit) ---

infra-up:
	$(INFRA_COMPOSE) up -d

infra-down:
	$(INFRA_COMPOSE) down

# --- All services ---

up: infra-up
	@if [ -z "$(ALL_SERVICES)" ]; then \
		echo "Project workspace config not found (missing .workspace-config-path or {project-docs}/workspace.mk) — run /init-project first"; exit 1; \
	fi
	@for s in $(ALL_SERVICES); do \
		echo "Starting $$s..."; \
		docker compose -f ../$$s/docker-compose.yml up -d; \
	done

down:
	@for s in $(ALL_SERVICES); do \
		docker compose -f ../$$s/docker-compose.yml down 2>/dev/null; \
	done
	$(INFRA_COMPOSE) down

build:
	@if [ -z "$(ALL_SERVICES)" ]; then \
		echo "Project workspace config not found (missing .workspace-config-path or {project-docs}/workspace.mk) — run /init-project first"; exit 1; \
	fi
	@for s in $(ALL_SERVICES); do \
		echo "Building $$s..."; \
		docker compose -f ../$$s/docker-compose.yml build; \
	done

update: build up

# --- Tests ---

test:
	@if [ -z "$(BACKEND_SERVICES)$(FRONTEND_SERVICES)" ]; then \
		echo "Project workspace config not found (missing .workspace-config-path or {project-docs}/workspace.mk) — run /init-project first"; exit 1; \
	fi
	@for s in $(BACKEND_SERVICES); do \
		echo "Testing $$s..."; \
		docker compose -f ../$$s/docker-compose.yml exec $$s php vendor/bin/phpunit || exit 1; \
	done
	@for s in $(FRONTEND_SERVICES); do \
		echo "Testing $$s..."; \
		docker compose -f ../$$s/docker-compose.yml exec $$s npm run test || exit 1; \
	done

test-unit:
	@if [ -z "$(BACKEND_SERVICES)$(FRONTEND_SERVICES)" ]; then \
		echo "Project workspace config not found (missing .workspace-config-path or {project-docs}/workspace.mk) — run /init-project first"; exit 1; \
	fi
	@for s in $(BACKEND_SERVICES); do \
		echo "Unit testing $$s..."; \
		docker compose -f ../$$s/docker-compose.yml exec $$s php vendor/bin/phpunit --testsuite=unit || exit 1; \
	done
	@for s in $(FRONTEND_SERVICES); do \
		echo "Unit testing $$s..."; \
		docker compose -f ../$$s/docker-compose.yml exec $$s npm run test || exit 1; \
	done

test-integration:
	@if [ -z "$(BACKEND_SERVICES)" ]; then \
		echo "Project workspace config not found (missing .workspace-config-path or {project-docs}/workspace.mk) — run /init-project first"; exit 1; \
	fi
	@for s in $(BACKEND_SERVICES); do \
		echo "Integration testing $$s..."; \
		docker compose -f ../$$s/docker-compose.yml exec $$s php vendor/bin/phpunit --testsuite=integration || exit 1; \
	done

# --- Quality gates (across services) ---

lint:
	@if [ -z "$(BACKEND_SERVICES)$(FRONTEND_SERVICES)" ]; then \
		echo "Project workspace config not found (missing .workspace-config-path or {project-docs}/workspace.mk) — run /init-project first"; exit 1; \
	fi
	@for s in $(BACKEND_SERVICES); do \
		echo "Linting $$s (php-cs-fixer)..."; \
		docker compose -f ../$$s/docker-compose.yml exec $$s vendor/bin/php-cs-fixer fix --dry-run --diff || exit 1; \
	done
	@for s in $(FRONTEND_SERVICES); do \
		echo "Linting $$s (eslint + prettier)..."; \
		docker compose -f ../$$s/docker-compose.yml exec $$s npm run lint || exit 1; \
		docker compose -f ../$$s/docker-compose.yml exec $$s npm run format:check || exit 1; \
	done

static:
	@if [ -z "$(BACKEND_SERVICES)$(FRONTEND_SERVICES)" ]; then \
		echo "Project workspace config not found (missing .workspace-config-path or {project-docs}/workspace.mk) — run /init-project first"; exit 1; \
	fi
	@for s in $(BACKEND_SERVICES); do \
		echo "Static analysis $$s (phpstan level 9)..."; \
		docker compose -f ../$$s/docker-compose.yml exec $$s vendor/bin/phpstan analyse --memory-limit=1G --no-progress || exit 1; \
	done
	@for s in $(FRONTEND_SERVICES); do \
		echo "Type-checking $$s (vue-tsc)..."; \
		docker compose -f ../$$s/docker-compose.yml exec $$s npm run type-check || exit 1; \
	done

quality: lint static test
	@echo "=== Quality gates: PASS ==="

# --- Utilities ---

logs:
	$(INFRA_COMPOSE) logs -f

ps:
	@echo "=== Infrastructure ===" && $(INFRA_COMPOSE) ps
	@for s in $(ALL_SERVICES); do \
		echo "=== $$s ===" && docker compose -f ../$$s/docker-compose.yml ps 2>/dev/null; \
	done
