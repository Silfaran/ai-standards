# AI Standards — Architecture

This document explains how the framework is designed — the stack it enforces, the agent pipeline, the spec lifecycle, and the repository layout. For setup and day-to-day usage, see [USAGE.md](USAGE.md). For the short overview, see [README.md](README.md).

---

## Tech stack

This framework is opinionated. It enforces a specific stack and architecture.

The authoritative list of technologies, minimum versions and upgrade policy lives in [`standards/tech-stack.md`](standards/tech-stack.md) — all versions are minimums, open to newer compatible releases.

At a glance: PHP + Symfony on the backend, Vue 3 + TypeScript + Vite (with shadcn/ui) on the frontend, PostgreSQL as the database (one per service), RabbitMQ via Symfony Messenger for messaging, Docker for per-service containers and shared infrastructure.

Architecture patterns — Hexagonal, DDD, CQRS, Event-Driven — are enforced by standards, not suggested. Every agent validates against them.

---

## Recommended prior knowledge

The framework writes the code, but you review specs, approve architectural decisions, and resolve what the AI can't. The more of the list below you already know, the faster the feedback loop. Nothing here is a hard prerequisite — Claude can explain any of it on request — but the first three are what you actually need to drive the workflow.

**Needed to operate the framework:**
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) basics — slash commands, MCP configuration, context windows. The whole framework is slash commands on top of Claude Code.
- **Docker + docker compose** — every service runs in a container; you will `docker compose up`, read logs, and occasionally rebuild.
- **Git** — branches, merges, pushing. `/build-plan` creates feature branches and asks you to confirm merges.

**Needed to review what the agents produce:**
- **PHP / Symfony** — enough to read controllers, commands, handlers, and migrations. You don't need to write them from scratch.
- **Vue 3 + TypeScript + Vite** — enough to read `<script setup>` components, composables, and Pinia stores. Familiarity with shadcn/ui helps.
- **Hexagonal Architecture, DDD, CQRS, Event-Driven design** — at concept level. The standards enforce these; if they are unfamiliar, specs and reviews will feel arbitrary.
- **Markdown** — specs, plans, tasks, lessons-learned are all `.md` files you will read (and sometimes edit).

**Useful but optional:**
- **Make / Makefiles** — the workspace has `make up`, `make test`, `make quality`. If you can run them, you are fine — writing new targets is rare.
- **PostgreSQL** — only needed when debugging data or writing a migration; agents write the SQL themselves.
- **RabbitMQ / Symfony Messenger** — only if your project has cross-service events; otherwise you can ignore it.

---

## Spec lifecycle

Every feature produces three files under `{project-name}-docs/specs/{Aggregate}/`:

| File | Purpose | Lifespan |
|---|---|---|
| `{feature}-specs.md` | WHAT was built and WHY — the contract | Permanent. Read by future specs and agents. |
| `{feature}-plan.md`  | HOW to execute — phases, agents, files to touch | Ephemeral. Deleted by `/update-specs` on `simple`/`standard` complexity. Archived under `specs/_archive/{feature}/` on `complex`. |
| `{feature}-task.md`  | Test requirements and DoD checklist | Same as the plan. |

Before retirement, `/update-specs` distills the plan and task into an `## As-built notes` section appended to the spec (complexity rationale, scope boundaries, deviations, test deltas, open follow-ups). That keeps the non-obvious rationale addressable without leaving every historical plan/task file in the main specs folder. `/build-plan` calls `/update-specs` automatically — you only invoke it by hand if you edited the code outside `/build-plan` or need to re-close a spec after an aborted run. See [`commands/update-specs-command.md`](commands/update-specs-command.md).

---

## How it works

Six commands, each backed by specialized agents:

```
/create-specs     You describe a feature → Spec Analyzer writes a business spec
       │
       ▼
/refine-specs     Spec Analyzer reads the codebase → technical spec + execution plan + task checklist
       │
       ▼
/build-plan       Orchestrator spawns agents in sequence:
       │
       │   [Phase 1]  DevOps sets up infrastructure (only if needed)
       │   [Phase 2]  Backend Developer + Frontend Developer  (parallel)
       │   [Phase 3]  DoD-checker (Haiku) — mechanical task-DoD verification
       │   [Phase 4]  Backend Reviewer + Frontend Reviewer    (parallel, up to 3 rounds each)
       │   [Phase 5]  Tester writes and runs all tests
       │
       ▼
/update-specs     Spec Analyzer syncs the spec with the final implementation
```

