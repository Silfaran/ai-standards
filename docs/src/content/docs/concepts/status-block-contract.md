---
title: The Status block contract
description: How handoffs signal success, failure, and ambiguity to the orchestrator — a four-value Status block at the top of every handoff with fail-loud safe defaults.
---

Every handoff produced by a subagent starts with a `## Status` block. The orchestrator parses it before reading anything else and decides whether to advance, stop, or escalate.

## The four values

| Value | Meaning | Orchestrator behaviour |
|---|---|---|
| `complete` | Agent finished, all artefacts written, ready for next phase | Advance to next phase |
| `blocked` | Agent hit ambiguity it could not resolve; `## Open Questions` populated; no destructive change made | Stop pipeline, surface Open Questions to human |
| `failed` | Agent ran into an error it could not recover (build broken, env missing, dependency unresolved, tool error); `## Status reason` populated | Stop pipeline, report failure to human |
| `incomplete` | Agent reached turn / context budget before finishing all DoD items; `## Status reason` populated | Stop, ask human (retry vs accept-with-gaps vs abort) |

If the value is **absent or unrecognised**, the orchestrator treats the handoff as `failed` — fail-loud safe default. Never advance on missing signal.

## Why this exists

Before this contract, the orchestrator could not reliably detect a subagent failure. *"Subagent returns an error → stop"* was the entire contract. Whether the subagent actually succeeded was inferred from prose. A subagent that:

- Hit its turn budget mid-run, or
- Crashed after `Write` but before fully populating the handoff, or
- Ran cleanly but produced a handoff whose required sections were truncated

… all left a file on disk that the orchestrator treated as success and fed to the next phase. The DoD-checker partially mitigated this for `## DoD coverage` validation, but did not cover *"did the developer crash?"*.

The Status block makes failure explicit and machine-readable. Every subagent declares its run-health; the orchestrator routes deterministically.

## Independent of semantic verdicts

`Status` is the agent's own self-report of run health. It is independent of any semantic verdict the agent might also produce.

The DoD-checker, for example, has its own `## Verdict: APPROVED | BLOCKED` field — that is a semantic verification of the developer's work. A clean DoD-checker run can be `Status: complete` AND `Verdict: BLOCKED`: the gate ran successfully AND validated that the developer's work has gaps. Both signals are needed.

Same for the Reviewer: `Status: complete` is independent of `APPROVED` vs `REQUEST_CHANGES`. A Reviewer that finished cleanly with `REQUEST_CHANGES` has `Status: complete`.

## Status reason

Required when `Status ≠ complete`. One line citing the specific blocker / failure / unfinished item:

- `blocked`: *"requirement DoD-7 contradicts spec § Authorization — see Open Questions"*
- `failed`: *"docker compose up failed: port 5432 in use"*
- `incomplete`: *"hit 200-tool-call budget after 18/22 DoD rows"*

Empty when `Status: complete`.

## Routing on `blocked`

When an agent emits `Status: blocked`, the orchestrator does NOT re-spawn it. The ambiguity needs human input. The orchestrator reads the agent's `## Open Questions` verbatim, surfaces it to the human, and waits.

This is the canonical way for subagents to ask the human a question. `AskUserQuestion` invoked inside a `/build-plan` subagent does NOT reach the human (subagents are isolated from the user); the documented escape hatch is `Status: blocked` + populated `## Open Questions`. See `agents/backend-developer-agent.md` and `agents/frontend-developer-agent.md` § Role for the full rule.

## Enforcement

- **Smoke check 21** verifies the canonical handoff template (`templates/feature-handoff-template.md`) declares `## Status` + the four values + `## Status reason`.
- **Smoke check 21** also verifies the orchestrator-side fail-loud prose (*"Absent / unrecognised"*) is intact in `commands/build-plan-command.md`.
- The Reviewer prompt template in `commands/build-plan-command.md` instructs every subagent to write the Status block first.
- Each agent's `## Output` section in its definition file declares the Status contract for its specific failure modes (e.g. Backend Developer's `failed` covers tool/env errors; Reviewer's `blocked` covers unreadable dev handoffs).

Together these anchors prevent silent regression: if any of them is dropped, CI fails on the smoke check.
