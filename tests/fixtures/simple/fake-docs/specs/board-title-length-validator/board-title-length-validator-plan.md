# Board Title Length Validator — Execution Plan

## Complexity: simple

Rationale against the classification table:

- One new file (`Infrastructure/Validator/BoardTitleLength.php`), one DTO edit
  (single annotation line). Total files touched: 2. Below the `standard`
  threshold (5+).
- No handler refactor, no DB change, no cross-service wiring.
- The validator follows a well-known Symfony idiom — no architectural
  judgement required. Reviewer adds negligible signal.

Per the command rules at `simple` complexity, a single Developer+Tester agent
implements the feature AND writes/runs tests in one session. No separate
Reviewer phase (none of the criteria in the spec's `## Open Questions`
apply — there are none).

## Standards Scope

| Agent | Extra reads (beyond context bundle) |
|---|---|
| Backend Dev+Tester | `backend-reference.md` (Symfony validator attribute pattern, PHPUnit pattern for constraints) |

## Execution phases

### Phase 1 — Backend Dev+Tester (single agent)

**Service:** `task-service`

**Files to create:**

| File | Purpose |
|---|---|
| `task-service/src/Infrastructure/Validator/BoardTitleLength.php` | Custom constraint + validator pair following Symfony idiom. |
| `task-service/tests/Unit/Infrastructure/Validator/BoardTitleLengthTest.php` | Edge-case coverage (0, 1, 200, 201 chars, whitespace-only). |

**Files to modify:**

| File | Change |
|---|---|
| `task-service/src/Application/Dto/BoardTitleDto.php` | Replace inline `#[Assert\Length]` with `#[BoardTitleLength]`. |

**Definition of Dev done:**

1. `make test-unit` green — new test file covers the edge cases.
2. PHPStan level 9 clean.
3. PHP CS Fixer clean.

## Out of plan

- No Reviewer phase (per `simple` flow)
- No frontend
- No migration
- No new endpoint
