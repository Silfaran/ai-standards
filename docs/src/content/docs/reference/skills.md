---
title: Skills catalog
description: On-demand playbooks auto-loaded by Claude Code when the active task or file paths match — narrow, specific, cheap.
---

Skills are narrow playbooks Claude Code auto-loads only when the active task or file paths match the skill's description. The full body is loaded on match; otherwise only the description sits in context (cheap).

This replaces reading large reference files end-to-end whenever a recurring sub-task fits a known recipe.

## Catalog

| Skill | Activates when |
|---|---|
| `cors-nelmio-configuration` | Configuring NelmioCorsBundle, adding a frontend origin, debugging CORS preflight failures |
| `docker-env-reload` | Editing `.env` / `env_file`; env-var changes not taking effect in a running container |
| `docker-frontend-deps-sync` | `npm install`, adding/removing packages in a Dockerized Vue/Vite frontend |
| `doctrine-migration-safe` | Writing a Phinx migration — tables, columns, indexes, safe ALTER patterns |
| `empty-loading-error-states` | Vue 3 page rendering server data fetched with TanStack Query — three non-negotiable UI states |
| `jwt-security` | JWT auth, refresh-token rotation, login/logout endpoints, Lexik JWT, token storage |
| `messenger-logging-middleware` | Wiring LoggingMiddleware to Symfony Messenger buses, structured JSON logs, redaction list |
| `new-service-bootstrap` | Scaffolding a new PHP/Symfony service from scratch — Kernel, bundles, routes, Flex cleanup |
| `openapi-controller-docs` | Writing a PHP/Symfony controller — adding `#[OA\...]` attributes covering req body, params, responses |
| `pinia-store-pattern` | Creating or modifying a Pinia store — global state, what belongs in store vs TanStack Query |
| `quality-gates-setup` | Installing quality gates — CI workflow, pre-commit hook, Makefile targets |
| `rate-limiting-auth` | Adding/adjusting Symfony RateLimiter on auth endpoints (login, register, password reset) |
| `shadcn-vue-component-add` | Before/after `npx shadcn-vue add <component>` — to catch silent overwrites |
| `symfony-messenger-async` | Configuring buses, RabbitMQ transports, cross-service message contracts, consumer workers |
| `vitest-composable-test` | Writing or debugging Vitest tests for Vue 3 composables / stores / pages — TanStack Query mocking, Pinia setup |
| `vue-composable-mutation` | Implementing a Vue 3 composable with TanStack Query's `useMutation` — login, register, create, update, delete |

## How to add a skill

Skills live in `.claude/skills/<name>/SKILL.md`. The frontmatter must include:

- `name:` — must match the directory name (smoke check 3 verifies this).
- `description:` — the trigger conditions Claude Code matches against the active task.
- `allowed-files:` — optional glob list that scopes when the skill auto-loads.

The body is the playbook content — recipes, patterns, gotchas, anti-patterns.

## When NOT to add a skill

Skills are for recurring sub-tasks that have a clear pattern AND a clear failure mode if done wrong. Do NOT add a skill for:

- Anything covered by a standard or critical path (would duplicate).
- One-off project-specific recipes (those live in the project's docs repo).
- Documentation that does not produce or modify code.

If a recipe is generally useful but not yet recurring, add it as a section in the relevant `<name>-reference.md` standard file. Promote it to a skill only when it has fired in 2-3 features and proven its trigger.
