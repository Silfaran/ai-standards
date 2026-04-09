# {Feature Name} — Task

## Description
<!-- Brief description of what needs to be implemented -->

## Related Spec
`{project-docs-path}/specs/{Aggregate}/{feature-name}-specs.md`

## Required Tests

### Phase 1 — Unit Tests (written before implementation)
<!-- Domain rules to encode as unit tests -->
<!-- Example: Password validation (min 8 chars, 1 uppercase, 1 number, 1 special char) -->

### Phase 2 — Integration Tests (written after implementation)
<!-- HTTP scenarios to test end-to-end -->
<!-- Example: POST /api/register with valid data → 201 -->
<!-- Example: POST /api/register with existing email → 409 -->

## Definition of Done
- [ ] Code follows the architecture defined in `ai-standards/CLAUDE.md`
- [ ] All code passes PHPStan level 9 (backend)
- [ ] All code passes PHP CS Fixer (backend)
- [ ] All code passes ESLint and Prettier (frontend)
- [ ] All controllers have OpenAPI/Swagger annotations (backend)
- [ ] All Phase 1 unit tests pass
- [ ] All Phase 2 integration tests pass
- [ ] Code reviewed and approved by the corresponding Reviewer agent
- [ ] No security vulnerabilities detected
- [ ] Spec updated via `update-specs` after implementation
