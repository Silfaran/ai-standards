---
title: Coverage-aware checklist loading
description: How Reviewer agents avoid the ~520-rule full-checklist read — match critical paths first, compute the gap, then load checklist sections per-section with mandatory citation.
---

The Reviewer's job is to walk a closed list of verifiable rules against a diff. The naive approach — load `backend-review-checklist.md` (375 rules, ~520 lines) on every spawn — wastes 30-50k Sonnet tokens per Reviewer phase when the diff only touches 30-50 rules.

The coverage-aware protocol replaces that defensive read with a deterministic seven-step procedure.

## The seven steps

1. **Identify matching critical paths via PRIMARY triggers.** Read the developer handoff and the diff. Open every `critical-paths/*.md` whose `## When to load this path` PRIMARY trigger matches the diff. Load each such path's rules in full.

2. **Add SECONDARY paths only on coverage gap.** A path's SECONDARY trigger fires only when its content is needed AND no PRIMARY-loaded path covers it already.

3. **Compute the union of `## Coverage map vs full checklist`** across loaded paths. This is the covered surface.

4. **Compute the diff's CATEGORIES touched** — e.g. `tests/`, `config/services.yaml`, `src/Infrastructure/Persistence/Migration/`, controllers, repositories, logging, caching, observability.

5. **Identify the GAP** = categories touched MINUS coverage union.

6. **Load checklist SECTIONS in the gap only** — never the full checklist file. Use `Read` with `offset` + `limit` per section in `backend-review-checklist.md` / `frontend-review-checklist.md`.

7. **Reading the full checklist file in one go is permitted ONLY when 3+ different sections are needed.** Otherwise per-section reads.

## Mandatory citation

Every checklist section load MUST cite the gap that triggered it in the Reviewer's handoff:

> Loaded §Testing because diff includes `tests/Unit/MeServiceTest.php`; not covered by loaded paths (`auth-protected-action`, `pii-write-endpoint`).

A checklist load without citation is **rejected as defensive overhead**. This is enforced by smoke check 16, which anchors both the citation requirement clause and the *"cite the gap"* phrase in both reviewer agent files. Without the citation rule, the Reviewer slides back to the defensive full-checklist read and the empirical 30-50k Sonnet/phase saving evaporates.

## Why this works

A critical path's coverage map declares which checklist sections the path covers. The Reviewer's gap-computation in step 5 is a set operation: `categories_touched_by_diff - sections_covered_by_loaded_paths`. The result is the minimal set of checklist sections that need explicit per-section reads.

When a feature combines multiple paths (e.g. `crud-endpoint` + `auth-protected-action` + `pii-write-endpoint`), the coverage union is large and the gap is usually empty — the Reviewer never opens the full checklist at all.

## Empirical impact (measured 2026-05-02 in red-profesionales)

| Phase | Before #102 | After #102+#104 | Predicted | Result |
|---|---:|---:|---:|---:|
| Backend Reviewer (feature 1) | ~130k | 84k | 80-100k | ✓ in band |
| Frontend Reviewer iter 1 (feature 2) | ~130k | 95k | 80-100k | ✓ in band |
| Frontend Reviewer iter 2 fast (feature 2) | — | 47k | ~50% iter 1 | ✓ ~50% |

Both features confirmed the predicted 30-50k Sonnet savings per Reviewer phase. Two consecutive datapoints in band.

## Fast re-review mode

When the Reviewer is on iteration ≥ 2 AND the developer's iter-2 diff modifies ≤ 5 files AND iter-1 findings were mechanical (not structural), the Reviewer:

- Re-loads only the critical-path file(s) whose rules touched the iter-1 findings.
- Skips re-walking critical paths whose rules were already PASS in iter 1 AND the iter-2 diff does not touch them.
- Each row's "STILL PASS" justification is a one-liner unless the iter-2 diff touched the rule's surface.
- Target: ~30-40k tokens for a focused re-review (measured 47k on a frontend feature).

The Reviewer states explicitly when fast mode applies via the handoff's `## Re-review mode` section. This makes the cost choice auditable.

## What this does not relax

- The Reviewer NEVER skips a rule that appears in a loaded path.
- "Hard blockers" (BE-001 quality gates, SC-001 secrets, LO-001 redaction) are explicit rows in every path's coverage map and are walked on every spawn.
- The path narrows the search; it does not relax the bar.

## Source files

- `agents/backend-reviewer-agent.md` and `agents/frontend-reviewer-agent.md` — the canonical 7-step protocol.
- `commands/build-plan-command.md` — Reviewer prompt template + Failure Handling Status gate.
- `scripts/smoke-tests.sh` — checks 16 (gap citation) + 15 (every critical path declares the structure).
- `standards/critical-paths/README.md` — overview + maintenance protocol.
