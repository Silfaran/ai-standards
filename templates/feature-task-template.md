# {Feature Name} — Task

## Description

## Related Spec
`{project-docs-path}/specs/{Aggregate}/{feature-name}-specs.md`

## Required Tests

The bullets below are informative for the Tester (they describe coverage targets). The Tester writes them in the Tester phase — the Developer never writes tests to satisfy DoD. See `## Definition of Done` → `### Tester scope` for the gated checklist.

### Unit Tests

### Integration Tests

## Definition of Done

The DoD is partitioned by agent role. **Tests live exclusively under `### Tester scope`** — the Developer marks those rows `⚠️ Tester scope` in their `## DoD coverage` and never writes the test to clear them. See `agents/tester-agent.md` and `agents/{backend,frontend}-developer-agent.md` for the contract.

### Backend (Developer scope)
- [ ] Code follows the architecture defined in `ai-standards/CLAUDE.md` and `ai-standards/standards/backend.md`
- [ ] All code passes PHPStan level 9
- [ ] All code passes PHP CS Fixer
- [ ] All controllers have OpenAPI/Swagger annotations
- [ ] Input validated at controller level (structural) before creating commands
- [ ] Business rules validated through Value Objects (domain layer)
- [ ] If this feature introduces a new bus: LoggingMiddleware wired to it (see `logging.md`)
- [ ] If this feature adds an authentication endpoint: rate limiting applied (see `security.md`)

### Frontend (Developer scope)
- [ ] Code follows `ai-standards/standards/frontend.md`
- [ ] All code passes ESLint and Prettier
- [ ] All code passes `vue-tsc --noEmit`

### Tester scope
- [ ] Unit tests written for every domain rule, value object and aggregate behaviour listed in `## Required Tests` → Unit Tests
- [ ] Integration tests written for every scenario listed in `## Required Tests` → Integration Tests
- [ ] Composable unit tests written (mutations, error handling, navigation) — frontend features only
- [ ] Page integration tests written (form submit, validation, loading/error states) — frontend features only
- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] Visual / interactive items in the spec verified via Playwright MCP (viewport sizes, light/dark parity, error-message rendering) — frontend features only

### Shared
- [ ] Code reviewed and approved by the corresponding Reviewer agent
- [ ] No security vulnerabilities detected (`composer audit`, `npm audit`)
- [ ] Spec updated via `update-specs` after implementation
