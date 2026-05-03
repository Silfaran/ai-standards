---
title: Smoke checks
description: Static framework self-checks that run on every push — 25 hard checks plus a non-fatal staleness reminder.
---

`scripts/smoke-tests.sh` runs on every push to `master` (via `.github/workflows/validate.yml`) and locally via `make smoke`. It catches framework regressions that markdownlint and link-checking cannot.

The checks are deliberately mechanical — no LLM calls, deterministic, fast. They run in seconds.

## Catalog

| # | Check | Anchors |
|---|---|---|
| 1 | Agent model tier | Every `agents/*.md` declares `## Model` with `Opus`, `Sonnet`, or `Haiku` |
| 2 | Command → agent wiring | Agent paths cited in `commands/*.md` resolve to real files |
| 3 | Skill name ↔ folder | Every `.claude/skills/<name>/SKILL.md` `name:` matches its folder |
| 4 | Docs path references | Backtick-wrapped paths in CLAUDE.md / USAGE.md / README.md / ARCHITECTURE.md exist |
| 5 | CLAUDE.md index coverage | Every primary standard is listed in CLAUDE.md (silent-orphan detector) |
| 6 | Standards ↔ agent-reading-protocol coverage | Every primary standard appears in `agent-reading-protocol.md` |
| 7 | Reviewer checklist rule IDs | Format + uniqueness + prefix legality |
| 8 | Cross-rule references | Rule IDs cited across `standards/*.md` resolve to declared bullets |
| 9 | Critical-path rule IDs | Rule IDs cited in `standards/critical-paths/*.md` resolve to declared bullets |
| 10 | Per-phase bundle path coherence | `dev-bundle.md` + `tester-bundle.md` cited in build-plan + agent-reading-protocol |
| 11 | DoD-checker phase wiring | `DoD-checker` mentioned ≥5× in build-plan + Haiku tier in flow table |
| 12 | Reviewer fast-mode coherence | Both reviewer agents declare `## Fast re-review mode` + `## Re-review mode` markers |
| 13 | Quality-gate trust contract | Tester `## Quality-gate re-execution policy` + Devs `## Quality-Gate Results` + `## DoD coverage` |
| 14 | Three invocation modes | `agent-reading-protocol.md` declares Mode A + Mode B + Mode C |
| 15 | Critical paths coverage + triggers | Every critical path declares `## Coverage map vs full checklist` + PRIMARY/SECONDARY/DO NOT load |
| 16 | Reviewer gap-citation enforcement | Both reviewer agents retain *"rejected as defensive overhead"* + *"cite the gap"* |
| 17 | DoD-checker tool-call budget | `agents/dod-checker-agent.md` declares its tool-call budget per row |
| 18 | build-plan anti-duplication rule | `commands/build-plan-command.md` retains the "Anti-duplication rule for both bundles" + "Do NOT reproduce spec content" |
| 19 | Handoff template contract sections | `templates/feature-handoff-template.md` declares `## Iteration` + `## Quality-Gate Results` + `## DoD coverage` |
| 20 | Dynamic-smoke fixture rule-prefix coverage | `tests/expected/standard.json` regex carries the full 23-prefix alternation |
| 21 | Handoff Status block contract | `templates/feature-handoff-template.md` declares `## Status` with the 4 values + `## Status reason`; orchestrator gate prose intact |
| 22 | Bundle generator cheap-extraction protocol | `commands/build-plan-command.md` declares the index → offset+limit → 4+sections fallback |
| 23 | Docs site sync coverage | `docs/scripts/sync.mjs` covers every content category the Astro Starlight sidebar renders |
| 24 | Handoff Abstract + selective reading protocol | Template declares `## Abstract` with 5 fields + `commands/build-plan-command.md` retains *"Handoff reading protocol"* / *"Always read"* / *"Conditional deep-reads"* |
| 25 | Test-ownership contract | `feature-task-template.md` declares `### Tester scope` partition + dev agents declare `⚠️ Tester scope` mark + Tester agent owns the contract + DoD-checker carries `⚠️ Tester scope` rows forward without verification |
| 26 | Dynamic smoke staleness | Non-fatal — reminds when structural files changed since last release without `make smoke-dynamic` running |

## Why these specifically

Each check anchors a load-bearing pattern that, if silently removed, would degrade framework behaviour without breaking any other test:

- **Coherence checks (1-9)** — catch broken cross-references between agents / commands / standards / checklists / critical paths. Each was added in response to a real drift incident.
- **v0.40.0 contract checks (10-14)** — lock the per-phase bundle split, DoD-checker wiring, fast re-review mode, quality-gate trust contract, and three-invocation-mode declaration introduced in PR #98.
- **Coverage-aware checks (15-18)** — lock the wins of PRs #100/#102/#104 (critical-paths structure, gap citation, DoD-checker budget, anti-duplication).
- **Pass-3 + pass-4 checks (19-22)** — lock the handoff template contract (PR #108), the rule-prefix regex alignment (PR #108), the Status block (PR #112), and the cheap-extraction protocol (PR #112).
- **Public site + pass-5 checks (23-24)** — lock the docs site auto-sync (PR #117) and the orchestrator's selective-reading Abstract (PR #119).
- **Test-ownership check (25)** — lock the partitioned DoD + `⚠️ Tester scope` mark introduced to remove Dev/Tester duplication on test rows. See [Test ownership](/concepts/test-ownership/).
- **Staleness reminder (26)** — non-fatal hint that the dynamic smoke (real subagent runs) has not been exercised since the last release; CI stays green either way.

## Dynamic smoke

`make smoke-dynamic` (separate from the static suite above) runs the orchestrator against three fixture projects (`standard`, `simple`, `complex`) and asserts on the captured first-Agent-spawn shape. `make smoke-dynamic-full` runs the entire pipeline against the `standard` fixture with real subagents — the only test that exercises the live orchestrator behaviour end-to-end. Both are token-billed (real Claude API calls), so they are local-only and not run on CI.

See [`tests/README.md`](https://github.com/Silfaran/ai-standards/blob/master/tests/README.md) for the harness details.
