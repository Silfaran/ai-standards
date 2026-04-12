DOCKER_COMPOSE = docker compose -f ../docker-compose.yml

-include workspace.mk

.PHONY: up down build update test test-unit test-integration logs ps

up:
	$(DOCKER_COMPOSE) up -d

down:
	$(DOCKER_COMPOSE) down

build:
	$(DOCKER_COMPOSE) build

update:
	$(DOCKER_COMPOSE) build
	$(DOCKER_COMPOSE) up -d

test:
	@if [ -z "$(BACKEND_SERVICES)$(FRONTEND_SERVICES)" ]; then \
		echo "workspace.mk not found — run /init-project first"; exit 1; \
	fi
	@for s in $(BACKEND_SERVICES); do \
		echo "Testing $$s..."; \
		$(DOCKER_COMPOSE) exec $$s php vendor/bin/phpunit || exit 1; \
	done
	@for s in $(FRONTEND_SERVICES); do \
		echo "Testing $$s..."; \
		$(DOCKER_COMPOSE) exec $$s npm run test || exit 1; \
	done

test-unit:
	@if [ -z "$(BACKEND_SERVICES)$(FRONTEND_SERVICES)" ]; then \
		echo "workspace.mk not found — run /init-project first"; exit 1; \
	fi
	@for s in $(BACKEND_SERVICES); do \
		echo "Unit testing $$s..."; \
		$(DOCKER_COMPOSE) exec $$s php vendor/bin/phpunit --testsuite=unit || exit 1; \
	done
	@for s in $(FRONTEND_SERVICES); do \
		echo "Unit testing $$s..."; \
		$(DOCKER_COMPOSE) exec $$s npm run test || exit 1; \
	done

test-integration:
	@if [ -z "$(BACKEND_SERVICES)" ]; then \
		echo "workspace.mk not found — run /init-project first"; exit 1; \
	fi
	@for s in $(BACKEND_SERVICES); do \
		echo "Integration testing $$s..."; \
		$(DOCKER_COMPOSE) exec $$s php vendor/bin/phpunit --testsuite=integration || exit 1; \
	done

logs:
	$(DOCKER_COMPOSE) logs -f

ps:
	$(DOCKER_COMPOSE) ps
