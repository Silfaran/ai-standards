## Precondition — spec target is OPTIONAL but must be resolved before loading context

The argument (spec file path or feature name) is optional. Resolve the target **before** reading any standards file:

- **If a target was provided**, proceed directly to the Execution section below.
- **If no target was provided**, do NOT read standards, invariants, CLAUDE.md, or any agent file yet. Read only the minimum needed to help the developer choose:
  1. `ai-standards/.workspace-config-path` → locate `{docs-dir}`
  2. `{docs-dir}/workspace.md` → locate the specs directory
  3. `{specs-dir}/INDEX.md` → list specs eligible for refine (status `Pending implementation` with empty Technical Details)

  Then show the eligible specs to the developer and ask which one to refine. **Stop and wait** — do not continue until they answer.

---

## Execution (only once a spec target is known)

Read the file `ai-standards/commands/refine-specs-command.md` and follow its instructions exactly.

Before starting, also read:
- `ai-standards/agents/spec-analyzer-agent.md` — your role definition
- `ai-standards/standards/invariants.md` — non-negotiable rules
- `ai-standards/CLAUDE.md`
- `ai-standards/.workspace-config-path` — pointer to the project docs directory (single line, e.g. `../task-manager-docs`). Then read `{docs-dir}/workspace.md` — tells you where services.md, specs, and decisions.md live for this workspace.
