## Precondition — business description is REQUIRED

This command requires a business description of the feature as argument (the text the developer types after `/create-specs`).

**If the developer invoked `/create-specs` with no description (empty arguments), STOP immediately.**

Do not read any file, do not load standards, do not inspect the workspace — reading context before knowing the feature wastes tokens and pollutes the conversation.

Respond with exactly this message and wait for the developer's reply:

> `/create-specs` needs a business description of the feature to create the spec. Re-run the command with the description, for example:
> `/create-specs I want users to be able to invite other users to a board by email`
>
> No technical details are needed — just describe in business terms what should be built.

Only once the developer provides a non-empty description, proceed with the rest of this file.

---

## Execution (only when a description is present)

Read the file `ai-standards/commands/create-specs-command.md` and follow its instructions exactly.

Before starting, also read:
- `ai-standards/standards/invariants.md` — non-negotiable rules
- `ai-standards/CLAUDE.md`
- `ai-standards/.workspace-config-path` — pointer to the project docs directory (single line, e.g. `../task-manager-docs`). Then read `{docs-dir}/workspace.md` — tells you where services.md and specs live for this workspace.
- `ai-standards/agents/spec-analyzer-agent.md` — your role definition
