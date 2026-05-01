# Agent Reading Protocol

Canonical reading order every agent must follow before doing any work.
Each agent definition references this file instead of repeating the list.

When you extend an agent, add only the **role-specific** files it needs — do not redefine the common core.

## Three Invocation Modes

Every agent runs in one of three modes. Know which one you are in.

### Mode A — `build-plan` subagent (default)

The orchestrator has already prepared **per-phase bundles** under `{workspace_root}/handoffs/{feature}/` (workspace-root `handoffs/` directory declared in `{project-docs}/workspace.md` under the `handoffs:` key):

- `dev-bundle.md` — full implementation surface, consumed by Developer / Dev+Tester / DevOps. Distills every rule relevant to the feature from `invariants.md`, `CLAUDE.md`, and the role-specific standards.
- `tester-bundle.md` — reduced surface (no implementation rules), consumed by the Tester. Keeps invariants, naming, logging/redaction, GDPR/PII, attack-surface-hardening, and the spec digest.

The orchestrator names the correct bundle path in each subagent's prompt — read whichever bundle is named, not the other one.

Read, in order:

1. **The bundle named in the prompt** (`dev-bundle.md` or `tester-bundle.md`) — it replaces `invariants.md`, `CLAUDE.md`, and the standards files.
2. **The role-specific handoffs** the orchestrator names in your prompt.
3. **The spec, task and plan** files the orchestrator names in your prompt.

Do **not** re-read individual standards files in this mode. The bundle is the contract.

> **Reviewers and the DoD-checker do NOT receive a bundle.** Reviewers follow the coverage-aware protocol — load PRIMARY-matched critical paths, then read checklist sections per the gap (with citation) instead of pre-loading the full review checklist. The DoD-checker reads only the task DoD and the developer handoff's `## DoD coverage` section. See [`../commands/build-plan-command.md`](../commands/build-plan-command.md) for the full reading surface per phase, and the §Reviewer exception below for the protocol summary.

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

### Mode C — Manual audit (Web Auditor only)

Spawned exclusively by `/check-web`. No context bundle, no spec/plan/task files prepared upfront. The orchestrator runs the Playwright walker first and produces a `raw-findings.json`; the agent reads that JSON as its primary input.

Read, in order:

1. **The agent's own definition** (`agents/web-auditor-agent.md`).
2. **`raw-findings.json`** for this audit — the walker's output. This is the equivalent of the context bundle in Mode A.
3. **`{project-docs}/web-flows.md`** if it exists — the agent's own append-only memo of confirmed expected behaviors. **Read this BEFORE specs**, never after.
4. **`{project-docs}/specs/INDEX.md`** — feature topology, used to map symptoms to features.
5. **Individual specs and source files** — on demand only, when a finding is not covered by `web-flows.md` and the agent needs to disambiguate "real bug, expected, or auditor misinterpreted".

The agent does NOT pre-load the full standards or specs directory. Discovery stays blind; consultation happens only on miss. This is what differentiates the auditor from the Tester (the Tester knows the spec; the auditor consults the spec).

The agent appends new entries to `{project-docs}/web-flows.md` only after confirming an interpretation against a spec — never speculatively. Each entry cites spec file + section + commit SHA. Append-only: stale entries are superseded, never edited or deleted.

## Role-specific Additions

Each agent adds only the files below to the Mode B list. Reference files (`*-reference.md`) are **on demand** — load them the first time a pattern appears, not by default.

