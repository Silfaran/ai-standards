# Board Activity Feed — Execution Plan

## Complexity: complex

Rationale against the classification table:

- THREE services affected (`task-service`, `notification-service`, `task-front`) —
  exceeds `standard`.
- NEW infrastructure required: a `board_activity` RabbitMQ transport
  (exchange + queue + DLQ) and a new Redis cache DB. DevOps phase is
  mandatory and MUST run before any Dev phase so both sides can pick up
  the new env vars + docker-compose entries.
- Backend + Frontend run in parallel against the same spec (new endpoint
  contract). Both sides warrant a Reviewer iteration.
- Cross-service message contract (`BoardActivityRecordedEvent`) + new read
  model + new SSE endpoint — non-trivial integration surface.

Per the command rules at `complex` complexity, the flow is:

```
DevOps (new infra — sequential)
  → Backend Developer ‖ Frontend Developer
    → Backend Reviewer ‖ Frontend Reviewer
      → Tester
```

## Standards Scope

| Agent | Extra reads (beyond context bundle) |
|---|---|
| DevOps | `new-service-checklist.md` (transport + env-var wiring idiom) |
| Backend Developer | `backend-reference.md` (Messenger transport, SSE endpoint, new-aggregate scaffold) |
| Frontend Developer | `frontend-reference.md` (composable + store pattern) |
| Backend Reviewer | none — uses `backend-review-checklist.md` |
| Frontend Reviewer | `design-decisions.md` (visual parity with existing board page) |
| Tester | `backend-reference.md` + Playwright DoD for feed visibility |

## Execution phases

### Phase 1 — DevOps (sequential — MUST run before Dev phases)

**Services touched:** `task-service`, `notification-service`

**Changes:**

| Area | Change |
|---|---|
| `docker-compose.yml` (root) | Declare `MESSENGER_TRANSPORT_BOARD_ACTIVITY` + `REDIS_BOARD_ACTIVITY_DB` env vars |
| `task-service/config/packages/messenger.yaml` | Add `board_activity` transport pointing to the new exchange |
| `notification-service/config/packages/messenger.yaml` | Add `board_activity` transport binding |
| `notification-service/.env.example` | Document the new env var |
| `task-service/.env.example` | Document the new env var |

**Definition of DevOps done:**

1. `docker build .` succeeds for both services
2. `docker compose config` validates without errors
3. Both new env vars declared in `.env.example`

**Handoff file:** `devops-handoff.md` listing all env vars added and all
files touched. Both Dev phases read this before starting.

### Phase 2a — Backend Developer (parallel with 2b)

**Service:** `task-service` + `notification-service`

Scope summarized — full details in context bundle:

- task-service: emit `BoardActivityRecordedEvent` on board write paths
- notification-service: consumer, read-model persistence, `GET /boards/{id}/activity`

### Phase 2b — Frontend Developer (parallel with 2a)

**Service:** `task-front`

- New `BoardActivityFeed.vue` + composable + store slice
- Integrates with the new `/activity` endpoint via SSE or polling fallback

### Phase 3a — Backend Reviewer (parallel with 3b)

Checklist-driven review of the two backend services' diffs.

### Phase 3b — Frontend Reviewer (parallel with 3a)

Checklist-driven review of the frontend diff + design-decisions compliance.

### Phase 4 — Tester

Unit + integration on backend, Playwright DoD on frontend (feed visibility,
filter-by-type interaction).

## Out of plan

- No change to the deletion cascade (out of scope)
- No retention policy yet (follow-up)
