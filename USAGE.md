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

**2. Copy the commands and skills folders to your workspace root:**
```bash
cp -r ai-standards/.claude/commands .claude/commands
cp -r ai-standards/.claude/skills   .claude/skills
```

- `commands/` makes all slash commands available in Claude Code (e.g. `/init-project`, `/create-specs`).
- `skills/` gives agents on-demand access to narrow playbooks (CORS setup, safe migrations, JWT lifecycle, Vitest patterns, etc.). Claude auto-loads each skill only when it matches the file or task at hand — zero cost when not needed. See [skills reference](#skills-reference) below.

Re-run the `cp` commands when ai-standards updates its skills or commands. For a live link (edits in ai-standards instantly reflected), replace `cp -r` with a symlink: `ln -s ../ai-standards/.claude/skills .claude/skills`.

**3. Initialize your project:**
```
/init-project
```
The agent will ask for your project name and list of services, then create:
```
workspace/
├── ai-standards/
│   └── workspace.md          ← local config (gitignored) — all agents read this
├── {project-name}-docs/
│   ├── services.md           ← your project catalog
│   ├── decisions.md          ← architecture decisions (populated by Spec Analyzer)
│   ├── design-decisions.md   ← frontend design decisions (populated by Frontend Developer)
│   ├── workspace.md          ← local workspace config — all agents read this
│   ├── workspace.mk          ← Makefile variables (service lists)
│   └── lessons-learned/      ← per-project agent mistakes, split by back.md / front.md / infra.md / general.md
└── (your services...)
```

`{project-name}-docs/workspace.md` is the single source of truth for project paths. Every agent discovers it via the pointer file `ai-standards/.workspace-config-path` (gitignored, one line — created by `/init-project`). That pointer is the only project-specific file inside `ai-standards/`; everything else lives in the docs repo.

Every service you create must have a `CLAUDE.md` pointing to `ai-standards`. Use this as the template:
```markdown
## Standards
Read `ai-standards/CLAUDE.md` and the relevant `ai-standards/standards/*.md` before doing anything.
```

**4. Install Playwright MCP (enables live browser verification by the Tester):**

The Tester agent drives a real browser — via the [Playwright MCP server](https://github.com/microsoft/playwright-mcp) — to verify visual and interactive DoD items (full-viewport gradients, rendered error copy, light/dark parity, viewport-size checks). Without it, those items fall back to "requires human verification" and slow down every `/build-plan` loop.

Create `.mcp.json` at your **workspace root** (the folder that contains `ai-standards/` and your services — not inside any repo):

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest"]
    }
  }
}
```

Then reload Claude Code (close and reopen the session). On first use, `npx` downloads `@playwright/mcp` and Chromium (~150 MB, one-time). Verify with `/mcp` inside Claude Code — `playwright` should appear as connected.

The workspace root is intentionally outside version control in this layout, so this step is per-machine. If you set up a second machine (or a teammate joins), re-run step 4 there. The Tester agent definition (`agents/tester-agent.md`) and `build-plan` command already assume Playwright MCP is available and will instruct the subagent accordingly.

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

## Make commands (workspace-level)

The root `Makefile` in `ai-standards/` orchestrates every service in the workspace using the `BACKEND_SERVICES` and `FRONTEND_SERVICES` lists from `{project-name}-docs/workspace.mk` (generated by `/init-project`; located via the `.workspace-config-path` pointer file). Run these from the `ai-standards/` directory.

### Lifecycle

| Command | What it does |
|---|---|
| `make infra-up` | Starts shared infrastructure only (PostgreSQL, RabbitMQ, Mailpit) |
| `make infra-down` | Stops shared infrastructure |
| `make up` | Starts infrastructure first, then every service (`docker compose up -d`) |
| `make down` | Stops every service, then the infrastructure |
| `make build` | Rebuilds all service images |
| `make update` | `make build` + `make up` (use after changing `composer.json`, `Dockerfile`, or any file in the Docker build context) |

### Observability

| Command | What it does |
|---|---|
| `make ps` | Shows container status for infrastructure + all services |
| `make logs` | Tails infrastructure logs |

### Tests

| Command | What it does |
|---|---|
| `make test` | Unit + integration on every service |
| `make test-unit` | Unit tests only |
| `make test-integration` | Backend integration tests only (frontends don't have integration tier) |

### Quality gates

| Command | What it does |
|---|---|
| `make lint` | PHP-CS-Fixer dry-run (backends) + ESLint + Prettier check (frontends) |
| `make static` | PHPStan level 9 (backends) + `vue-tsc --noEmit` (frontends) |
| `make quality` | `lint` + `static` + `test` — the full gate bar across the workspace |

Run `make quality` before a push. See [`standards/quality-gates.md`](standards/quality-gates.md) for the full rules and [`templates/`](templates/) for the installable CI / hook / Makefile assets per service.

### What's NOT in the root Makefile

Per-service commands — `make lint`, `make static`, `make quality` — also exist **inside each service directory** after you install the quality snippets. The root targets iterate over services; the per-service targets run directly via `docker compose exec`.

---

## Workspace structure (after setup)

```
workspace/
├── .claude/
│   ├── commands/          ← slash commands (copied from ai-standards/.claude/commands/)
│   └── skills/            ← on-demand playbooks (copied from ai-standards/.claude/skills/)
├── ai-standards/          ← this repo (standards, agents, commands, skills) + `.workspace-config-path` pointer
├── {project-name}-docs/
│   ├── services.md           ← project service catalog
│   ├── decisions.md          ← architecture decisions (Spec Analyzer)
│   ├── design-decisions.md   ← frontend design decisions (Frontend Developer)
│   ├── workspace.md          ← workspace config — path source of truth for agents
│   ├── workspace.mk          ← Makefile variables (BACKEND_SERVICES, FRONTEND_SERVICES)
│   ├── lessons-learned/      ← per-project agent mistakes (back / front / infra / general)
│   │   ├── README.md
│   │   ├── general.md
│   │   ├── back.md
│   │   ├── front.md
│   │   └── infra.md
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

Standards are split into **rules** (concise, always loaded by agents) and **reference** (full examples, loaded conditionally).

| File | What it governs |
|---|---|
| `standards/invariants.md` | Non-negotiable rules — read first by all agents |
| `standards/backend.md` | PHP/Symfony: architecture rules (concise) |
| `standards/backend-reference.md` | Full code examples, configs, scaffold usage |
| `standards/frontend.md` | Vue 3/TS: rules (concise) |
| `standards/frontend-reference.md` | Full code examples, test patterns |
| `standards/logging.md` | Structured logs, Monolog config |
| `standards/security.md` | Headers, CORS, JWT, rate limiting |
| `standards/performance.md` | Database, API, and frontend performance |
| `standards/new-service-checklist.md` | Pre-commit checklist for new services |
| `standards/lessons-learned.md` | Framework-level agent mistakes only (orchestration, checklist design). Per-project mistakes live in `{project-name}-docs/lessons-learned/` |
| `standards/tech-stack.md` | Authoritative versions (minimums, open to update) + upgrade procedure |
| `standards/agent-reading-protocol.md` | Canonical reading order for every agent (build-plan + standalone modes) |
| `standards/quality-gates.md` | CI + pre-commit + Makefile quality rules (PHPStan L9, vue-tsc, tests) |
| `scaffolds/` | Copy-verbatim PHP classes (AppController, etc.) |
| `templates/ci/` | GitHub Actions workflow templates (backend + frontend) |
| `templates/hooks/` | Git pre-commit hooks (backend + frontend) |
| `templates/makefile/` | Makefile quality snippets to drop into a service Makefile |
| `.claude/skills/` | On-demand playbooks (see below) |

---

## Skills reference

Skills are narrow, auto-loading playbooks. Claude reads only each skill's `description` at session start (cheap) and loads the full body only when the active task matches. This replaces reading big reference files end-to-end.

| Skill | Activates when |
|---|---|
| `cors-nelmio-configuration` | Configuring NelmioCorsBundle, adding a new frontend origin, debugging CORS preflight failures |
| `docker-env-reload` | Editing `.env` / `env_file`; when env-var changes aren't taking effect in a running container |
| `docker-frontend-deps-sync` | Running `npm install`, adding/removing packages in a Dockerized Vue/Vite frontend |
| `shadcn-vue-component-add` | Before/after `npx shadcn-vue add <component>` — to catch silent overwrites of unrelated files |
| `new-service-bootstrap` | Scaffolding a new PHP/Symfony service (Kernel, bundles, routes, Flex cleanup, composer.lock sync) |
| `doctrine-migration-safe` | Writing a Phinx migration — tables, columns, indexes, safe ALTER patterns |
| `symfony-messenger-async` | Configuring buses, RabbitMQ transports, cross-service message contracts, consumer workers |
| `messenger-logging-middleware` | Wiring LoggingMiddleware, configuring Monolog JSON-to-stdout, sensitive field redaction |
| `jwt-security` | Implementing JWT auth, refresh-token rotation, httpOnly cookie storage, Lexik config |
| `rate-limiting-auth` | Adding Symfony RateLimiter to login/register/password-reset/token-refresh endpoints |
| `vue-composable-mutation` | Writing a Vue 3 composable with TanStack Query `useMutation` for write operations |
| `vitest-composable-test` | Writing Vitest tests for composables, stores, pages (mocks, captured callbacks, jsdom shims) |
| `quality-gates-setup` | Installing CI workflow, pre-commit hook, and Makefile quality targets in a new or existing service |

All skills can also be invoked manually with `/skill-name`. See each skill's `SKILL.md` for the full content.
