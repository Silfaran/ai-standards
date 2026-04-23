# Workspace (smoke-test fixture)

project: smoke-fixture-standard
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

This workspace.md is a **test fixture** — not a real project. It exists to let
`/build-plan` resolve `{project-docs}` paths when the dynamic smoke harness
runs the orchestrator against `fake-docs/specs/board-set-title/`.
