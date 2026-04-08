# AI Standards

Central hub for AI standards, conventions, agents and project documentation
used across all projects in this workspace.

Designed for professional web development projects following enterprise-grade
architecture patterns (Hexagonal Architecture, DDD, CQRS, Event-Driven).

## What's inside

- **CLAUDE.md** — global standards and rules for the AI assistant
- **agents/** — agent definitions (roles, responsibilities, tools)
- **commands/** — developer-invoked workflows that orchestrate agents
- **templates/** — file templates (specs, tasks...)
- **projects/** — project-specific documentation (services, specs)

## Agents

| Agent | Responsibility |
|---|---|
| [Spec Analyzer](agents/spec-analyzer-agent.md) | Analyzes tasks, asks questions, creates specs and execution plans |
| [Backend Developer](agents/backend-developer-agent.md) | Implements backend features following Hexagonal, DDD and CQRS |
| [Frontend Developer](agents/frontend-developer-agent.md) | Implements frontend features with Vue 3 and TypeScript |
| [Backend Reviewer](agents/backend-reviewer-agent.md) | Reviews backend code quality, architecture and security |
| [Frontend Reviewer](agents/frontend-reviewer-agent.md) | Reviews frontend code quality, standards and security |
| [Tester](agents/tester-agent.md) | Writes and executes integration and unit tests |
| [DevOps](agents/devops-agent.md) | Configures Docker, Makefiles and infrastructure |

## Tech Stack

| Layer | Technology |
|---|---|
| Backend | PHP 8.4+ + Symfony 8.0+ |
| Frontend | Vue 3 + TypeScript + Vite |
| Database | PostgreSQL |
| Messaging | RabbitMQ |
| Infrastructure | Docker |

## Commands

| Command | Description |
|---|---|
| [create-specs](commands/create-specs-command.md) | Creates a business-level spec from a feature description |
| [refine-specs](commands/refine-specs-command.md) | Refines business specs into technical specs and generates the execution plan |
| [build-plan](commands/build-plan-command.md) | Executes the plan, invoking agents in the defined order |
| [update-specs](commands/update-specs-command.md) | Updates specs to match the final implementation |

## Workflow

A typical feature goes through the following flow:

```
Developer describes the feature
        │
        ▼
  create-specs ─── Spec Analyzer creates business spec
        │
        ▼
  refine-specs ─── Spec Analyzer refines into technical spec + plan + task
        │
        ▼
   build-plan ──┬─ Backend Developer implements
                │  Backend Reviewer reviews ←→ (loop if changes needed)
                │  Frontend Developer implements
                │  Frontend Reviewer reviews ←→ (loop if changes needed)
                │  DevOps configures infrastructure (if needed)
                │  Tester writes and runs tests ←→ (loop if tests fail)
                │
                ▼
  update-specs ─── Spec Analyzer updates specs to match final implementation
```

## How to use in a project

Every service must include a `CLAUDE.md` referencing this repository and its standards.
Project-specific documentation (services, specs) lives under `projects/{project-name}/`.
