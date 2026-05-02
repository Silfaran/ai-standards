---
title: Your first feature in five minutes
description: Walkthrough of building a feature end-to-end — describe → spec → plan → build → merge — with the actual prompts and expected outputs.
---

This walkthrough takes you from "I want to add a login screen" to "the feature is on `master` with tests" in roughly five wall-clock minutes of typing and ~30-40 minutes of agent runtime.

The example uses a fictional `auth-service` + `web-front` repo pair. Replace with your own service names.

## 0. Pre-flight check

You should already have:

- A workspace where `/init-project` has run.
- The target service repos checked out under your workspace (e.g. `my-workspace/auth-service/`, `my-workspace/web-front/`).
- Both repos on `master` with a clean working tree.

If not, see the [Quickstart](/ai-standards/guides/quickstart/).

## 1. Describe the feature

In Claude Code:

```
/create-specs
```

Then describe what you want, e.g.:

> Add a login screen to web-front with email + password fields. The backend already exposes `POST /api/auth/login` returning a JWT. The screen should show validation errors inline, redirect to `/dashboard` on success, and rate-limit the submit button to one request per second.

The Spec Analyzer asks clarifying questions if anything is ambiguous (it never invents domain rules), then writes a business spec under `{project-name}-docs/specs/Auth/login-screen-specs.md`. Open the spec and confirm it captures what you wanted; edit it directly if not.

## 2. Refine into technical spec + plan + task

```
/refine-specs
```

The Spec Analyzer reads:

- Your spec.
- The current state of the affected service repos.
- The lessons-learned files for that service category.
- `decisions.md` (your project's ADRs).

It produces three more files alongside the spec:

- `login-screen-plan.md` — the execution plan (phases, complexity classification, files to touch, Standards Scope).
- `login-screen-task.md` — the test requirements and Definition of Done checklist.
- An updated spec with `## Technical Details`.

Review the plan. The `Complexity:` line determines the execution flow:

- `simple` — one Dev+Tester agent does everything in a single session. No DoD-checker, optional Reviewer.
- `standard` — Dev → DoD-checker → Reviewer (loop) → Tester. The default for most features.
- `complex` — DevOps → Backend Dev ‖ Frontend Dev → DoD-checkers ‖ → Reviewers ‖ → Tester. Used when the feature touches multiple services.

## 3. Run the pipeline

```
/build-plan
```

The orchestrator:

1. Asks you to confirm the spec is correct (one human gate).
2. Pre-flight checks every affected repo is on `master`.
3. Creates feature branches in every affected repo.
4. Generates two per-phase bundles (`dev-bundle.md` for Developer / DevOps, `tester-bundle.md` for Tester) — distilling only the rules this feature actually touches.
5. Spawns agents in sequence (or parallel where appropriate).
6. After every spawn, parses the agent's `## Status` block. If `blocked`, surfaces the agent's `## Open Questions` to you. If `failed`, stops with the failure reason. If `complete`, advances.
7. Runs the DoD-checker (Haiku tier) before invoking the Reviewer — verifies every `## Definition of Done` checkbox has an artefact on disk.
8. Runs the Reviewer loop (max 3 iterations). Each iteration uses [coverage-aware loading](/ai-standards/concepts/coverage-aware-loading/) — no defensive full-checklist reads.
9. Runs the Tester. Reads the developer's `## Quality-Gate Results` and skips re-running gates already reported clean.
10. Emits a per-phase token-cost table.
11. Asks you to confirm merge.

Typical wall-clock: 30-40 minutes for a `standard` feature. Typical cost: $5-15 per `/build-plan` run depending on the feature's surface area. See [Token economics](/ai-standards/concepts/token-economics/) for measured numbers.

## 4. Merge

The orchestrator opens PRs in every affected repo, including the docs repo (which now carries the updated spec, INDEX flip, and any lessons-learned entries). It uses `gh pr merge --squash --delete-branch` after CI confirms. You confirm once; the orchestrator handles every repo's merge ordering (producer-first when there's a cross-service dependency).

## 5. Review the cost report

At the end of every `/build-plan` run the orchestrator emits a per-phase token table (real `total_tokens` from each subagent, not estimates):

```text
Phase                    | Model   | Tool uses | Total tokens | Duration
Bundle generator         | sonnet  | 38        | ~111k        | 10m 38s
Backend Developer        | opus    | 98        | ~234k        | 15m 32s
DoD-checker              | haiku   | 35        | ~55k         | 1m 16s
Backend Reviewer         | sonnet  | 47        | ~84k         | 5m 19s
Tester                   | sonnet  | 42        | ~62k         | 4m 27s
update-specs             | opus    | 24        | ~110k        | 2m 31s
Total subagents          | —       | 284       | ~658k        | ~40 min
```

The orchestrator overhead (~200-400k Opus, not in the per-subagent total) is reported separately when measurable.

## What's next

- Read [pipeline](/ai-standards/concepts/pipeline/) for the agent flow visual.
- Read [coverage-aware loading](/ai-standards/concepts/coverage-aware-loading/) for the Reviewer's per-section read protocol.
- Browse the [agent reference](/ai-standards/reference/agents/spec-analyzer/) for what each agent does.
