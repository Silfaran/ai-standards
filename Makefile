DOCKER_COMPOSE = docker compose -f ../docker-compose.yml

.PHONY: up down build update test logs

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
	$(DOCKER_COMPOSE) exec login-service php vendor/bin/phpunit
	$(DOCKER_COMPOSE) exec login-front npm run test

test-unit:
	$(DOCKER_COMPOSE) exec login-service php vendor/bin/phpunit --testsuite=unit
	$(DOCKER_COMPOSE) exec login-front npm run test:unit

test-integration:
	$(DOCKER_COMPOSE) exec login-service php vendor/bin/phpunit --testsuite=integration
	$(DOCKER_COMPOSE) exec login-front npm run test:integration

logs:
	$(DOCKER_COMPOSE) logs -f

ps:
	$(DOCKER_COMPOSE) ps
