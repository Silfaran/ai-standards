# AI Standards

## Purpose

Global standards, conventions, and agent definitions for all projects in this workspace.
Every service must have a `CLAUDE.md` referencing this file.

- **Invariants (read first): `ai-standards/standards/invariants.md`** — rules that cannot be overridden under any circumstances
- **Agent reading protocol: `ai-standards/standards/agent-reading-protocol.md`** — canonical order every agent must follow (build-plan mode + standalone mode)
- **Tech stack: `ai-standards/standards/tech-stack.md`** — authoritative versions (all values are minimums, open to update) and upgrade procedure
- Agent definitions: `ai-standards/agents/`
- Commands: `ai-standards/commands/` (full implementations, referenced by the `.claude/commands/` stubs)
- Manual audit mode: `/check-web` invokes the **Web Auditor** agent (`agents/web-auditor-agent.md`) via the Playwright walker at `scripts/check-web/`. Read-only navigation of a deployed UI; produces paste-ready `/create-specs` prompts grouped by inferred root cause. The agent maintains an append-only memo at `{project-docs}/web-flows.md` (confirmed expected behaviors and previous false positives) so each session needs to read fewer specs than the last. Never automated — manual on-demand only.
- Templates: `ai-standards/templates/`
- Scaffold files: `ai-standards/scaffolds/` — copy-verbatim PHP classes. Baseline: `AppController`, `ApiExceptionSubscriber`, `LoggingMiddleware`, `SecurityHeadersSubscriber`. Domain patterns extracted from the 13 generalist standards: `Subject` + `Voter` (authorization.md), `Money` + `CurrencyMismatchException` (payments-and-money.md), `SafeHttpClient` + `SsrfBlockedException` (attack-surface-hardening.md), `LlmGatewayInterface` + `LlmRequest` + `LlmResponse` (llm-integration.md), `AuditLogProjector` (audit-log.md), `AssertMaxQueriesTrait` + `QueryCountMiddleware` (performance.md PE-018). Copy verbatim, then adapt the placeholder names to the project's aggregates.
- Agent model-tier hook template: `ai-standards/templates/agent-model-hook.json` — `PreToolUse` hook installed by `/init-project` into `{workspace-root}/.claude/settings.json`; enforces the tier declared in each agent's `## Model` section (see "Agent model tiering" below)
- **Skills: `ai-standards/.claude/skills/`** — on-demand playbooks (CORS, Docker env reload, migrations, JWT, Vitest patterns, ...). Claude auto-loads a skill only when it matches the active task or file paths; description-only otherwise. See `USAGE.md` → Skills reference for the full catalog.
- Backend standards: `ai-standards/standards/backend.md` (rules) / `backend-reference.md` (full examples)
- Frontend standards: `ai-standards/standards/frontend.md` (rules) / `frontend-reference.md` (full examples)
- Logging standards: `ai-standards/standards/logging.md`
- Security standards: `ai-standards/standards/security.md`
- Attack surface hardening: `ai-standards/standards/attack-surface-hardening.md` — OWASP Top 10 coverage map + CSP / HSTS / cookie security / COOP-COEP-CORP, CSRF on cookie-auth SPAs, `SafeHttpClient` for SSRF, XXE / SSTI / command-injection / deserialization rules, username-enumeration & lockout, bot protection, open-redirect (backend), outbound-webhook signing, dependency automation (Dependabot/Renovate, SBOM, container Trivy scan, gitleaks), DAST in CI, anomaly metrics. Read whenever the project is reachable from the public internet (staging or production).
- Authorization standards: `ai-standards/standards/authorization.md` — Voter pattern, Subject VO, tenant scoping, RBAC + ABAC hybrid model. Read when the system has more than one role beyond authenticated, has resource owners, is multi-tenant, or has different rules per action on the same resource.
- Internationalization standards: `ai-standards/standards/i18n.md` — locale negotiation, UI strings vs content translations, fallback chain, plurals/dates/currency formatting, frontend `vue-i18n` integration. Read when the product ships in more than one language, accepts user-generated content from multi-language users, or targets users in more than one country.
- GDPR / PII standards: `ai-standards/standards/gdpr-pii.md` — four-tier classification (Public / Internal-PII / Sensitive-PII / Derived), pii-inventory.md, column-level encryption for sensitive fields, DSAR + RTBF workflow, consent ledger, sub-processor list, DPIA template. Read when the system stores any data identifying a natural person (name, email, phone, government ID, photo, behavioural data tied to an account).
- LLM integration standards: `ai-standards/standards/llm-integration.md` — `LlmGatewayInterface` Domain seam, versioned prompt templates, JSON-mode + schema validation, retry/circuit-breaker, prompt-caching discipline, cost observability (`llm.cost_micro_dollars`), `PiiPromptGuard`, tool-use loop cap. Read whenever the product code calls a Large Language Model (Claude, OpenAI, Gemini, Mistral, self-hosted) at runtime — not for the ai-standards orchestrator pipeline itself.
- Payments & money standards: `ai-standards/standards/payments-and-money.md` — `Money` value object (integer minor units + ISO 4217), append-only double-entry ledger, deterministic webhook idempotency, signature-verify-before-parse, state machines per payment object, multi-party splits, daily reconciliation, hosted card capture on the frontend. Read whenever the system charges, refunds, holds in escrow, pays out, splits revenue, or handles subscriptions.
- File & media storage standards: `ai-standards/standards/file-and-media-storage.md` — bucket layout (public vs private separated by name), presigned PUT/GET flow, scoped URLs with TTL ≤ 15 min, magic-byte verification, antivirus scan as state machine, video transcode pipeline + signed playback, captions as variants, retention + orphan detection, observability metrics. Read whenever the system stores user-uploaded or system-generated binary content.
- Geo & search standards: `ai-standards/standards/geo-search.md` — `geography(Point, 4326)` storage, GiST indexes, ST_DWithin/bbox/polygon query patterns, Postgres FTS (`tsvector` + GIN + `pg_trgm`) before any dedicated search engine, combined geo+text+structured CTE queries, `MatchScoreCalculator` (pure Domain service), score → qualitative label translation, explanations transparency, frontend bbox fetching + clustering. Read whenever the system stores locations, searches by proximity, ranks candidates, or renders maps.
- Audit log standards: `ai-standards/standards/audit-log.md` — append-only `audit_log` table with strict schema, AuditLogProjector wiring via domain events, same-tx-or-outbox synchrony, mandatory entries on success AND denial, structured per-action `metadata` (no PII), retention + archival, separation from operational logging. Read whenever the system performs an authorization-, money-, privacy-, legally-, security-, or configuration-significant action.
- Feature flags standards: `ai-standards/standards/feature-flags.md` — flag taxonomy (release / operational / experiment / permission), `feature-flags.md` registry as single source of truth, `FlagGatewayInterface` Domain seam, sticky bucketing for experiments, no-PII evaluation context, conservative defaults, mandatory removal procedure for release flags, observability + audit on toggles. Read whenever the system needs to ramp a feature, hide work-in-progress, run an A/B test, or stage a rollout per tenant/jurisdiction.
- Analytics & projections standards: `ai-standards/standards/analytics-readonly-projection.md` — four-tier projection model (T1 read-on-operational / T2 materialized view / T3 replica / T4 warehouse), schema isolation under `analytics`, refresh discipline, replica lag tolerance, warehouse loaders as infrastructure (not application code), privacy preserved across projections, mandatory Voter on every analytics endpoint, cacheability + observability per tier. Read whenever the system needs dashboards, scheduled reports, product analytics, BI tool feeds, or ML feature stores.
- PWA & offline standards: `ai-standards/standards/pwa-offline.md` — four progressive levels (L0 plain SPA → L1 installable → L2 offline reads → L3 offline writes + push), Workbox-generated service worker, recommended cache strategies per request kind, manifest shape, update flow with explicit user consent, IndexedDB never holding Sensitive-PII, push consent per category audited, conflict policies for L3 writes. Read whenever the product is installable, needs to function on flaky networks, supports offline reads/writes, or sends push notifications.
- Digital signature integration standards: `ai-standards/standards/digital-signature-integration.md` — `SignatureGatewayInterface` Domain seam (Signaturit / DocuSign / Adobe Sign / Yousign / etc.), modality choice (simple / advanced / qualified) per use case + jurisdiction, versioned templates owned by the system, `SigningRequest` state machine, signed-document storage in private bucket with independent `document_sha256`, signature-verify-before-parse webhooks, retention exceeds RTBF for legal documents, audit entries on every signing event. Read whenever the system needs a legally binding signature on a document.
- Secrets standards: `ai-standards/standards/secrets.md`
- Performance standards: `ai-standards/standards/performance.md`
- Caching standards: `ai-standards/standards/caching.md`
- Observability standards: `ai-standards/standards/observability.md`
- Data migrations standards: `ai-standards/standards/data-migrations.md`
- API contracts & breaking-change protocol: `ai-standards/standards/api-contracts.md`
- New service scaffold checklist: `ai-standards/standards/new-service-checklist.md`
- Architecture Decision Records (ADR) format: `ai-standards/standards/adr.md` — ID convention, status lifecycle (proposed/accepted/deprecated/superseded), structure, when to write one. Entry template at `templates/adr-entry-template.md`. ADRs themselves live in `{project-docs}/decisions.md`, not in this repo.
- Quality gates: `ai-standards/standards/quality-gates.md` — PHPStan L9, vue-tsc strict, PHP-CS-Fixer, ESLint/Prettier, test suite, dependency audits; installed per service via `templates/`
- Reviewer checklists: `ai-standards/standards/backend-review-checklist.md` / `frontend-review-checklist.md` — closed list of verifiable rules consumed by Backend/Frontend Reviewer agents instead of the full standards. Every rule has a stable ID (`BE-*`, `FE-*`, `SE-*`, `PE-*`, `OB-*`, `CA-*`, `SC-*`, `DM-*`, `AC-*`, `LO-*`) — see "Rule IDs" below. **When you add or change a rule in any standards file, update the matching checklist entry in the same commit** — otherwise reviewers will silently miss new rules.
- Critical-path sub-checklists: `ai-standards/standards/critical-paths/` — curated rule subsets per feature kind (CRUD endpoint, authorization-protected action, PII write, payment endpoint, LLM feature, file upload, signature feature, geo-search feature, PWA surface, async message handler, public-facing deploy). Reviewer agents follow a coverage-aware protocol: identify PRIMARY-trigger paths from the diff, add SECONDARY only on coverage gap, then load checklist sections in the gap only (with citation), instead of pre-loading the full ~515-rule surface. The full checklists remain authoritative; the paths are how the reviewer focuses. See `critical-paths/README.md` and the 7-step protocol in each reviewer agent file for the routing rules.
- Project config lookup: `ai-standards/.workspace-config-path` (gitignored, one line created by `init-project`) points to the current project's docs repo — typically `../{project-name}-docs`. The real config files (`workspace.md`, `workspace.mk`, `services.md`, specs, decisions, lessons-learned) all live **inside that docs repo**, not in `ai-standards/`. To discover any project path, read `.workspace-config-path` first, then read `{docs-dir}/workspace.md`.

