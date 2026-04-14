# {Feature Name} — Task

## Description

## Related Spec
`{project-docs-path}/specs/{Aggregate}/{feature-name}-specs.md`

## Required Tests

### Phase 1 — Unit Tests (written before implementation)

### Phase 2 — Integration Tests (written after implementation)

## Definition of Done

### Backend
- [ ] Code follows the architecture defined in `ai-standards/CLAUDE.md` and `ai-standards/standards/backend.md`
- [ ] All code passes PHPStan level 9
- [ ] All code passes PHP CS Fixer
- [ ] All controllers have OpenAPI/Swagger annotations
- [ ] Input validated at controller level (structural) before creating commands
- [ ] Business rules validated through Value Objects (domain layer)
- [ ] If this feature introduces a new bus: LoggingMiddleware wired to it (see `logging.md`)
- [ ] If this feature adds an authentication endpoint: rate limiting applied (see `security.md`)

### Frontend
- [ ] Code follows `ai-standards/standards/frontend.md`
- [ ] All code passes ESLint and Prettier
- [ ] Composable unit tests written (mutations, error handling, navigation)
- [ ] Page integration tests written (form submit, validation, loading/error states)

### Shared
- [ ] All Phase 1 unit tests pass
- [ ] All Phase 2 integration/page tests pass
- [ ] Code reviewed and approved by the corresponding Reviewer agent
- [ ] No security vulnerabilities detected (`composer audit`, `npm audit`)
- [ ] Spec updated via `update-specs` after implementation
