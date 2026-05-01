# Critical-path sub-checklists

Curated rule subsets a Reviewer agent loads instead of the full backend / frontend checklist when the diff matches a known feature kind. The full checklists remain the authoritative reference; the sub-checklists are how the reviewer focuses.

## Why

The backend reviewer checklist carries ~375 rules across 25+ sections; the frontend checklist adds ~140 more. A typical "create a new CRUD endpoint" diff legitimately touches ~30 of them. Loading the entire ~515-rule surface defensively costs tokens, attention, and signal-to-noise — empirical measurement: ~30-50k Sonnet tokens wasted per Reviewer phase before PR #102.

A critical path declares: **for THIS kind of feature, these are the rules that always apply.** The reviewer loads the matching path, walks through every rule in it, and consults the full checklist ONLY for sections the loaded paths leave uncovered.

## How the reviewer picks a path (coverage-aware)

The canonical procedure is the 7-step protocol in [`../../agents/backend-reviewer-agent.md`](../../agents/backend-reviewer-agent.md) and [`../../agents/frontend-reviewer-agent.md`](../../agents/frontend-reviewer-agent.md). Summary:

1. **PRIMARY triggers first.** Each path's `## When to load this path` declares strong signals (new class, new endpoint, new column kind). Load every path with a matching PRIMARY trigger.
2. **SECONDARY only on coverage gap.** A SECONDARY trigger fires only when no PRIMARY-loaded path already covers the same rules.
3. **Compute the union of `## Coverage map vs full checklist`** across loaded paths — that is the covered surface.
4. **Identify the GAP** = diff categories touched (tests/, services.yaml, migrations, …) MINUS the coverage union.
5. **Load checklist SECTIONS in the gap only** — never the full checklist file. Use `Read` with `offset` + `limit` per section. Reading the full checklist file in one go is permitted ONLY when 3+ different sections are needed.
6. **Cite the gap** in the handoff for every section loaded (e.g. *"Loaded §Testing because diff includes `tests/Unit/MeServiceTest.php`; not covered by loaded paths (`auth-protected-action`, `pii-write-endpoint`)"*). A checklist load without citation is rejected as defensive overhead.

The reviewer NEVER skips a rule that appears in a loaded path. The path narrows the search; it does not relax the bar.

## Paths

| Kind | Use when the diff … |
|---|---|
| [`crud-endpoint.md`](crud-endpoint.md) | Adds a controller + handler + repository for a non-sensitive aggregate |
| [`auth-protected-action.md`](auth-protected-action.md) | Adds an action that requires a Voter check or role gating (most server-side actions) |
| [`pii-write-endpoint.md`](pii-write-endpoint.md) | Stores or updates personal data of a user (registration, profile edit, KYC submission) |
| [`payment-endpoint.md`](payment-endpoint.md) | Charges, refunds, payouts, subscriptions, splits, or webhook handlers from a PSP |
| [`llm-feature.md`](llm-feature.md) | Calls an LLM at runtime (classification, generation, translation, embedding) |
| [`file-upload-feature.md`](file-upload-feature.md) | Accepts or serves user-uploaded files / generated documents / video |
| [`signature-feature.md`](signature-feature.md) | Initiates, observes, or verifies a legally binding digital signature |
| [`geo-search-feature.md`](geo-search-feature.md) | Performs proximity search, ranked matching, or renders a map |
| [`pwa-surface.md`](pwa-surface.md) | Configures the service worker, manifest, offline behaviour, or push notifications |
| [`async-handler.md`](async-handler.md) | Adds or modifies a Symfony Messenger handler on an async transport (domain-event consumer, application-message handler, async write command per ADR-009) — covers idempotency, DLQ wiring, failure subscriber, retry, worker resource discipline |
| [`public-facing-deploy.md`](public-facing-deploy.md) | Touches the perimeter of a public deploy — CSP, HSTS, CSRF/SSRF, container build, dependency automation, secrets scanning, DAST |

The exact rules each path loads are listed in its own file. The "rules loaded" count column was removed because it drifted on every standards expansion without being load-bearing — read the path file for the authoritative subset.

## Compositional usage

A "professional registration" feature may combine `crud-endpoint` + `auth-protected-action` + `pii-write-endpoint` + `file-upload-feature` (avatar). The reviewer loads all four and runs them in order; rules that appear in multiple paths are checked once.

## Maintenance

When a new standard ships and its rules apply to one or more existing kinds:

1. Add the new rule IDs to every matching path.
2. Update the path's `## Coverage map vs full checklist` section so reviewers can compute the gap correctly.
3. The smoke check `§Critical-path rule IDs` (`scripts/smoke-tests.sh`) verifies that every rule ID cited in `critical-paths/*.md` exists as a declared bullet in one of the reviewer checklists. A separate check (`§Critical paths coverage + triggers`) verifies that every path declares the `## Coverage map vs full checklist` and `## When to load this path` sections with PRIMARY / SECONDARY / DO NOT load classification. A typo or a removed structural section fails CI.

When a brand-new kind emerges (e.g. "blockchain transaction"), add a new path file and update this README.
