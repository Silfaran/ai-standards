# AI Standards

An orchestration framework for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that builds full-stack web applications — PHP/Symfony backend and Vue 3 frontend — using isolated AI agents that spec, implement, review, and test each feature.

You describe a feature in plain language. The framework splits the work across seven specialized agents, each with its own context window, strict standards, and a single role. The result is implemented, reviewed, and tested code following Hexagonal Architecture, DDD, CQRS, and Event-Driven design.

> **Want to start using it?** See **[USAGE.md](USAGE.md)** for the setup guide and step-by-step workflow.

---

## Tech stack

This framework is opinionated. It enforces a specific stack and architecture.

The authoritative list of technologies, minimum versions and upgrade policy lives in [`standards/tech-stack.md`](standards/tech-stack.md) — all versions are minimums, open to newer compatible releases.

At a glance: PHP + Symfony on the backend, Vue 3 + TypeScript + Vite (with shadcn/ui) on the frontend, PostgreSQL as the database (one per service), RabbitMQ via Symfony Messenger for messaging, Docker for per-service containers and shared infrastructure.

Architecture patterns — Hexagonal, DDD, CQRS, Event-Driven — are enforced by standards, not suggested. Every agent validates against them.

---

## How it works

Four commands, each backed by specialized agents:

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
       │   [Phase 3]  Backend Reviewer + Frontend Reviewer    (parallel, up to 3 rounds each)
       │   [Phase 4]  Tester writes and runs all tests
       │
       ▼
/update-specs     Spec Analyzer syncs the spec with the final implementation
```

Backend and Frontend run in parallel — independent codebases, independent review loops. The Tester runs once against the final, reviewed code. The framework adapts the execution flow to feature complexity: simple features use fewer agents; complex multi-service features use the full pipeline with parallel phases.

---

## Agents

Seven agents, each with a single responsibility and an isolated context window:

| Agent | Does | Doesn't |
|---|---|---|
| [Spec Analyzer](agents/spec-analyzer-agent.md) | Translates business descriptions into technical specs, flags cross-service incompatibilities | Write code |
| [Backend Developer](agents/backend-developer-agent.md) | Implements commands, queries, handlers, repositories, migrations, controllers with OpenAPI | Touch frontend code |
| [Frontend Developer](agents/frontend-developer-agent.md) | Implements pages, composables, stores, services, components | Touch backend code |
| [Backend Reviewer](agents/backend-reviewer-agent.md) | Reviews architecture, PHPStan level 9, PHP-CS-Fixer, security, API contracts | Modify code — only requests changes |
| [Frontend Reviewer](agents/frontend-reviewer-agent.md) | Reviews TypeScript strict mode, ESLint/Prettier, state management, error handling | Modify code — only requests changes |
| [Tester](agents/tester-agent.md) | Writes and runs unit + integration tests after review is complete | Skip tests for "simple" changes |
| [DevOps](agents/devops-agent.md) | Configures Docker, docker-compose, Makefiles, env vars, migrations on startup | Run unless new infrastructure is needed |

Agents never share a context window. They communicate via **handoff files** — structured summaries listing files created, files modified, key decisions, and exactly which files the next agent should read. Handoffs are deleted when the feature is complete.

---

## What makes this work

**Spec before code.** No agent writes a line of code without a validated spec. The spec is the contract — the developer, every agent, and every reviewer read the same document.

**Isolated contexts.** Each agent starts with a clean context and reads only the files it needs. A decision made during backend implementation can't leak into the frontend review. Token costs stay predictable.

**Token-conscious architecture.** Standards are split into concise rules files (always loaded, ~150 lines) and detailed reference files (loaded only when needed, ~500 lines each). Before agents run, a **context bundle** distills all relevant standards into a single 200–400 line file tailored to the current feature. This avoids agents reading ~1,000+ lines of standards they don't need.

**Standards from real failures.** Every rule exists because it prevented a real problem. The bootstrap checklist includes the exact error each item avoids. Agent mistakes are logged by the Tester and recycled as warnings in future builds — patterns that recur get promoted to permanent standards.

**Visual consistency across features.** The Frontend Developer documents UI patterns (first form, first table, first modal...) in a project-level `design-decisions.md` file as they are implemented. The Spec Analyzer reads it when writing specs to avoid contradictions. The Frontend Reviewer verifies compliance. The result: the second feature looks like it was built by the same team as the first.

**Definition of Done is a checklist.** Every feature generates a task file with explicit checkboxes: architecture compliance, static analysis, formatting, tests passing, security checks, spec updated. A feature is done when every box is checked.

**On-demand skills.** Narrow playbooks (CORS gotchas, safe migrations, JWT lifecycle, Vitest patterns, quality-gate setup...) live in `.claude/skills/`. Claude Code auto-loads a skill only when the active task or file paths match — description-only otherwise, so they cost nothing until needed. See [USAGE.md](USAGE.md#skills-reference) for the full catalog (~13 skills).

**Deterministic quality gates.** Three layers — pre-commit hook, per-service `make quality`, and GitHub Actions CI — enforce PHPStan level 9, `vue-tsc --noEmit` strict, PHP-CS-Fixer, ESLint + Prettier, full test suite, and `composer audit` / `npm audit`. Reviewer agents keep doing what humans do best; the mechanical bar is enforced by machines. Install per service from [`templates/`](templates/); authoritative rules in [`standards/quality-gates.md`](standards/quality-gates.md).

---

## What's inside

```
ai-standards/
├── .claude/
│   ├── commands/                   ← 5 slash commands (Claude Code integration)
│   └── skills/                     ← ~13 on-demand playbooks auto-loaded by Claude Code
├── CLAUDE.md                       ← Entry point for agents — global rules, naming, git workflow
├── USAGE.md                        ← Setup guide, make-command reference, skills catalog
├── Makefile                        ← Workspace-level orchestration: up/down/build/test/quality
├── agents/                         ← 7 agent definitions (role, responsibilities, tools, limits)
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
    ├── new-service-checklist.md    ← Bootstrap checklist — each item includes the error it prevents
    └── lessons-learned.md          ← Agent mistakes from past builds — auto-populated, injected as warnings
```

---

## Honest limitations

- **Single stack.** This builds PHP/Symfony + Vue 3 applications. A different stack requires rewriting the standards, scaffolds, and reference files. The orchestration patterns (agents, handoffs, spec-first) are portable; the implementation details are not.
- **Claude Code only.** Agent orchestration relies on Claude Code's subagent system. It won't work with other AI tools without significant adaptation.
- **Developer in the loop.** This does not replace the developer. You describe features, approve specs, confirm git operations, and make decisions the AI can't make alone. The framework structures the AI's work — it doesn't eliminate yours.
- **Opinionated architecture.** Hexagonal + DDD + CQRS is enforced, not suggested. If your project doesn't follow these patterns, the standards will fight your codebase.

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

