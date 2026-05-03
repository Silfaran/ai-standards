# {Feature Name} — Handoff from {Agent Role}

## Status

One of: `complete` | `blocked` | `failed` | `incomplete`. **Mandatory — first section.** The orchestrator parses this line to decide whether to advance to the next phase. Absent or unrecognised value is treated as `failed` (fail-loud safe default — never advance on missing signal).

| Value | Meaning | Orchestrator behaviour |
|---|---|---|
| `complete` | Agent finished, all artifacts written, ready for next phase | Advance to next phase |
| `blocked` | Agent hit ambiguity it could not resolve; `## Open Questions` populated; no destructive change made | Stop pipeline, surface Open Questions to human |
| `failed` | Agent ran into an error it could not recover (build broken, env missing, dependency unresolved, tool error) | Stop pipeline, report failure to human |
| `incomplete` | Agent reached turn / context budget before finishing all DoD items | Stop, ask human to decide retry vs accept-with-gaps |

## Status reason

One line. **Mandatory when `Status ≠ complete`.** Cite the specific blocker / failure / unfinished item (e.g. *"requirement DoD-7 contradicts spec § Authorization — see Open Questions"*, *"docker compose up failed: port 5432 in use"*, *"hit 200-tool-call budget after 18/22 DoD rows"*). Empty when `Status = complete`.

## Abstract

Five-line structured summary the **orchestrator** reads instead of scanning the full handoff for routing decisions. Mandatory. Robustness contract: parsing structured fields beats scanning prose. The detailed sections below are still authoritative for the next agent; the Abstract is an index, not a replacement.

```yaml
outcome: <1-line description of what this agent achieved or why it stopped>
verdict: <APPROVED | REQUEST_CHANGES | BLOCKED | n/a>   # only Reviewers + DoD-checker fill this; others use n/a
files: <N created, M modified, K deleted>               # raw counts only — full lists in §Files Created / §Files Modified
next_phase: <expected next agent role | "stop, surface to human" | "n/a">
open_questions: <integer count — 0 when none, otherwise N referring to the §Open Questions section>
```

Field semantics:

| Field | Used by orchestrator for |
|---|---|
| `outcome` | One-line context for terse phase-transition log + final report |
| `verdict` | Reviewer / DoD-checker routing — APPROVED → next phase, REQUEST_CHANGES → re-spawn upstream Dev with findings, BLOCKED → re-spawn Dev with gap list |
| `files` | Final commit message construction + sanity check vs §Files Created / §Files Modified counts |
| `next_phase` | Confirms the routing the orchestrator was about to take. A mismatch here is a fail-loud signal |
| `open_questions` | When `> 0`, the orchestrator deep-reads §Open Questions and surfaces verbatim to the human |

The orchestrator's selective-read protocol (build-plan-command.md § "Handoff reading protocol") uses the Abstract for default routing and only deep-reads the rest of the handoff when the Abstract triggers it (REQUEST_CHANGES → read findings; open_questions > 0 → read questions; final commit → read file lists + Key Decisions).

## Iteration

`iter 1` for the first handoff. Increment on every re-spawn (`iter 2`, `iter 3`, …). The Tester reads this to decide whether to re-run from scratch or trust prior pass results — see `agents/tester-agent.md` § "Quality-gate re-execution policy".

## Files Created

## Files Modified

## Quality-Gate Results

One line per gate with the tool's verbatim summary (PHPStan / PHP-CS-Fixer / PHPUnit / vue-tsc / ESLint / Prettier / npm test, as applicable). Mandatory for Developer / Dev+Tester / DevOps handoffs. Required by `agents/{backend,frontend}-developer-agent.md` § "Definition-of-Done verification gate" and validated downstream by the Tester's re-execution policy.

## DoD coverage

Verbatim copy of the task DoD with each row marked `✓` (passed), `✗` (failed), `⚠️ Tester scope` (row lives under `### Tester scope` of the task DoD — Developer defers to the Tester; mandatory mark for every test/Playwright row, never `✓`), or `⚠️` (other partial / blocked, with one-line reason). Mandatory for Developer / Dev+Tester / DevOps handoffs. The DoD-checker agent re-verifies every `✓` row by spot-check, carries `⚠️ Tester scope` rows forward without verification, and confirms `⚠️` (other) justifications. The Tester later re-marks every `⚠️ Tester scope` row in their own `## DoD coverage`. Iteration ≥ 2 must re-mark every row instead of carrying marks forward.

## Key Decisions

## For the Next Agent

## Open Questions