## Tech Stack

See [`standards/tech-stack.md`](standards/tech-stack.md) for the authoritative list of technologies, minimum versions (all values are floors — newer compatible releases are welcome), and the upgrade procedure. Do not restate versions in other files.

## General Naming Conventions

| Context | Convention | Example |
|---|---|---|
| PHP classes | PascalCase | `UserFinderService` |
| PHP methods & variables | camelCase | `findByEmail()`, `$userId` |
| API payload parameters | snake_case | `first_name`, `created_at` |
| Database tables | snake_case | `user_boards` |
| Database columns | snake_case | `created_at`, `board_id` |
| All table primary keys | UUID v4 | `id UUID DEFAULT gen_random_uuid()` |
| Vue components | PascalCase | `UserCard.vue` |
| TypeScript variables & methods | camelCase | `findUser()`, `userId` |

## AI Behavior Rules

All agents follow the canonical reading order defined in [`standards/agent-reading-protocol.md`](standards/agent-reading-protocol.md) — both the build-plan subagent mode (context bundle only) and the standalone mode (full file set). The protocol also defines role-specific additions and the handoff rules; do not restate them in agent definitions.

The reading protocol is binding. If it conflicts with an older instruction elsewhere, the protocol wins.

### Agent model tiering

Every agent definition in `agents/` declares a `## Model` section with the Claude tier it must run on (`Opus` or `Sonnet`). The orchestrator (`/build-plan` and any other command that spawns an agent) is required to read that value from the agent definition file and pass it to the `Agent` tool's `model` parameter. **Never spawn an agent without an explicit `model` argument.**

