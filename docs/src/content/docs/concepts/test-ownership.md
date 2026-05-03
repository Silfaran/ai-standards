---
title: Test ownership
description: Why a single specialised agent (Tester) writes every test, and how the partitioned task DoD + the `⚠️ Tester scope` mark prevent the Developer from duplicating that work.
---

In any pipeline that has both a Developer agent and a Tester agent, two contracts can fight each other:

- The Developer's *Definition-of-Done verification gate* says "every DoD checkbox must have a verified artefact, or the handoff is blocked".
- The Tester's *Role* says "writes and executes all tests after implementation and review are complete".

If the task's DoD lists test rows under the Developer's section (e.g. *"Composable unit tests written"*), both contracts apply at once: the Developer is forced to write the test to clear the gate, and the Tester writes their own version later. The result is the duplication you would expect — two agents producing partially overlapping tests, billed twice in Opus and Sonnet tokens.

The framework resolves this with a partitioned DoD and an explicit `⚠️ Tester scope` mark.

## The four-section task DoD

[`templates/feature-task-template.md`](https://github.com/Silfaran/ai-standards/blob/master/templates/feature-task-template.md) declares four DoD subsections:

| Subsection | Owner | Example rows |
|---|---|---|
| `### Backend (Developer scope)` | Backend Developer | Code passes PHPStan L9, OpenAPI annotation present, controller-level validation in place, LoggingMiddleware wired |
| `### Frontend (Developer scope)` | Frontend Developer | Code passes ESLint + vue-tsc, follows `frontend.md` |
| `### Tester scope` | Tester | Unit / integration / composable / page tests written, all tests pass, Playwright captures for visual + interactive items |
| `### Shared` | Reviewer + DoD-checker + final phase | Reviewer-approved, no security vulns, spec updated via `/update-specs` |

Test artefacts (every flavour: PHPUnit, Vitest, Playwright captures) live exclusively under `### Tester scope`. The Spec Analyzer is required to place them there when authoring the task file.

## The `⚠️ Tester scope` mark

Both Developer agents declare a four-mark `## DoD coverage` table:

| Mark | Meaning | Set by |
|---|---|---|
| `✓` | Artefact verified on disk via `grep`/`ls`/`Read` | Developer |
| `✗` | Artefact claimed but missing — handoff is blocked | Developer |
| `⚠️ Tester scope` | Row lives under `### Tester scope` of the task DoD; deferred to Tester | Developer (mandatory for every test row, never `✓`) |
| `⚠️` (other) | Verifiable only manually (e.g. multi-service smoke no automated tool can drive) | Developer |

The Tester later re-marks every `⚠️ Tester scope` row in their **own** `## DoD coverage` with `✓` / `✗` / `⚠️` after writing the artefact.

## Routing on `⚠️ Tester scope`

The DoD-checker is the gate between the Developer and the Reviewer. Per [`agents/dod-checker-agent.md`](https://github.com/Silfaran/ai-standards/blob/master/agents/dod-checker-agent.md), it carries `⚠️ Tester scope` rows forward to APPROVED **without verification**:

- Verifying them as if they were `✓` would either duplicate the Tester's work (when the test happens to already exist from a prior iteration) or false-fail (when it does not exist YET because the Tester has not run).
- The contract closure happens later, in the Tester's `## DoD coverage` section.
- The DoD-checker does cross-check that the `⚠️ Tester scope` mark was applied to a row that genuinely lives under `### Tester scope`. Misuse on an architecture / wiring / config row is downgraded to `✗` with a citation.

## Why this saves tokens (without sacrificing quality)

Empirical band measured against the previous shape (Dev writes tests to clear DoD, Tester rewrites or augments them):

| Phase | Before | After | Saving |
|---|---|---|---|
| Backend Developer iter 1 | 130-180k Opus | ~110-160k Opus | ~15-25k Opus |
| Frontend Developer iter 1 | 160-200k Opus | ~140-180k Opus | ~15-25k Opus |
| Tester | 36-110k Sonnet | unchanged | 0 |

Quality is preserved because the work is not removed — it is consolidated under a single specialised agent (the Tester) that already has the test-design context loaded (spec rules, fixtures, Playwright tooling, the `tester-bundle.md`). Removing the Developer's parallel attempt eliminates a class of problems where the Developer wrote a test that the Tester then had to delete or refactor.

## What the agents declare

- [`agents/backend-developer-agent.md`](https://github.com/Silfaran/ai-standards/blob/master/agents/backend-developer-agent.md) — verification gate step 2: "Rows under `### Tester scope` are NOT yours to satisfy [...] Mark every `### Tester scope` row as `⚠️ Tester scope` and skip the artefact verification".
- [`agents/frontend-developer-agent.md`](https://github.com/Silfaran/ai-standards/blob/master/agents/frontend-developer-agent.md) — same clause; adds Playwright as a Tester-scope artefact.
- [`agents/tester-agent.md`](https://github.com/Silfaran/ai-standards/blob/master/agents/tester-agent.md) — Role section declares the Test-ownership contract; output mandates a `## DoD coverage` re-marking every `⚠️ Tester scope` row.
- [`agents/dod-checker-agent.md`](https://github.com/Silfaran/ai-standards/blob/master/agents/dod-checker-agent.md) — Work Loop step 3 carries `⚠️ Tester scope` forward without verification; step 5 rejects `✓` marks that cite a test path.
- [`agents/spec-analyzer-agent.md`](https://github.com/Silfaran/ai-standards/blob/master/agents/spec-analyzer-agent.md) — Responsibilities require placing every test row under `### Tester scope`.

## Enforcement

- [Smoke check 25](/reference/smoke-checks/) anchors the contract in five places (template + four agents). If any of them drops the marker, CI fails on the smoke check.
- The dynamic smoke (`make smoke-dynamic`) exercises the live orchestrator against fixture projects and observes the DoD-checker's behaviour on `⚠️ Tester scope` rows.
