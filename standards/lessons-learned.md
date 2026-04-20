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
- [command] Playwright MCP has no native HAR export, so measurement specs that mandate HAR artifacts are unfulfillable as-written → accept the `browser_network_requests` + `performance.getEntriesByType(...)` JSON pair as the canonical substitute; consider updating measurement command templates to name the JSON pair rather than HAR.
- [agent] When the Backend Reviewer checklist is silent on a naming-style rule that contradicts a project's PHP-CS-Fixer config (e.g. `php_unit_method_casing` forcing camelCase test names while a standards file still reads `snake_case`), the hard-blocker "PHP-CS-Fixer passes" wins by construction — do not reject on the style-guide wording. Flag the gap as a `minor` checklist-update recommendation and keep moving.
- [agent] Application-vs-Domain service placement has one decisive signal: a class that injects `Doctrine\DBAL\Connection` is Application by construction — Domain services may never hold a `Connection`. Same for injecting `MessageBusInterface` or any other transactional/side-effect primitive. Use this as a fast disambiguator during Architecture-section review rather than re-deriving from the decision rule every time.