The tier is assigned by two rules, applied in order:

1. **Generates new content → Opus.** Errors propagate downstream with no safety net (spec-analyzer, backend-developer, frontend-developer).
2. **Verifies against a closed checklist or fills templates → Sonnet.** The reasoning is already compressed into the artifact being consumed (backend-reviewer, frontend-reviewer, tester).
3. **Correct for call frequency.** If a rail-guided agent runs rarely per feature, upgrade to Opus because the aggregate cost is marginal but the impact of a mistake is outsized. This is why DevOps runs on Opus despite being mostly copy-from-template.

Use the generic tier name (`Opus`, `Sonnet`) — never hardcode a version (`Opus 4.7`) in the agent definition. The `Agent` tool accepts `opus` / `sonnet` / `haiku` and resolves to the latest available.

When adding a new agent, classify first, then correct for frequency. Do not downgrade a generator to Sonnet without strong evidence that the downstream pipeline is robust enough to catch its mistakes.

### Rule IDs

Every bullet in the reviewer checklists (`backend-review-checklist.md`, `frontend-review-checklist.md`) carries a stable ID so a violation can be cited unambiguously (`"violates BE-015"` beats quoting the full prose). The prefix reflects the source-standard domain, not the checklist file:

| Prefix | Domain | Source standard |
|---|---|---|
| `BE-*` | Backend architecture, handlers, controllers, validation, testing | `backend.md` |
| `FE-*` | Frontend architecture, stores, composables, TypeScript, routing | `frontend.md` |
| `SE-*` | Security (CORS, JWT, XSS, rate limiting, headers, redirects) | `security.md` |
| `PE-*` | Performance (DB indexing, N+1, pagination, Web Vitals, Vite bundle) | `performance.md` |
| `OB-*` | Observability (tracing, metrics, health endpoints, SLOs) | `observability.md` |
| `CA-*` | Caching (HTTP cache, Redis keys, TTLs, invalidation) | `caching.md` |
| `SC-*` | Secrets (manifest, injection, rotation, `.env.example`) | `secrets.md` |
| `DM-*` | Data migrations (expand-contract, backfills, compatibility matrix) | `data-migrations.md` |
| `AC-*` | API contracts (versioning, OpenAPI, deprecation, payload shape) | `api-contracts.md` |
| `LO-*` | Logging (structure, redaction, middleware wiring) | `logging.md` |
| `AZ-*` | Authorization (Voter pattern, Subject VO, tenant scoping, route guards) | `authorization.md` |
| `IN-*` | Internationalization (locale negotiation, translations storage, fallback chain, formatting) | `i18n.md` |
| `GD-*` | GDPR / PII (classification, encryption, DSAR/RTBF, consent, sub-processors, DPIA) | `gdpr-pii.md` |
| `LL-*` | LLM integration (gateway seam, prompt versioning, schema validation, cost spans, PII guard) | `llm-integration.md` |
| `PA-*` | Payments & money (Money VO, ledger, webhook idempotency, state machines, reconciliation) | `payments-and-money.md` |
| `FS-*` | File & media storage (buckets, presigned URLs, antivirus, magic-byte, video pipeline) | `file-and-media-storage.md` |
| `GS-*` | Geo & search (PostGIS, FTS, MatchScoreCalculator, label translation, map rendering) | `geo-search.md` |
| `AU-*` | Audit log (append-only table, projector wiring, denial trails, retention) | `audit-log.md` |
| `FF-*` | Feature flags (registry, gateway, sticky bucketing, removal procedure, observability) | `feature-flags.md` |
| `AN-*` | Analytics projections (tier model, materialized views, replicas, warehouse loaders, privacy) | `analytics-readonly-projection.md` |
| `PW-*` | PWA & offline (service worker, cache strategies, manifest, offline reads/writes, push) | `pwa-offline.md` |
| `DS-*` | Digital signatures (SignatureGatewayInterface, modality, templates, document hashing, retention) | `digital-signature-integration.md` |
| `AS-*` | Attack surface hardening (CSP, HSTS, CSRF, SSRF, deserialisation, lockout, bot, outbound webhook signing, SBOM, container scan, gitleaks, DAST) | `attack-surface-hardening.md` |

