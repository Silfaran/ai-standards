# Lessons Learned — Framework

Agent and orchestration mistakes about the **ai-standards framework itself** — not about any project that uses it. Once a lesson is promoted to a proper standard or command doc, remove it from here.

**Scope:** rules that apply across every project using ai-standards (agent prompts, checklist design, command flow, standards structure). Per-project lessons — bugs, gotchas or traps that only matter in a single product's codebase — live in that project's docs repo, under `{project-name}-docs/lessons-learned/` (see the path configured in `{project-docs}/workspace.md` under the `lessons-learned:` key; resolve `{project-docs}` from `../.workspace-config-path`).

**Keep this file short** — under 40 lines of entries. Each entry is one line. Long explanations belong in the standard, command doc or agent definition where the lesson gets promoted.

## Format

```
- [{agent|command}] {what went wrong} → {fix or rule to follow}
```

## Entries

<!-- Add new entries at the bottom. Remove when promoted to a standard. -->
