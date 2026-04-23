# Workspace (smoke-test fixture — simple)

project: smoke-fixture-simple
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

Fixture for `Complexity: simple` — exercises the orchestrator's single-agent
Dev+Tester branch.
