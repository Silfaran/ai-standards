# Board Activity Feed — Specs

## Status
Refined

## Business Description

Display a chronological activity feed on every board — who joined, who
updated a task, who deleted a column. Events are produced by `task-service`,
consumed by `notification-service`, projected into a read model, and
rendered by `task-front` via a new `GET /boards/{id}/activity` endpoint.

Fixture-only spec for the dynamic smoke test — not a real feature. Its
sole purpose is to force `/build-plan` to choose the DevOps-first branch
of the complex flow.

## Affected Aggregate(s)

- BoardActivity (new aggregate owned by notification-service)
- Board (event emitter; untouched business rules)

## Affected Service(s)

- `task-service` — emits `BoardActivityRecordedEvent` on every board write
- `notification-service` — consumes the event, persists it to a new read
  table `board_activity`, exposes `GET /boards/{id}/activity`
- `task-front` — new `BoardActivityFeed.vue` component on the board page

## New infrastructure required

- **New RabbitMQ transport** `board_activity` (exchange + queue + DLQ).
- **New Redis cache database** (index 3) for the activity list cache.
- Both require `docker-compose.yml` edits in every service that touches
  the transports + env-var additions (`MESSENGER_TRANSPORT_BOARD_ACTIVITY`,
  `REDIS_BOARD_ACTIVITY_DB`).

These are NEW — no existing transport/cache can be reused without changing
contracts. DevOps MUST run before either Dev phase.

## User Stories

- As a board member, I see a live-updating feed of recent activity on my board
- As an admin, I filter the feed by event type

## Technical Details

### Event payload

`BoardActivityRecordedEvent { boardId, userId, action, timestamp, metadata }`

### Endpoint

`GET /boards/{id}/activity?type=&since=&limit=` — returns 200 with paginated
entries. 403 on non-member, 404 on missing board.

## Definition of Done

- DevOps lands new transport + Redis db + env vars in every affected service
- task-service emits events on every board write path
- notification-service consumer persists + exposes the endpoint
- task-front renders the feed with polling-free updates via a SSE variant
  (or fallback polling)
- Unit + integration + Playwright DoD for feed visibility
