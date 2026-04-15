INFRA_COMPOSE = docker compose -f ../docker-compose.yml

-include workspace.mk

ALL_SERVICES = $(BACKEND_SERVICES) $(FRONTEND_SERVICES)

.PHONY: up down build update infra-up infra-down test test-unit test-integration logs ps

# --- Infrastructure (shared: PostgreSQL, RabbitMQ, Mailpit) ---

infra-up:
	$(INFRA_COMPOSE) up -d

infra-down:
	$(INFRA_COMPOSE) down

# --- All services ---

up: infra-up
	@if [ -z "$(ALL_SERVICES)" ]; then \
		echo "workspace.mk not found — run /init-project first"; exit 1; \
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
		echo "workspace.mk not found — run /init-project first"; exit 1; \
	fi
	@for s in $(ALL_SERVICES); do \
		echo "Building $$s..."; \
		docker compose -f ../$$s/docker-compose.yml build; \
	done

update: build up

# --- Tests ---

test:
	@if [ -z "$(BACKEND_SERVICES)$(FRONTEND_SERVICES)" ]; then \
		echo "workspace.mk not found — run /init-project first"; exit 1; \
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
		echo "workspace.mk not found — run /init-project first"; exit 1; \
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
		echo "workspace.mk not found — run /init-project first"; exit 1; \
	fi
	@for s in $(BACKEND_SERVICES); do \
		echo "Integration testing $$s..."; \
		docker compose -f ../$$s/docker-compose.yml exec $$s php vendor/bin/phpunit --testsuite=integration || exit 1; \
	done

# --- Utilities ---

logs:
	$(INFRA_COMPOSE) logs -f

ps:
	@echo "=== Infrastructure ===" && $(INFRA_COMPOSE) ps
	@for s in $(ALL_SERVICES); do \
		echo "=== $$s ===" && docker compose -f ../$$s/docker-compose.yml ps 2>/dev/null; \
	done
