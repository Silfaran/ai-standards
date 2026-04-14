# {Feature Name} — Handoff from {Agent Role}

## Files Created
<!-- List every new file with its full path. Example:
- `src/Domain/Model/Task.php`
- `src/Application/Command/Task/CreateTask/CreateTaskCommand.php`
-->

## Files Modified
<!-- List every modified file with its full path and a brief description of the change. Example:
- `config/services.yaml` — added handler tag for `CreateTaskCommandHandler`
-->

## Key Decisions
<!-- Non-obvious decisions that the next agent needs to understand. Focus on "why", not "what" — the code shows the what. Example:
- Used `fanout` exchange instead of `direct` because multiple consumers may subscribe in the future
-->

## For the Next Agent
<!-- What the next agent should focus on — and what they can safely ignore. Example:
- **Focus on:** integration tests for the `/api/tasks` endpoint (see task file Phase 2)
- **Ignore:** domain model and value objects — already reviewed and approved
- **Watch out for:** the `TaskStatus` value object accepts only `pending`, `in_progress`, `done` — tests should cover invalid values
-->

## Open Questions
<!-- Any unresolved decisions that need developer input. Delete this section if empty. -->
