# Agent Reading Protocol

Canonical reading order every agent must follow before doing any work.
Each agent definition references this file instead of repeating the list.

When you extend an agent, add only the **role-specific** files it needs — do not redefine the common core.

## Two Invocation Modes

Every agent runs in one of two modes. Know which one you are in.

### Mode A — `build-plan` subagent (default)

The orchestrator has already prepared a **context bundle** (`{workspace_root}/handoffs/{feature}/context-bundle.md`, workspace-root `handoffs/` directory declared in `{project-docs}/workspace.md` under the `handoffs:` key) that distills every rule relevant to the feature from `invariants.md`, `CLAUDE.md`, and the role-specific standards.

Read, in order:

1. **The context bundle** — it replaces `invariants.md`, `CLAUDE.md`, and the standards files.
2. **The role-specific handoffs** the orchestrator names in your prompt.
3. **The spec, task and plan** files the orchestrator names in your prompt.

Do **not** re-read individual standards files in this mode. The bundle is the contract.

### Mode B — Standalone (manual invocation, rare)

No context bundle exists. Read the full file set:

1. [`invariants.md`](invariants.md) — non-negotiable rules. Always first.
2. [`../CLAUDE.md`](../CLAUDE.md) — workspace-wide rules and conventions.
3. [`tech-stack.md`](tech-stack.md) — authoritative versions and pinning policy.
4. **Project workspace config** — resolve the project docs directory from the pointer file `ai-standards/.workspace-config-path` (single line, e.g. `../task-manager-docs`), then read `{docs-dir}/workspace.md`. If either file is missing, stop and tell the developer to run `/init-project`.
5. **`services.md`** — path listed inside `{docs-dir}/workspace.md`.
6. **`decisions.md`** — path listed inside `{docs-dir}/workspace.md`. Never contradict a recorded decision without explicit developer approval. Format rules for entries in this file live in [`adr.md`](adr.md) — status lifecycle, ID convention, supersedes chain. The Spec Analyzer follows these when adding new ADRs.
7. **Role-specific standards** (see table below).
8. **The spec, task, and any handoff** for the feature you are working on.

## Role-specific Additions

Each agent adds only the files below to the Mode B list. Reference files (`*-reference.md`) are **on demand** — load them the first time a pattern appears, not by default.

| Agent | Always | On demand |
|---|---|---|
| Spec Analyzer | `design-decisions.md`, existing specs in the project docs folder | — |
| Backend Developer | [`backend.md`](backend.md), [`security.md`](security.md), [`performance.md`](performance.md), [`observability.md`](observability.md), [`api-contracts.md`](api-contracts.md) | [`caching.md`](caching.md) when the spec references cache behavior or the feature is read-heavy, [`secrets.md`](secrets.md) when the feature adds or reads a new secret, [`authorization.md`](authorization.md) when the feature adds a protected endpoint, introduces a new role, or touches a multi-tenant aggregate, [`i18n.md`](i18n.md) when the feature renders user-facing text, stores translatable content, or negotiates locale, [`gdpr-pii.md`](gdpr-pii.md) when the feature stores, reads, exports or deletes data identifying a natural person, [`llm-integration.md`](llm-integration.md) when the feature calls an LLM (Claude, OpenAI, Gemini, Mistral, self-hosted) at runtime, [`payments-and-money.md`](payments-and-money.md) when the feature charges, refunds, holds in escrow, pays out, splits revenue, or handles subscriptions, [`file-and-media-storage.md`](file-and-media-storage.md) when the feature stores user-uploaded or system-generated binary content (avatars, documents, video, attachments, exports), [`data-migrations.md`](data-migrations.md) when the feature modifies an existing table (column rename, type change, constraint tightening, removal), [`logging.md`](logging.md) (covered by `messenger-logging-middleware` skill), [`backend-reference.md`](backend-reference.md), [`new-service-checklist.md`](new-service-checklist.md), [`quality-gates.md`](quality-gates.md) |
| Frontend Developer | [`frontend.md`](frontend.md), [`security.md`](security.md), [`performance.md`](performance.md), [`observability.md`](observability.md), [`api-contracts.md`](api-contracts.md), `design-decisions.md` | [`caching.md`](caching.md) when wiring HTTP cache headers or consuming cached endpoints, [`secrets.md`](secrets.md) when adding a new `VITE_*` variable or consuming a backend-minted short-lived token, [`authorization.md`](authorization.md) when adding a route guard, role-gated UI, or handling 403 responses, [`i18n.md`](i18n.md) when rendering user-facing text, formatting dates/numbers/currency, or wiring vue-i18n, [`gdpr-pii.md`](gdpr-pii.md) when collecting PII via forms, building a consent UI, or handling a withdrawal flow, [`payments-and-money.md`](payments-and-money.md) when rendering money, capturing payment methods, or handling a payment confirmation page, [`file-and-media-storage.md`](file-and-media-storage.md) when wiring an upload form, rendering signed-URL images/videos, or showing upload progress, [`frontend-reference.md`](frontend-reference.md), [`quality-gates.md`](quality-gates.md) |
| Backend Reviewer | [`backend-review-checklist.md`](backend-review-checklist.md) **only** — see rule below | — |
| Frontend Reviewer | [`frontend-review-checklist.md`](frontend-review-checklist.md) **only** — see rule below | `design-decisions.md` when diff touches UI |
| Tester | [`backend.md`](backend.md) or [`frontend.md`](frontend.md) (pick by test surface), [`security.md`](security.md) | [`logging.md`](logging.md) (covered by `messenger-logging-middleware` skill), [`backend-reference.md`](backend-reference.md) or [`frontend-reference.md`](frontend-reference.md) for first-time test patterns |
| DevOps | [`tech-stack.md`](tech-stack.md) (already in common core), [`secrets.md`](secrets.md), [`quality-gates.md`](quality-gates.md), root `docker-compose.yml`, service compose files | [`backend-reference.md`](backend-reference.md) for consumer-worker patterns, [`new-service-checklist.md`](new-service-checklist.md) when scaffolding a new service |

### Reviewer exception

Both reviewer agents read **only** their checklist in both modes — never the full standards. The checklists are the authoritative review surface, extracted from the standards and updated alongside them. If a reviewer sees a violation not covered by the checklist, it is reported as `minor` with a recommendation for which checklist section should cover it.

### Skills complement this protocol

Claude Code auto-loads the matching skill from [`../.claude/skills/`](../.claude/skills/) whenever the active task or file paths match its description. When a skill has already supplied guidance on a topic (CORS setup, safe migrations, JWT lifecycle, Vitest patterns, …), the equivalent section of the corresponding standard can be skipped — do not double-load the same content. Standards remain the source of truth for architecture and topics not covered by any skill.

## Handoff Protocol

Every agent that produces output writes a handoff summary for the next agent, using [`../templates/feature-handoff-template.md`](../templates/feature-handoff-template.md).

The next agent reads the handoff first and then **only the files listed in it** — not the entire codebase.

Handoff files are temporary. The `build-plan` orchestrator deletes them once the full feature plan is complete.

## Writing Rules — always in effect

- All files, code, and documentation written in English.
- When in doubt about any decision, ask the developer before proceeding.
- Do not add complexity that is not required by the current task.
- Review your own output before considering the task complete.
- When scaffolding a component that exists in [`../scaffolds/`](../scaffolds/) (AppController, ApiExceptionSubscriber, LoggingMiddleware, SecurityHeadersSubscriber), copy it verbatim — do not rewrite from memory.