Two more commands sit outside the build-plan loop:

```
/init-project     One-time setup — wires the workspace, hooks, and project docs
/check-web        Manual audit — Playwright walks the running UI and the Web Auditor
                  produces paste-ready /create-specs prompts grouped by inferred root cause
```

Backend and Frontend run in parallel — independent codebases, independent review loops. The Tester runs once against the final, reviewed code. The framework adapts the execution flow to feature complexity: simple features use fewer agents; complex multi-service features use the full pipeline with parallel phases.

---

## Agents

Nine agents, each with a single responsibility and an isolated context window:

| Agent | Does | Doesn't |
|---|---|---|
| [Spec Analyzer](agents/spec-analyzer-agent.md) | Translates business descriptions into technical specs, flags cross-service incompatibilities | Write code |
| [Backend Developer](agents/backend-developer-agent.md) | Implements commands, queries, handlers, repositories, migrations, controllers with OpenAPI | Touch frontend code |
| [Frontend Developer](agents/frontend-developer-agent.md) | Implements pages, composables, stores, services, components | Touch backend code |
| [DoD-checker](agents/dod-checker-agent.md) | Mechanical Haiku-tier gate between Dev and Reviewer — verifies every task DoD checkbox has an artefact on disk | Make architectural judgements |
| [Backend Reviewer](agents/backend-reviewer-agent.md) | Reviews architecture, PHPStan level 9, PHP-CS-Fixer, security, API contracts | Modify code — only requests changes |
| [Frontend Reviewer](agents/frontend-reviewer-agent.md) | Reviews TypeScript strict mode, ESLint/Prettier, state management, error handling | Modify code — only requests changes |
| [Tester](agents/tester-agent.md) | Writes and runs unit + integration tests after review is complete | Skip tests for "simple" changes |
| [DevOps](agents/devops-agent.md) | Configures Docker, docker-compose, Makefiles, env vars, migrations on startup | Run unless new infrastructure is needed |
| [Web Auditor](agents/web-auditor-agent.md) | Manual audit (`/check-web`) — reads Playwright walker output, triages findings, emits `/create-specs` prompts | Run automatically — manual on-demand only |

Agents never share a context window. They communicate via **handoff files** — structured summaries listing files created, files modified, key decisions, and exactly which files the next agent should read. Handoffs are deleted when the feature is complete.

---

## What makes this work

**Spec before code.** No agent writes a line of code without a validated spec. The spec is the contract — the developer, every agent, and every reviewer read the same document.

**Isolated contexts.** Each agent starts with a clean context and reads only the files it needs. A decision made during backend implementation can't leak into the frontend review. Token costs stay predictable.

**Token-conscious architecture.** Standards are split into concise rules files (always loaded, ~150 lines) and detailed reference files (loaded only when needed, ~500 lines each). Before agents run, the orchestrator generates **two per-phase context bundles** tailored to the current feature: `dev-bundle.md` (~200–400 lines, consumed by Developer / Dev+Tester / DevOps with the full implementation surface) and `tester-bundle.md` (~150–200 lines, consumed by the Tester with the test-design-only surface). Reviewers and the DoD-checker do not receive a bundle — Reviewers follow a coverage-aware protocol that loads matching critical paths plus per-section reads of the review checklist; the DoD-checker reads only the task DoD and the developer handoff's `## DoD coverage` section. This avoids agents reading ~1,000+ lines of standards they don't need.

**Standards from real failures.** Every rule exists because it prevented a real problem. The bootstrap checklist includes the exact error each item avoids. Agent mistakes are logged by the Tester and recycled as warnings in future builds. Per-project mistakes are stored in the project's own docs repo (`{project-name}-docs/lessons-learned/`, split by `back.md` / `front.md` / `infra.md` / `general.md`). Mistakes that recur across projects get promoted directly to the relevant standard/command/checklist — `ai-standards/` keeps no framework-level lessons-learned registry, by design.

**Visual consistency across features.** The Frontend Developer documents UI patterns (first form, first table, first modal...) in a project-level `design-decisions.md` file as they are implemented. The Spec Analyzer reads it when writing specs to avoid contradictions. The Frontend Reviewer verifies compliance. The result: the second feature looks like it was built by the same team as the first.

