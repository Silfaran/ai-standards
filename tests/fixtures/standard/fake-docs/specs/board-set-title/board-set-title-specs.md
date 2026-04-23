# Board Set Title — Specs

## Status
Refined

## Business Description

Allow a board owner to rename an existing board. Any member with admin or owner
tier may send the new title; read-tier members cannot rename. The title is
persisted and returned in subsequent board read responses.

This spec exists solely as a **fixture for the dynamic smoke test** of the
`/build-plan` orchestrator — it is NOT a real feature and is not implemented
anywhere. Keep it minimal and self-contained.

## Affected Aggregate(s)

- Board (extended — new command + handler + endpoint)

## Affected Service(s)

- `task-service` — add `PATCH /boards/{id}/title` endpoint with command handler

## User Stories

- As a board owner or admin, I want to rename a board so that the title stays
  meaningful as the work evolves.

## Business Rules

- Only owner or admin-tier members may rename
- Title is a non-empty string, max 200 characters
- The update is atomic — no partial state
- Other fields (members, columns, tasks) are untouched by this operation

## Technical Details

### Endpoint

`PATCH /boards/{id}/title` — body: `{ "title": "<new title>" }` — returns 200
with the updated board, 403 if caller is not owner/admin, 404 if the board
does not exist, 422 if the title is empty or too long.

### Command flow

`SetBoardTitleCommand → SetBoardTitleCommandHandler → BoardFinderService →
BoardAccessAuthorizationService (TIER_ADMIN) → BoardRepository::save → 200`.

No RabbitMQ event is emitted (rename is internal state — no projection
consumer exists).

## Definition of Done

- Endpoint returns the documented status codes
- Authorization enforced at handler boundary (matches ADR-011 idiom)
- Repository stays nullable-only (throw-on-miss via `BoardFinderService`)
- Unit + integration tests cover happy path, 403, 404, 422
