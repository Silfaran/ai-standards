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

## The Abstract block (orchestrator's structured routing index)

Status alone is enough for the gate decision (advance / stop). For the rest of the orchestrator's routing — choosing the next phase, constructing re-spawn prompts, surfacing blockers to the human — Status is too coarse. The pass-5 audit added a structured `## Abstract` block right after `## Status reason` so the orchestrator can route on parsed fields instead of scanning the rest of the handoff prose.

The Abstract carries five fields:

```yaml
outcome: <1-line description of what the agent achieved or why it stopped>
verdict: <APPROVED | REQUEST_CHANGES | BLOCKED | n/a>
files: <N created, M modified, K deleted>
next_phase: <expected next agent role | "stop, surface to human" | "n/a">
open_questions: <integer count>
```

`verdict` is the routing-critical field for Reviewers and the DoD-checker. Other agents fill it `n/a`.

### Selective reading protocol (orchestrator-side)

The orchestrator does NOT read the full handoff after every phase transition. It reads:

- **Always**: `## Status` (1 line), `## Status reason` (1 line), `## Abstract` (~5-10 lines). ~10-30 lines per phase, ~1-3k tokens.
- **Conditionally** (only when the Abstract triggers it):
  - `Status: blocked` AND `open_questions > 0` → read `## Open Questions` and surface to human
  - `verdict: REQUEST_CHANGES` (Reviewer) → read `## Findings` / `## Change requests` to construct upstream Dev's next-iteration prompt
  - `verdict: BLOCKED` (DoD-checker) → read `## Gaps` to re-spawn upstream Dev
  - End-of-feature commit step → read `## Files Created` + `## Files Modified` + `## Key Decisions` for the commit message body

What the orchestrator never deep-reads as part of routing: `## Quality-Gate Results` (the Tester reads them directly via path), `## DoD coverage` (the DoD-checker validated them), `## Iteration` (orchestrator tracks independently), `## For the Next Agent` (this is for the next agent, not the orchestrator).

This protocol drops orchestrator-side handoff reading from ~30-120k tokens per /build-plan to ~10-40k. The next subagent still receives the full handoff via path reference — its own behaviour is unchanged. Only the orchestrator's reading workload changes.

### Why the Abstract is in addition to (not instead of) the detailed sections

The Abstract is an **index**, not a replacement. The detailed sections (Files Created, Files Modified, Quality-Gate Results, DoD coverage, Findings, Open Questions, Key Decisions) remain authoritative for the next agent, which still reads the full handoff via path reference in its own isolated context. This preserves the existing quality contract while removing waste from the orchestrator's reading layer.

### Enforcement

- **Smoke check 24** anchors `## Abstract` + the five field markers in the template, AND the *"Handoff reading protocol"* / *"Always read"* / *"Conditional deep-reads"* anchors in `commands/build-plan-command.md`. Without these the orchestrator regresses to full-handoff reads with no CI signal.
