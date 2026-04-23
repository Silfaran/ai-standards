# Board Activity Feed — Task

## Definition of Done

### Infrastructure (DevOps)
- [ ] `board_activity` RabbitMQ transport declared in both services' messenger.yaml
- [ ] `REDIS_BOARD_ACTIVITY_DB` env var added to both `.env.example` files
- [ ] `docker compose config` validates clean
- [ ] `docker build .` succeeds for each affected service

### Backend (task-service)
- [ ] `BoardActivityRecordedEvent` emitted on every board write handler
- [ ] Unit tests cover the emission path per handler
- [ ] PHPStan level 9 clean, PHP CS Fixer clean

### Backend (notification-service)
- [ ] Consumer persists events to `board_activity` read table
- [ ] `GET /boards/{id}/activity` returns 200 with paginated entries
- [ ] Unit + integration tests cover 200 / 403 / 404 / empty-feed paths

### Frontend
- [ ] `BoardActivityFeed.vue` renders the list
- [ ] Filter-by-type interaction works
- [ ] Loading / error / empty states implemented per FE rules
- [ ] Playwright DoD: open a board, verify feed renders, filter, verify update
