## Precondition — base URL is REQUIRED

This command requires a base URL to audit (the text the developer types after `/check-web`).

**If the developer invoked `/check-web` with no URL (empty arguments), STOP immediately.**

Do not read any file, do not load standards, do not spawn the walker — context is not needed yet.

Respond with exactly this message and wait for the developer's reply:

> `/check-web` needs a base URL to audit. Re-run the command with the URL, for example:
> `/check-web http://localhost:3000`
>
> Optional flags: `--routes <file>` (explicit list), `--cookie key=value` (seed auth), `--max-depth N` (default 2), `--max-routes N` (default 50).
>
> The audit is read-only — it never submits forms or triggers destructive actions.

Only once the developer provides a non-empty URL, proceed with the rest of this file.

---

## Execution (only when a URL is present)

Read the file `ai-standards/commands/check-web-command.md` and follow its instructions exactly.

Before starting, also read:
- `ai-standards/standards/invariants.md` — non-negotiable rules
- `ai-standards/CLAUDE.md`
- `ai-standards/.workspace-config-path` — pointer to the project docs directory (single line, e.g. `../task-manager-docs`). Then read `{docs-dir}/workspace.md` — tells you where the `handoffs/` directory and the project docs live for this workspace.
- `ai-standards/agents/web-auditor-agent.md` — your agent's role definition
