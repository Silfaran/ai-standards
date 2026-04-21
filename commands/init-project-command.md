# Command: init-project

## Description
Initializes the documentation structure for a new project.
Creates the `{project-name}-docs/` folder at the workspace root and generates
the `services.md` file that all agents will use to understand the project's architecture.

Once initialized, the project is ready to receive specs created with `create-specs`.

## Invoked by
Developer

## Agent
Spec Analyzer

## Input
The developer provides:
- **Project name** — used as the folder prefix (e.g. `task-manager` → `task-manager-docs/`)
- **List of services** — for each service: name, type (Backend/Frontend), and responsibility

Example input:
> "Project: task-manager. Services: login-service (Backend, auth and JWT), login-front (Frontend, login UI),
> task-service (Backend, boards and tasks), task-front (Frontend, main app UI)"

## Steps
1. Ask the developer for the project name and list of services if not already provided
2. Check that `{project-name}-docs/` does not already exist at the workspace root — if it does, warn and stop
3. Create the folder structure:
   ```
   {project-name}-docs/
   ├── services.md
   ├── decisions.md
   ├── design-decisions.md
   ├── workspace.md            ← local workspace config, read by all agents
   ├── workspace.mk            ← Makefile variables (service lists) included by ai-standards/Makefile
   ├── lessons-learned/
   │   ├── README.md
   │   ├── general.md
   │   ├── back.md
   │   ├── front.md
   │   └── infra.md
   └── specs/
       └── INDEX.md
   ```
4. Generate `services.md` using the information provided — follow the template below
5. Generate `decisions.md` as an empty ADR log — the Spec Analyzer will populate it as features are built
6. Generate `design-decisions.md` as an empty frontend design log — the Frontend Developer will populate it as UI patterns are implemented
7. Generate `lessons-learned/` with a `README.md` (scope + format + agent-to-file mapping) plus empty `general.md` / `back.md` / `front.md` / `infra.md` — `/build-plan` appends to these after each feature
8. Generate `specs/INDEX.md` with an empty table — the Spec Analyzer will add rows as specs are created
9. Generate `{project-name}-docs/workspace.md` with the project paths (template below) — lives in the docs repo so `ai-standards/` stays project-neutral
10. Generate `{project-name}-docs/workspace.mk` with the service lists (template below) — included by the `ai-standards/` Makefile via the pointer file
11. Create the pointer file `ai-standards/.workspace-config-path` — a single line containing `../{project-name}-docs` (relative to the ai-standards repo). Gitignored. This is how the `ai-standards/` Makefile and every agent locates the project docs repo.
12. **Install the Agent model-tier enforcement hook** — merge `ai-standards/templates/agent-model-hook.json` into `{workspace-root}/.claude/settings.json`. This hook rejects any `Agent` tool invocation that does not include an explicit `model` argument, guaranteeing every subagent runs on the tier declared in its `## Model` section (see `CLAUDE.md` → "Agent model tiering").

    Run this from the workspace root (the directory containing `ai-standards/` and `{project-name}-docs/`):

    ```bash
    mkdir -p .claude
    TARGET=".claude/settings.json"
    TEMPLATE="ai-standards/templates/agent-model-hook.json"
    if [ -f "$TARGET" ]; then
      jq -s '
        .[0] as $existing | .[1].hooks.PreToolUse[0] as $new_hook |
        $existing
        | .hooks //= {}
        | .hooks.PreToolUse //= []
        | .hooks.PreToolUse = (.hooks.PreToolUse | map(select(.matcher != "Agent")) + [$new_hook])
      ' "$TARGET" "$TEMPLATE" > "$TARGET.tmp" && mv "$TARGET.tmp" "$TARGET"
    else
      cp "$TEMPLATE" "$TARGET"
    fi
    ```

    The merge is idempotent: running it twice leaves a single `Agent` hook entry, and any existing hooks for other matchers (Bash, Write, etc.) are preserved. After install, verify with `jq '.hooks.PreToolUse[] | select(.matcher == "Agent")' .claude/settings.json`.

13. Report what was created and instruct the developer to run `/create-specs` for the first feature

## Output
- `{project-name}-docs/services.md` — project service catalog
- `{project-name}-docs/decisions.md` — architecture decision records (starts empty)
- `{project-name}-docs/design-decisions.md` — frontend design decisions (starts empty, populated by Frontend Developer)
- `{project-name}-docs/lessons-learned/` — per-project agent mistakes, split by category (starts empty, populated by `/build-plan`)
- `{project-name}-docs/specs/INDEX.md` — specs quick-reference index (starts with empty table, populated by Spec Analyzer)
- `{project-name}-docs/workspace.md` — local workspace config (lives in the docs repo, read by every agent), content:

```markdown
# Workspace

project: {project-name}
services: {project-name}-docs/services.md
specs: {project-name}-docs/specs/
decisions: {project-name}-docs/decisions.md
design-decisions: {project-name}-docs/design-decisions.md
lessons-learned: {project-name}-docs/lessons-learned/
handoffs: handoffs/
```

All paths are **workspace-root-relative** (the folder that contains `ai-standards/` and `{project-name}-docs/`). The `handoffs:` directory is used by `/build-plan` for ephemeral per-feature handoff files (context bundle, developer/reviewer/tester handoffs, screenshots). It lives at the workspace root — outside any service repo — and is deleted after each feature completes. Do not commit it anywhere.

- `{project-name}-docs/workspace.mk` — Makefile variables (lives in the docs repo, included by `ai-standards/Makefile`), content:

```makefile
BACKEND_SERVICES = {backend-service-1} {backend-service-2}
FRONTEND_SERVICES = {frontend-service-1} {frontend-service-2}
```

- `ai-standards/.workspace-config-path` — pointer file (gitignored — per-workspace), single line:

```
../{project-name}-docs
```

- `{workspace-root}/.claude/settings.json` — created or updated with the `Agent` `PreToolUse` hook that enforces the model tier declared in each agent definition. See `ai-standards/templates/agent-model-hook.json` for the source fragment.

### How lookup works

Every agent and the `ai-standards/Makefile` discover the project config via the pointer file:

1. Read `ai-standards/.workspace-config-path` → get `{docs-dir}` (relative to `ai-standards/`).
2. Read `{docs-dir}/workspace.md` for paths, or include `{docs-dir}/workspace.mk` in Make.

This keeps `ai-standards/` 100% project-neutral — the public framework repo stores only a pointer to the project, never the project's own config.

## services.md template

```markdown
# {Project Name} — Services

## Documentation
Specs, plans and tasks: `{project-name}-docs/specs/{Aggregate}/`

## Architecture

\`\`\`
ai-standards/           ← global standards and AI configuration
{service-1}/            ← description
{service-2}/            ← description
\`\`\`

## Service Responsibilities

| Service | Type | Responsibility |
|---|---|---|
| `{service-1}` | Backend (Symfony) | ... |
| `{service-2}` | Frontend (Vue 3) | ... |
```

## Convention

All agents discover the project catalog by reading `{project-name}-docs/workspace.md`, and `services.md` from the path it declares.

`ai-standards/` contains no project-specific information — only the pointer file `.workspace-config-path` (gitignored) telling the framework where the current project's docs repo is. Every piece of project documentation, config, and state lives exclusively inside `{project-name}-docs/`.
