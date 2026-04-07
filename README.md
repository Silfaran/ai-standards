# AI Standards

Central hub for AI standards, conventions, agents and project documentation
used across all projects in this workspace.

Designed for professional web development projects following enterprise-grade
architecture patterns (Hexagonal Architecture, DDD, CQRS, Event-Driven).

## What's inside

- **CLAUDE.md** — global standards and rules for the AI assistant
- **agents/** — agent definitions (roles, responsibilities, tools)
- **projects/** — project-specific documentation (services, specs)

## Agents

| Agent | Responsibility |
|---|---|
| [Spec Analyzer](agents/spec-analyzer.md) | Analyzes tasks, asks questions, creates specs and execution plans |
| [Backend Developer](agents/backend-developer.md) | Implements backend features following Hexagonal, DDD and CQRS |
| [Frontend Developer](agents/frontend-developer.md) | Implements frontend features with Vue 3 and TypeScript |
| [Backend Reviewer](agents/backend-reviewer.md) | Reviews backend code quality, architecture and security |
| [Frontend Reviewer](agents/frontend-reviewer.md) | Reviews frontend code quality, standards and security |
| [Tester](agents/tester.md) | Writes and executes integration and unit tests |
| [DevOps](agents/devops.md) | Configures Docker, Makefiles and infrastructure |

## Tech Stack

| Layer | Technology |
|---|---|
| Backend | PHP 8.4+ + Symfony 8.0+ |
| Frontend | Vue 3 + TypeScript + Vite |
| Database | PostgreSQL |
| Messaging | RabbitMQ |
| Infrastructure | Docker |

## How to use in a project

Every service must include a `CLAUDE.md` referencing this repository and its standards.
Project-specific documentation (services, specs) lives under `projects/{project-name}/`.