**Invariants of the ID scheme:**

- **Format:** `<PREFIX>-<3 digits>`, e.g. `BE-015`. Regex: `^(BE|FE|SE|PE|OB|CA|SC|DM|AC|LO|AZ|IN|GD|LL|PA|FS|GS|AU|FF|AN|PW|DS|AS)-\d{3}$`.
- **Stability:** IDs are never reassigned. A rule that is deleted leaves a gap in the sequence; a new rule takes the next free integer in its prefix (not the gap).
- **Global uniqueness:** an ID never refers to two different rules. When a rule applies to both backend and frontend (e.g. `SE-003` — no SSL verification disabled), the same ID appears in both checklists.
- **New rules:** when a reviewer flags a missing rule (see the footer of each checklist), the orchestrator assigns the next free ID in the matching prefix. Contributors do not invent IDs.

The `smoke` CI job validates format, uniqueness and prefix legality on every push.

### Specs & Documentation

- Specs must be written before any code — never implement without a validated spec
- Specs, plans and tasks live in the path defined in `{project-docs}/workspace.md` (resolve `{project-docs}` from `ai-standards/.workspace-config-path`)
- `{project-name}-docs/specs/INDEX.md` is the quick-reference index — always read this before deep-reading full specs
- Specs are version-controlled — every spec update must be committed
- When running as a `build-plan` subagent, read the **per-phase bundle** named in your prompt (`dev-bundle.md` for Developer / Dev+Tester / DevOps, `tester-bundle.md` for the Tester — both under `{workspace_root}/handoffs/{feature}/`, path defined in `{project-docs}/workspace.md` under the `handoffs:` key) instead of individual standards files. The bundle contains the distilled rules relevant to the current feature; Reviewers and the DoD-checker do not receive a bundle (see [`commands/build-plan-command.md`](commands/build-plan-command.md))

