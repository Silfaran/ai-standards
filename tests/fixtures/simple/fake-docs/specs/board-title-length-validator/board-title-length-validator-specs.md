# Board Title Length Validator — Specs

## Status
Refined

## Business Description

Add a Symfony validator constraint that enforces board titles between 1 and
200 characters. Existing create/update flows will apply it; no new endpoint.

Fixture-only spec for the dynamic smoke test — not a real feature.

## Affected Aggregate(s)

- Board (validation rule added)

## Affected Service(s)

- `task-service` — new validator class + DTO attribute annotation

## User Stories

- As a board member, I want a clear error when a title is empty or overly long
  so I know what to correct.

## Business Rules

- Title length: `1..=200`
- Trimmed before validation
- 422 with a single validation error when the rule fails

## Technical Details

- New class: `Infrastructure/Validator/BoardTitleLength.php` (Symfony constraint)
- DTO annotation: `#[BoardTitleLength]` on `BoardTitleDto::title`

No DB change, no handler change, no new endpoint — the existing handler picks
up the annotation via Symfony's validator autowiring.

## Definition of Done

- Constraint rejects empty + >200
- Existing create/update endpoints return 422 on violation
- Unit test covers edge cases (0, 1, 200, 201 chars, whitespace-only)
