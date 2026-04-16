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
   └── specs/
       └── INDEX.md
   ```
4. Generate `services.md` using the information provided — follow the template below
5. Generate `decisions.md` as an empty ADR log — the Spec Analyzer will populate it as features are built
6. Generate `design-decisions.md` as an empty frontend design log — the Frontend Developer will populate it as UI patterns are implemented
7. Generate `specs/INDEX.md` with an empty table — the Spec Analyzer will add rows as specs are created
8. Create `ai-standards/workspace.md` with the project paths — gitignored, read by all agents
9. Create `ai-standards/workspace.mk` with the service lists — gitignored, included by the Makefile for dynamic test targets
10. Report what was created and instruct the developer to run `/create-specs` for the first feature

## Output
- `{project-name}-docs/services.md` — project service catalog
- `{project-name}-docs/decisions.md` — architecture decision records (starts empty)
- `{project-name}-docs/design-decisions.md` — frontend design decisions (starts empty, populated by Frontend Developer)
- `{project-name}-docs/specs/INDEX.md` — specs quick-reference index (starts with empty table, populated by Spec Analyzer)
- `ai-standards/workspace.md` — local workspace config (gitignored), content:

```markdown
# Workspace

project: {project-name}
services: {project-name}-docs/services.md
specs: {project-name}-docs/specs/
decisions: {project-name}-docs/decisions.md
design-decisions: {project-name}-docs/design-decisions.md
```

- `ai-standards/workspace.mk` — Makefile variables (gitignored), content:

```makefile
BACKEND_SERVICES = {backend-service-1} {backend-service-2}
FRONTEND_SERVICES = {frontend-service-1} {frontend-service-2}
```

All agents read `ai-standards/workspace.md` to discover the project paths — no manual configuration needed.
The Makefile includes `workspace.mk` automatically — `make test` runs tests for all listed services.

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

All agents discover the project catalog by reading `{project-name}-docs/services.md`
at the workspace root — derived from the spec or plan file path currently being worked on.

`ai-standards/` contains no project-specific information.
All project documentation lives exclusively inside `{project-name}-docs/`.
