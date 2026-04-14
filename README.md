# AI Standards

A multi-agent orchestration framework for AI-assisted software development.
Covers the full feature lifecycle — from business description to deployed, reviewed, and tested code —
using isolated, role-specific AI agents that communicate via structured handoff files.

Designed for professional projects following enterprise-grade architecture patterns:
Hexagonal Architecture, DDD, CQRS, and Event-Driven design.

---

## The problem this solves

Using an AI assistant without structure produces inconsistent results: agents accumulate context across tasks, make contradictory decisions, skip reviews, and implement features without specs. This framework solves that by defining:

- **Roles** — each agent has a single responsibility and cannot exceed it
- **Order** — phases execute in a defined sequence, with parallel phases where safe
- **Handoffs** — every agent documents what it did before the next one starts
- **Specs first** — no code is written without a validated technical specification

---

## Workflow

A typical feature goes through the following phases:

```
Developer describes the feature
        │
        ▼
  create-specs ──── Spec Analyzer writes business spec, flags incompatibilities
        │
        ▼
  refine-specs ──── Spec Analyzer produces technical spec + execution plan + task checklist
        │
        ▼
   build-plan
        │
        ├─ [Phase 1] Tester writes unit tests (from spec domain rules, before any code)
        │
        ├─ [Phase 2] DevOps configures infrastructure (only if new service or new infra)
        │
        ├─ [Phase 3] Backend Developer ──────────────┐  (parallel, independent codebases)
        │            Frontend Developer ─────────────┘
        │
        ├─ [Phase 4] Backend Reviewer ───────────────┐  (parallel, loops up to 3× if changes needed)
        │            Frontend Reviewer ──────────────┘
        │
        └─ [Phase 5] Tester writes integration tests + runs all tests (loops up to 3× if failures)
        │
        ▼
  update-specs ──── Spec Analyzer syncs spec with the final implementation
```

Backend and Frontend run in parallel because their codebases are independent.
Reviewers run in parallel for the same reason.
The Tester runs in two phases: domain rules encoded before code exists, integration verified after.

---

## What's inside

```
ai-standards/
├── CLAUDE.md                       ← Global AI rules, naming conventions, git workflow
├── agents/                         ← 7 agent definitions (role, responsibilities, tools, limits)
├── commands/                       ← 5 developer-invoked orchestration commands
├── templates/                      ← Spec, task, and handoff file templates
├── scaffolds/                      ← Copy-verbatim PHP classes (AppController, etc.)
├── standards/
│   ├── invariants.md               ← Non-negotiable rules — read first, cannot be overridden
│   ├── backend.md                  ← PHP/Symfony: architecture rules (concise)
│   ├── backend-reference.md        ← Full code examples, configs, scaffold usage
│   ├── frontend.md                 ← Vue 3/TS: rules (concise)
│   ├── frontend-reference.md       ← Full code examples, test patterns
│   ├── logging.md                  ← Structured JSON logs, redaction, Monolog config
│   ├── security.md                 ← Headers, CORS, JWT, rate limiting, input validation
│   ├── performance.md              ← Database, API, and frontend performance rules
│   └── new-service-checklist.md    ← Pre-commit checklist derived from real bootstrap failures
└── commands/init-project-command.md
```

**Token optimization architecture:** Standards are split into rules files (always loaded) and reference files (loaded conditionally). The `refine-specs` command generates a `Standards Scope` in the plan file that tells `build-plan` which reference files each agent needs. This prevents agents from reading ~600 lines of code examples they don't need for the current feature.

---

## Agents

| Agent | Responsibility |
|---|---|
| [Spec Analyzer](agents/spec-analyzer-agent.md) | Translates business descriptions into technical specs, asks clarifying questions, detects incompatibilities between services |
| [Backend Developer](agents/backend-developer-agent.md) | Implements backend features: commands, queries, handlers, repositories, migrations, controllers with OpenAPI annotations |
| [Frontend Developer](agents/frontend-developer-agent.md) | Implements frontend features: pages, composables, stores, services, components |
| [Backend Reviewer](agents/backend-reviewer-agent.md) | Reviews backend code: architecture compliance, PHPStan level 9, PHP CS Fixer, security, API contracts |
| [Frontend Reviewer](agents/frontend-reviewer-agent.md) | Reviews frontend code: TypeScript strict mode, ESLint/Prettier, store usage, loading/error states |
| [Tester](agents/tester-agent.md) | Two-phase testing: unit tests before implementation (domain rules), integration tests after, executes both |
| [DevOps](agents/devops-agent.md) | Configures Docker, docker-compose, Makefiles, environment variables, migrations on startup |

