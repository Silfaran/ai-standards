# Board Set Title — Execution Plan

## Complexity: standard

Single-service backend feature. Moderate file count (new command, new handler,
new controller, unit + integration tests, `services.yaml` wiring). No migration,
no infrastructure change, no frontend work, no messaging. Warrants a Reviewer
pass for the new authorization/finder-service wiring — does not reach `complex`.

## Standards Scope

| Agent | Extra reads (beyond context bundle) |
|---|---|
| Backend Developer | `backend-reference.md` (command handler extraction pattern, finder-service composition) |
| Backend Reviewer | none — uses `backend-review-checklist.md` |
| Tester | `backend-reference.md` (PHPUnit patterns for repository mocks) |

## Execution phases

### Phase 1 — Backend Developer

**Service:** `task-service`

**Files to create:**

| File | Purpose |
|---|---|
| `task-service/src/Application/Command/Board/SetBoardTitle/SetBoardTitleCommand.php` | DTO with `boardId`, `title`, `requesterId`. |
| `task-service/src/Application/Command/Board/SetBoardTitle/SetBoardTitleCommandHandler.php` | Orchestrates finder → auth → save. Injects `BoardFinderService`, `BoardAccessAuthorizationService`, `BoardRepositoryInterface`. |
| `task-service/src/Infrastructure/Http/Board/SetBoardTitleController.php` | Thin controller — parses request, dispatches command, returns updated board. |

**Files to modify:**

| File | Change |
|---|---|
| `task-service/config/services.yaml` | Verify autowiring covers the new handler and controller. |
| `task-service/config/routes.yaml` | Register `PATCH /boards/{id}/title` → `SetBoardTitleController`. |

**Definition of Dev done:**

1. `make test-unit` green — new handler unit test.
2. `make test-integration` green — new endpoint integration test (200, 403, 404, 422).
3. PHPStan level 9 clean.
4. PHP CS Fixer clean.

### Phase 2 — Backend Reviewer

Scope limited to files modified in Phase 1. Uses `backend-review-checklist.md`.
Loop terminates after developer addresses flagged items; max 3 iterations.

### Phase 3 — Tester

**Service:** `task-service`

Unit tests for the handler (happy path, 403, 404, 422). Integration test for
the endpoint. Regression check that existing `/boards/{id}` GET responses
include the updated title after a PATCH.

## Out of plan

- No frontend work
- No migration
- No RabbitMQ event
- No `INDEX.md` or `decisions.md` edits during refine-specs
