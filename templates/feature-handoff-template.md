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

## Iteration

`iter 1` for the first handoff. Increment on every re-spawn (`iter 2`, `iter 3`, …). The Tester reads this to decide whether to re-run from scratch or trust prior pass results — see `agents/tester-agent.md` § "Quality-gate re-execution policy".

## Files Created

## Files Modified

## Quality-Gate Results

One line per gate with the tool's verbatim summary (PHPStan / PHP-CS-Fixer / PHPUnit / vue-tsc / ESLint / Prettier / npm test, as applicable). Mandatory for Developer / Dev+Tester / DevOps handoffs. Required by `agents/{backend,frontend}-developer-agent.md` § "Definition-of-Done verification gate" and validated downstream by the Tester's re-execution policy.

## DoD coverage

Verbatim copy of the task DoD with each row marked `✓` (passed), `✗` (failed), or `⚠️` (partial / blocked). Mandatory for Developer / Dev+Tester / DevOps handoffs. The DoD-checker agent re-verifies every `✓` row by spot-check; iteration ≥ 2 must re-mark every row instead of carrying marks forward.

## Key Decisions

## For the Next Agent

## Open Questions
