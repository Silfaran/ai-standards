# How to use AI Standards

## Prerequisites

- [Claude Code](https://claude.ai/code) installed and running
- A workspace folder that will contain all your project's services

---

## Setup (once per workspace)

**1. Clone this repo into your workspace:**
```
workspace/
└── ai-standards/    ← clone here
```

**2. Copy the commands folder to your workspace root:**
```bash
cp -r ai-standards/.claude/commands .claude/commands
```

This makes all commands available as slash commands in Claude Code (e.g. `/init-project`, `/create-specs`).

**3. Initialize your project:**
```
/init-project
```
The agent will ask for your project name and list of services, then create:
```
workspace/
├── ai-standards/
│   └── workspace.md     ← local config (gitignored) — all agents read this
├── {project-name}-docs/
│   └── services.md      ← your project catalog
└── (your services...)
```

`workspace.md` is the single source of truth for project paths. All agents read it automatically — no manual configuration needed.

Every service you create must have a `CLAUDE.md` pointing to `ai-standards`. Use this as the template:
```markdown
## Standards
Read `ai-standards/CLAUDE.md` and the relevant `ai-standards/standards/*.md` before doing anything.
```

---

## Building a feature

Every feature follows the same four-step flow:

### 1. `/create-specs`
Describe the feature in plain business language. No technical details needed.

> "I want users to invite others to a board by email"

The agent asks clarifying questions, warns about incompatibilities, and creates:
```
{project-name}-docs/specs/{Aggregate}/{feature-name}-specs.md
```

### 2. `/refine-specs`
Point to the spec file created in step 1. The agent reads the codebase, fills in technical details, and produces:
```
{feature-name}-specs.md   ← updated with architecture decisions
{feature-name}-plan.md    ← execution plan with agent phases
{feature-name}-task.md    ← Definition of Done checklist
```

### 3. `/build-plan`
Point to the plan file. The agent orchestrates the full implementation:
- Spawns isolated subagents per phase
- Runs Backend + Frontend in parallel
- Runs reviewers in parallel, loops until approved
- Runs tests, loops until they pass

### 4. `/update-specs`
Point to the spec file. The agent compares spec vs actual implementation and updates the spec to match.

---

## Commands reference

| Command | When to use |
|---|---|
| `/init-project` | Once, when starting a new project |
| `/create-specs` | When you have a new feature to build |
| `/refine-specs` | After create-specs, to produce the technical spec and plan |
| `/build-plan` | After refine-specs, to implement the full feature |
| `/update-specs` | After build-plan, to keep specs in sync with the code |

---

## Workspace structure (after setup)

```
workspace/
├── .claude/
│   └── commands/          ← slash commands (copied from ai-standards/.claude/commands/)
├── ai-standards/          ← this repo (standards, agents, commands)
├── {project-name}-docs/
│   ├── services.md        ← project service catalog
│   └── specs/
│       └── {Aggregate}/
│           ├── {feature}-specs.md
│           ├── {feature}-plan.md
│           └── {feature}-task.md
├── {service-1}/           ← your backend/frontend services
├── {service-2}/
└── ...
```

---

## Standards reference

| File | What it governs |
|---|---|
| `standards/backend.md` | PHP/Symfony: architecture, patterns, testing |
| `standards/frontend.md` | Vue 3/TS: composables, stores, services, testing |
| `standards/logging.md` | Structured logs, Monolog config |
| `standards/security.md` | Headers, CORS, JWT, rate limiting |
| `standards/new-service-checklist.md` | Pre-commit checklist for new services |
