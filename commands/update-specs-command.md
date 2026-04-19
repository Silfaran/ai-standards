# Command: update-specs

## Description
Compares the current specs with the actual implementation after a task is completed.
Updates the specs to accurately reflect what was built, keeping documentation coherent with the codebase.

Also closes the spec lifecycle: distills the execution artifacts (plan + task) into a
durable `## As-built notes` section inside the spec, then deletes (or archives) the
`-plan.md` / `-task.md` files so the specs folder does not grow unbounded across features.

If significant differences are found between the spec and the implementation, it warns the developer
that something may not have been implemented correctly before updating.

## Invoked by
- `/build-plan` (automatic — runs as the last step before deleting the handoffs directory)
- Developer (manual — see "When to run this manually" below)

## When to run this manually
`/build-plan` already calls `/update-specs` at the end of every successful run, so you rarely need
to invoke it by hand. Run it manually only when:

- You edited the implementation directly (outside `/build-plan`) and the spec is now stale.
- `/build-plan` aborted mid-run and the spec was never closed — re-run `/update-specs` pointing at
  the same spec so plan/task are properly distilled and retired.
- You need to refresh the `## As-built notes` after a later bugfix altered something documented
  there (rare — prefer a new `-fix-specs.md` feature for non-trivial changes).

## Agent
Spec Analyzer

## Input
- The spec file: `{project-name}-docs/specs/{Aggregate}/{feature-name}-specs.md`
- The plan file: `{project-name}-docs/specs/{Aggregate}/{feature-name}-plan.md` (if still present)
- The task file: `{project-name}-docs/specs/{Aggregate}/{feature-name}-task.md` (if still present)
- The implemented code across the affected services

## Steps
1. Read the existing spec, plan, and task files (if plan/task are already absent — e.g. a second
   run on the same feature — skip the distillation step and proceed from step 4).
2. Read the implemented code across all affected services.
3. Compare the spec with the actual implementation.
4. If significant differences are found:
   - Warn the developer with a detailed report of what differs and why it may indicate an issue.
   - Wait for the developer to confirm whether to update the spec or fix the implementation.
5. If differences are minor or the developer confirms the update:
   - Update the spec file to match the actual implementation.
   - Document the changes made and the reasoning behind them.
6. **Distill plan + task into the spec** — append (or replace, if already present) an
   `## As-built notes` section in the spec with the following subsections. Keep it tight: the goal
   is to preserve the non-obvious rationale that would otherwise be lost when plan/task are deleted,
   not to duplicate them.

   ```markdown
   ## As-built notes

   ### Complexity
   {simple | standard | complex} — {one-line rationale from the plan}.

   ### Scope boundaries
   {Bullet list of notable "files NOT to modify" or explicit exclusions from the plan that a
   future reader would otherwise have to re-derive. Omit if empty.}

   ### Deviations from the plan
   {Anything the developer changed on the fly vs the refined plan — added files, changed
   approach, skipped phases. Omit the section if none.}

   ### Tests added
   {Test suite deltas (e.g. "task-front 288 → 299 (+11)") plus a one-line summary of what the
   new tests cover. No per-test detail — the code is the source of truth.}

   ### Open follow-ups
   {Any known gaps, DevOps tasks not done, or TODOs left for later. Omit if none.}
   ```

7. **Retire plan + task** based on the complexity recorded in step 6:

   | Complexity | `-plan.md` | `-task.md` | INDEX.md marker |
   |---|---|---|---|
   | `simple`   | Delete | Delete | `Implemented` |
   | `standard` | Delete | Delete | `Implemented` |
   | `complex`  | Move to `specs/_archive/{feature-name}/` | Move to `specs/_archive/{feature-name}/` | `Implemented 📦` |

   Rationale: in `simple`/`standard` flows, the distilled `As-built notes` plus the code and git
   history are enough to reconstruct context. `complex` flows contain multi-agent orchestration
   rationale (parallelism, reviewer iterations, DevOps sequencing) worth preserving verbatim.

   If the developer has explicitly asked in the current session to keep plan/task (e.g. "don't
   delete, I want to review them"), honour that and skip this step — but still update INDEX.md.

8. **Update INDEX.md** — set the Status column to `Implemented` (or `Implemented 📦` if archived),
   append the implementation date in `Status` (`Implemented (YYYY-MM-DD)`), and verify the
   Summary column still reflects reality after step 5.

## Output
- Updated spec file reflecting the actual implementation, with an `## As-built notes` section.
- Plan and task files deleted (simple/standard) or moved under `specs/_archive/{feature-name}/` (complex).
- `INDEX.md` updated with final status and date.
- A diff report highlighting what changed between the original spec and the final implementation.
- Warnings if significant deviations from the original spec were detected.

### Token Usage Report
After completing, list the files you read and display: `Estimated input tokens: ~{lines_read × 8}`