Each agent runs as an isolated subagent with a clean context window.
Agents communicate only via handoff files — never via shared context.

---

## Commands

| Command | What it does |
|---|---|
| [init-project](commands/init-project-command.md) | Creates `{project-name}-docs/services.md` at the workspace root — run once per project |
| [create-specs](commands/create-specs-command.md) | Spec Analyzer converts a feature description into a structured business spec |
| [refine-specs](commands/refine-specs-command.md) | Spec Analyzer produces the technical spec, execution plan, and task checklist |
| [build-plan](commands/build-plan-command.md) | Executes the full plan: spawns agents in order, handles parallel phases, loops on failures |
| [update-specs](commands/update-specs-command.md) | Spec Analyzer compares spec against final implementation and updates it to match |

---

## Standards

Standards are split into **rules files** (concise, always loaded) and **reference files** (detailed, loaded conditionally by the `Standards Scope` in the plan file).

| Standard | Covers |
|---|---|
| [invariants.md](standards/invariants.md) | Non-negotiable rules — security, code, git, agent behavior |
| [backend.md](standards/backend.md) | Architecture rules, folder structure, naming, testing rules (concise) |
| [backend-reference.md](standards/backend-reference.md) | Full code examples, scaffold usage, YAML configs, test examples |
| [frontend.md](standards/frontend.md) | Vue 3/TS rules, composable patterns, store rules, testing rules (concise) |
| [frontend-reference.md](standards/frontend-reference.md) | Full code examples, interceptor setup, test examples |
| [logging.md](standards/logging.md) | Structured JSON logs, sensitive field redaction, Monolog config |
| [security.md](standards/security.md) | HTTP headers, CORS, JWT lifecycle, rate limiting, input validation |
| [performance.md](standards/performance.md) | Database indexes, pagination, N+1 prevention, frontend lazy loading |
| [new-service-checklist.md](standards/new-service-checklist.md) | Bootstrap checklist for new services, CORS setup, Docker env reload |

---

## Tech Stack

| Layer | Technology |
|---|---|
| Backend | PHP 8.4+ + Symfony 8.0+ |
| Frontend | Vue 3 + TypeScript + Vite |
| UI Components | shadcn/ui (Vue) |
| Database | PostgreSQL |
| Messaging | RabbitMQ (Symfony Messenger) |
| Infrastructure | Docker |

---

## Design principles

**Isolated context per agent.** Each agent starts with a clean context and reads only the files it needs. This prevents decisions made in one phase from contaminating another, and keeps token costs predictable.

**Spec before code.** No agent writes code without a validated spec. The spec is the contract — developers, agents, and reviewers all read the same document.

**Standards derived from real failures.** Rules in this repository were added after encountering the specific problem they prevent. Each rule in `new-service-checklist.md` includes the exact error it avoids.

**Handoff files as the communication layer.** Agents do not share context windows. Each agent produces a structured handoff file (Files Created, Files Modified, Key Decisions, Open Questions) before the next agent starts. The file is deleted after the feature is complete.

**Definition of Done is a checklist, not a feeling.** Every feature has a task file with explicit checkboxes. A feature is done when every box is checked — not when it "looks done."

---

## Ethical use

This project is released under the MIT License. You are free to use, modify, and distribute it for any purpose, including commercial use.

However, the author does not endorse and explicitly discourages use of this work in any context that:

- Develops, supports, or facilitates weapons systems or military targeting
- Enables mass surveillance, tracking, or profiling of individuals without consent
- Powers systems designed to discriminate based on race, gender, religion, nationality, or any protected characteristic
- Generates or distributes disinformation, propaganda, or deceptive content at scale
- Facilitates fraud, scams, or platforms designed to deceive or defraud users
- Develops malware, cyberweapons, or software intended to attack systems without authorization
- Violates applicable human rights law or international humanitarian law

This notice is not a legal restriction — it is a statement of values.

---

## How to use in a project

Every service in the workspace must have a `CLAUDE.md` that references this repository:

```markdown
## Standards
Read `ai-standards/CLAUDE.md` and the relevant `ai-standards/standards/*.md` before doing anything.
```

Run `init-project` to create the documentation structure for a new project.
This creates `{project-name}-docs/services.md` at the workspace root — outside of `ai-standards/`.
Specs, plans, and task files live in `{project-name}-docs/specs/{Aggregate}/`.
