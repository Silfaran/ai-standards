# Board Set Title — Task

## Definition of Done

- [ ] `SetBoardTitleCommand` created with 3 fields (`boardId`, `title`, `requesterId`)
- [ ] `SetBoardTitleCommandHandler` created — composes `BoardFinderService`, `BoardAccessAuthorizationService::execute(..., TIER_ADMIN)`, `BoardRepositoryInterface::save`
- [ ] `SetBoardTitleController` created — 200 on success, 403 unauthorized, 404 not-found, 422 invalid title
- [ ] Route `PATCH /boards/{id}/title` registered in `routes.yaml`
- [ ] `services.yaml` autowires the new handler
- [ ] Unit test `SetBoardTitleCommandHandlerTest` covers happy path + 3 error paths
- [ ] Integration test `SetBoardTitleControllerTest` covers 200 / 403 / 404 / 422 responses
- [ ] `make test-unit` and `make test-integration` green
- [ ] PHPStan level 9 clean
- [ ] PHP CS Fixer clean