### Commit convention

Every commit to `ai-standards/` master must use [Conventional Commits](https://www.conventionalcommits.org/). The release-please Action reads this history to maintain the release PR, generate `CHANGELOG.md` entries and compute the next version bump. Getting the prefix wrong means the change is either invisible in the CHANGELOG or bumps the wrong version component.

| Prefix | CHANGELOG section | Version bump (pre-1.0) |
|---|---|---|
| `feat:` | Added | minor (0.1.0 → 0.2.0) |
| `fix:` | Fixed | patch (0.1.0 → 0.1.1) |
| `refactor:` / `perf:` | Changed | patch |
| `docs:` | Documentation | patch |
| `chore:` / `ci:` / `test:` / `style:` / `build:` | hidden | no bump on its own |

Breaking changes: append `!` after the type (e.g. `refactor!: move workspace.md to docs repo`) **or** include a `BREAKING CHANGE:` trailer in the body. Pre-1.0 this promotes the bump to minor; post-1.0 it will trigger a major.

Commit scope (optional but recommended) matches the area: `feat(skill): add x`, `refactor(workspace): …`, `docs(readme): …`.

### Release process

Releases are cut by [release-please](https://github.com/googleapis/release-please) — see [`.github/workflows/release-please.yml`](.github/workflows/release-please.yml).

Flow:
1. You push commits to `master` following the convention above.
2. The `Release Please` Action opens (or updates) a PR titled `chore(master): release X.Y.Z`. The PR's diff is the CHANGELOG update plus a bump in `.release-please-manifest.json`. **Never edit `CHANGELOG.md` by hand** — release-please owns it. Manual edits get overwritten on the next push.
3. Review the PR. If the computed version or CHANGELOG section assignments are wrong, fix the offending commit message with a follow-up commit (e.g. an empty commit with a corrected `BREAKING CHANGE:` trailer).
4. Merge the release PR. release-please then creates the git tag (`v0.2.0`) and a GitHub Release with the CHANGELOG excerpt as the release notes.

The tag pointed to by the manifest is the most recent released version. `Unreleased` in `CHANGELOG.md` is populated by release-please from post-tag commits.

### Git (main conversation only — subagents do not perform git operations)

- Main branch: `master`
- Always work from `master` — every new branch is created from an up-to-date `master`
- Branch naming: `feature/{aggregate}/{description}`, `fix/{aggregate}/{description}`, `hotfix/{description}`
- `build-plan` workflow:
  1. **Pre-flight check**: before creating a feature branch in any affected repo, verify HEAD is on `master`. If not, ask the developer to merge the current branch into `master` first, continue on the existing branch, or abort — never silently branch from a non-master HEAD.
  2. Creates the feature branch from `master` and commits after the last agent.
  3. **Post-feature merge prompt**: after committing, asks the developer if the feature should be merged into `master`. If yes, merges + pushes in every affected repo and leaves all repos checked out on `master`.
- Any other command that creates branches must apply the same pre-flight master check.
- Never push or create pull requests without explicit developer confirmation (see `invariants.md`)

### Makefile

Every service must implement at minimum:
- `make up` / `make down` / `make build` / `make update`
- `make test` / `make test-unit` / `make test-integration`

The root Makefile in `ai-standards/` orchestrates all services and adds:
- `make infra-up` / `make infra-down` — start/stop shared infrastructure only (PostgreSQL, RabbitMQ, Mailpit)
- `make up` — starts infrastructure first, then all services
- `make ps` — shows status of infrastructure + all services