| Agent | Always | On demand |
|---|---|---|
| Spec Analyzer | `design-decisions.md`, existing specs in the project docs folder | — |
| Backend Developer | [`backend.md`](backend.md), [`security.md`](security.md), [`performance.md`](performance.md), [`observability.md`](observability.md), [`api-contracts.md`](api-contracts.md) | [`caching.md`](caching.md) when the spec references cache behavior or the feature is read-heavy, [`secrets.md`](secrets.md) when the feature adds or reads a new secret, [`authorization.md`](authorization.md) when the feature adds a protected endpoint, introduces a new role, or touches a multi-tenant aggregate, [`i18n.md`](i18n.md) when the feature renders user-facing text, stores translatable content, or negotiates locale, [`gdpr-pii.md`](gdpr-pii.md) when the feature stores, reads, exports or deletes data identifying a natural person, [`llm-integration.md`](llm-integration.md) when the feature calls an LLM (Claude, OpenAI, Gemini, Mistral, self-hosted) at runtime, [`payments-and-money.md`](payments-and-money.md) when the feature charges, refunds, holds in escrow, pays out, splits revenue, or handles subscriptions, [`file-and-media-storage.md`](file-and-media-storage.md) when the feature stores user-uploaded or system-generated binary content (avatars, documents, video, attachments, exports), [`geo-search.md`](geo-search.md) when the feature stores locations, searches by proximity, ranks candidates with scoring, or renders maps, [`audit-log.md`](audit-log.md) when the feature performs an authorization-, money-, privacy-, legally-, security-, or configuration-significant action, [`feature-flags.md`](feature-flags.md) when the feature ramps gradually, hides work-in-progress, runs an A/B test, or stages a per-tenant or per-jurisdiction rollout, [`analytics-readonly-projection.md`](analytics-readonly-projection.md) when the feature renders dashboards, runs scheduled reports, powers product analytics, feeds a BI tool, or builds a read-replica/warehouse projection, [`pwa-offline.md`](pwa-offline.md) when the feature stores push subscriptions, accepts offline-write intents, or rate-limits push sends, [`digital-signature-integration.md`](digital-signature-integration.md) when the feature initiates a legally binding signature, stores a signed document, or verifies one, [`attack-surface-hardening.md`](attack-surface-hardening.md) when the project is reachable from the public internet (staging or production) — covers CSP/HSTS/CSRF/SSRF/lockout/bot/SBOM/container-scan/gitleaks/DAST, [`data-migrations.md`](data-migrations.md) when the feature modifies an existing table (column rename, type change, constraint tightening, removal), [`logging.md`](logging.md) (covered by `messenger-logging-middleware` skill), [`backend-reference.md`](backend-reference.md), [`new-service-checklist.md`](new-service-checklist.md), [`quality-gates.md`](quality-gates.md) |
| Frontend Developer | [`frontend.md`](frontend.md), [`security.md`](security.md), [`performance.md`](performance.md), [`observability.md`](observability.md), [`api-contracts.md`](api-contracts.md), `design-decisions.md` | [`caching.md`](caching.md) when wiring HTTP cache headers or consuming cached endpoints, [`secrets.md`](secrets.md) when adding a new `VITE_*` variable or consuming a backend-minted short-lived token, [`authorization.md`](authorization.md) when adding a route guard, role-gated UI, or handling 403 responses, [`i18n.md`](i18n.md) when rendering user-facing text, formatting dates/numbers/currency, or wiring vue-i18n, [`gdpr-pii.md`](gdpr-pii.md) when collecting PII via forms, building a consent UI, or handling a withdrawal flow, [`payments-and-money.md`](payments-and-money.md) when rendering money, capturing payment methods, or handling a payment confirmation page, [`file-and-media-storage.md`](file-and-media-storage.md) when wiring an upload form, rendering signed-URL images/videos, or showing upload progress, [`geo-search.md`](geo-search.md) when rendering a map, debouncing a search input, or displaying ranked match results, [`feature-flags.md`](feature-flags.md) when gating UI behind a flag, rendering experiment variants, or wiring a `useFlag` composable, [`pwa-offline.md`](pwa-offline.md) when configuring the service worker, manifest, offline reads/writes, push consent, or update flow, [`digital-signature-integration.md`](digital-signature-integration.md) when rendering a pre-sign document review, signing-state UX, or a verification surface, [`attack-surface-hardening.md`](attack-surface-hardening.md) when wiring CSP nonces, SRI on CDN scripts, allowlisted redirects, or the CSP-violation dashboard, [`frontend-reference.md`](frontend-reference.md), [`quality-gates.md`](quality-gates.md) |
| Backend Reviewer | [`critical-paths/`](critical-paths/) (PRIMARY-matched) + per-section reads of [`backend-review-checklist.md`](backend-review-checklist.md) (gap-cited) — see rule below | — |
| Frontend Reviewer | [`critical-paths/`](critical-paths/) (PRIMARY-matched) + per-section reads of [`frontend-review-checklist.md`](frontend-review-checklist.md) (gap-cited) — see rule below | `design-decisions.md` when diff touches UI |
| DoD Checker | The task file's `## Definition of Done` and the developer handoff's `## DoD coverage` section **only** — see [`dod-checker-agent.md`](../agents/dod-checker-agent.md). No standards file. | — |
| Tester | [`backend.md`](backend.md) or [`frontend.md`](frontend.md) (pick by test surface), [`security.md`](security.md) | [`logging.md`](logging.md) (covered by `messenger-logging-middleware` skill), [`backend-reference.md`](backend-reference.md) or [`frontend-reference.md`](frontend-reference.md) for first-time test patterns |
| DevOps | [`tech-stack.md`](tech-stack.md) (already in common core), [`secrets.md`](secrets.md), [`quality-gates.md`](quality-gates.md), root `docker-compose.yml`, service compose files | [`backend-reference.md`](backend-reference.md) for consumer-worker patterns, [`new-service-checklist.md`](new-service-checklist.md) when scaffolding a new service |
| Web Auditor | Mode C only — runs against `raw-findings.json` from the walker. No standards file. | `{project-docs}/web-flows.md`, `{project-docs}/specs/INDEX.md`, individual specs (only on miss in `web-flows.md`), source files (only to deduplicate findings) |

### Reviewer exception

Both reviewer agents follow a **coverage-aware** focusing protocol in every mode. The canonical 7 steps live in [`../agents/backend-reviewer-agent.md`](../agents/backend-reviewer-agent.md) and [`../agents/frontend-reviewer-agent.md`](../agents/frontend-reviewer-agent.md). Summary:

1. **Load every critical path matching a PRIMARY trigger** (each path's `## When to load this path` section declares them). Add SECONDARY paths only on coverage gap.
2. **Compute the union of `## Coverage map vs full checklist`** across loaded paths — that is the covered surface.
3. **Identify the GAP** = diff categories touched MINUS the coverage union, then load checklist SECTIONS in the gap only via `Read` `offset` + `limit`. Reading the full checklist file in one go is permitted ONLY when 3+ different sections are needed.
4. **Cite the gap** in the handoff for every section loaded (e.g. *"Loaded §Testing because diff includes `tests/Unit/MeServiceTest.php`; not covered by loaded paths (`auth-protected-action`, `pii-write-endpoint`)"*). A checklist load without citation is rejected as defensive overhead.

The reviewers NEVER read the underlying standards (`backend.md`, `security.md`, etc.) — those are for Developers. The full checklists (`backend-review-checklist.md` / `frontend-review-checklist.md`) remain the authoritative source from which the critical paths are extracted, but they are consulted per-section, not pre-loaded. If a reviewer sees a violation not covered by any loaded path AND not by the sections it loaded, it is reported as `minor` with a recommendation for which checklist section AND which critical path should cover it.

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
