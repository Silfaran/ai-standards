# Workspace (smoke-test fixture — complex)

project: smoke-fixture-complex
services: fake-docs/services.md
specs: fake-docs/specs/
decisions: fake-docs/decisions.md
design-decisions: fake-docs/design-decisions.md
lessons-learned: fake-docs/lessons-learned/
handoffs: handoffs/

## Service Ports

| Service | Port | Type |
|---|---|---|
| task-service | 8080 | Backend HTTP |
| notification-service | 8082 | Backend worker |
| task-front | 3002 | Frontend dev |

Fixture for `Complexity: complex` — exercises the orchestrator's DevOps-first
branch when the plan declares new infrastructure (RabbitMQ queue + Redis).