**Definition of Done is a checklist.** Every feature generates a task file with explicit checkboxes: architecture compliance, static analysis, formatting, tests passing, security checks, spec updated. A feature is done when every box is checked.

**On-demand skills.** Narrow playbooks (CORS gotchas, safe migrations, JWT lifecycle, Vitest patterns, quality-gate setup...) live in `.claude/skills/`. Claude Code auto-loads a skill only when the active task or file paths match — description-only otherwise, so they cost nothing until needed. See [USAGE.md](USAGE.md#skills-reference) for the full catalog (~16 skills).

**Deterministic quality gates.** Three layers — pre-commit hook, per-service `make quality`, and GitHub Actions CI — enforce PHPStan level 9, `vue-tsc --noEmit` strict, PHP-CS-Fixer, ESLint + Prettier, full test suite, and `composer audit` / `npm audit`. Reviewer agents keep doing what humans do best; the mechanical bar is enforced by machines. Install per service from [`templates/`](templates/); authoritative rules in [`standards/quality-gates.md`](standards/quality-gates.md).

---

## What's inside

```
ai-standards/
├── .claude/
│   ├── commands/                   ← 6 slash commands (Claude Code integration)
│   └── skills/                     ← ~16 on-demand playbooks auto-loaded by Claude Code
├── CLAUDE.md                       ← Entry point for agents — global rules, naming, git workflow
├── USAGE.md                        ← Setup guide, make-command reference, skills catalog
├── Makefile                        ← Workspace-level orchestration: up/down/build/test/quality (includes `{project-docs}/workspace.mk`)
├── .workspace-config-path          ← Gitignored pointer — one line with the path to the current project's docs repo
├── agents/                         ← 9 agent definitions (role, responsibilities, tools, limits)
├── commands/                       ← Command implementations (referenced by .claude/commands/)
├── templates/
│   ├── ci/                         ← GitHub Actions workflow templates (backend + frontend)
│   ├── hooks/                      ← Git pre-commit hooks (backend + frontend)
│   ├── makefile/                   ← Makefile quality snippets for per-service Makefiles
│   └── feature-*.md                ← Spec, task, and handoff file templates
├── scaffolds/                      ← Production-ready PHP classes — copy verbatim, never rewrite
│   ├── AppController.php           ← Base controller with command/query dispatch helpers
│   ├── ApiExceptionSubscriber.php  ← Maps domain exceptions to HTTP status codes
│   ├── LoggingMiddleware.php       ← Structured JSON logging with sensitive field redaction
│   └── SecurityHeadersSubscriber.php
├── scripts/
│   └── smoke-tests.sh              ← Static framework self-checks — free, runs on every CI push (`make smoke`)
├── tests/                          ← Dynamic framework self-checks — local only, run via `make smoke-dynamic`
│   ├── fixtures/                   ← Minimal project stubs (`standard/`) exercised by the harness
│   ├── harness/                    ← Hook + runner + assertions (stdlib Python)
│   ├── expected/                   ← Per-fixture JSON invariants
│   └── README.md                   ← When to run, how to add a fixture, what the harness intercepts
└── standards/
    ├── invariants.md               ← Non-negotiable rules — security, code, git, agent behavior
    ├── agent-reading-protocol.md   ← Canonical reading order for every agent (build-plan + standalone)
    ├── tech-stack.md               ← Authoritative versions (minimums, open to update) + upgrade procedure
    ├── quality-gates.md            ← CI + pre-commit + Makefile quality rules (PHPStan L9, vue-tsc, tests)
    ├── backend.md                  ← PHP/Symfony architecture rules (concise, always loaded)
    ├── backend-reference.md        ← Full code examples, configs, test patterns (loaded on demand)
    ├── frontend.md                 ← Vue 3/TypeScript rules (concise, always loaded)
    ├── frontend-reference.md       ← Full code examples, interceptor setup, test patterns (loaded on demand)
    ├── logging.md                  ← Structured JSON logs, Monolog config, sensitive field redaction
    ├── security.md                 ← HTTP headers, CORS, JWT lifecycle, rate limiting, input validation
    ├── performance.md              ← Database indexes, pagination, N+1 prevention, lazy loading
    └── new-service-checklist.md    ← Bootstrap checklist — each item includes the error it prevents
```

> Per-project agent mistakes live in `{project-name}-docs/lessons-learned/` — never inside `ai-standards/`. If a lesson recurs across projects, promote it to the relevant standard/command/agent doc in the same commit.
