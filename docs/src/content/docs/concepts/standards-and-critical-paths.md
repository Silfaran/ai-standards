---
title: Standards and critical paths
description: How architectural rules are organised — 33 standards, ~520 verifiable rules with stable IDs, 11 critical paths that scope reviewer attention per feature kind.
---

ai-standards encodes architectural rules at three layers: standards files (the source of truth), reviewer checklists (closed lists of verifiable rules with stable IDs), and critical paths (curated rule subsets per feature kind).

## Standards files

`standards/*.md` is the authoritative reference. ~33 files cover backend architecture, frontend architecture, security, performance, observability, GDPR/PII, payments, LLM integration, file storage, geo-search, audit log, feature flags, analytics, PWA, digital signatures, attack-surface hardening, data migrations, API contracts, secrets, and the ADR format.

Each standard splits into **rules** (concise, always loaded by agents — `<name>.md`, ~150 lines) and **reference** (full code examples, loaded conditionally — `<name>-reference.md`, ~500 lines).

Agents read selected standards via the [per-phase bundle](/ai-standards/concepts/per-phase-bundles/) the orchestrator generates per feature, not the full directory.

## Reviewer checklists

`standards/backend-review-checklist.md` and `standards/frontend-review-checklist.md` are closed lists of verifiable rules — every bullet has a stable ID like `BE-015` or `AZ-001`. Reviewers cite by ID, never by paraphrased prose.

The IDs follow a fixed prefix scheme — see [rule ID prefixes](/ai-standards/reference/rule-id-prefixes/) for the full table. Smoke tests validate format, uniqueness, and prefix legality on every push.

When a rule's prose changes, the ID stays. When a rule is deleted, its ID is never reassigned. This stability is what lets the framework cite "violates `BE-015`" in commit messages and lessons-learned without breaking when prose is refined.

## Critical paths

`standards/critical-paths/*.md` is the bridge between standards and reviewer effort. Each path declares: **for THIS kind of feature, these are the rules that always apply**. The reviewer loads the matching path(s) and walks through every rule, instead of opening the full ~520-rule checklist.

The 11 paths are:

| Kind | Use when the diff … |
|---|---|
| `crud-endpoint` | Adds a controller + handler + repository for a non-sensitive aggregate |
| `auth-protected-action` | Adds an action that requires a Voter check or role gating |
| `pii-write-endpoint` | Stores or updates personal data of a user |
| `payment-endpoint` | Charges, refunds, payouts, subscriptions, splits, PSP webhooks |
| `llm-feature` | Calls an LLM at runtime (classification, generation, translation) |
| `file-upload-feature` | Accepts or serves user-uploaded files / generated documents / video |
| `signature-feature` | Initiates, observes, or verifies a legally binding digital signature |
| `geo-search-feature` | Performs proximity search, ranked matching, or renders a map |
| `pwa-surface` | Configures the service worker, manifest, offline behaviour, push |
| `async-handler` | Adds or modifies a Symfony Messenger handler on an async transport |
| `public-facing-deploy` | Touches the perimeter of a public deploy (CSP, HSTS, CSRF/SSRF, …) |

Paths are designed to compose. A "professional registration" feature combines `crud-endpoint` + `auth-protected-action` + `pii-write-endpoint` + `file-upload-feature` (avatar) — the reviewer loads all four and runs them in order. Rules that appear in multiple paths are checked once.

See the [Critical paths reference](/ai-standards/reference/critical-paths/async-handler/) for each path's full rule set.

## How a path is structured

Every critical path declares two structural sections that the reviewer relies on:

### `## When to load this path`

Three classifications:

- **PRIMARY trigger** — strong signals that this path's rules always apply (e.g. *"new class implements `LlmGatewayInterface`"*). The reviewer loads the path when ANY primary trigger matches.
- **SECONDARY trigger** — weaker signals that load the path only when no PRIMARY-loaded path already covers the same rules.
- **DO NOT load when** — anti-patterns that explicitly exclude the path even if a trigger seems to match.

### `## Coverage map vs full checklist`

Lists every reviewer-checklist section the path claims to cover, with explicit rule-ID lists. This is what the [coverage-aware protocol](/ai-standards/concepts/coverage-aware-loading/) uses to compute the gap between "what the diff touches" and "what loaded paths cover".

## Always-up-to-date guarantee

This site does NOT duplicate the agents, commands, critical paths, or standards. The reference pages on this site are synced from the repo on every build (see `docs/scripts/sync.mjs`). Every page in the reference section starts with the marker:

> Synced verbatim from the repo on every site build. Edit the source file on GitHub (link in the page footer); do not edit the rendered copy here.

This guarantees the published docs cannot drift from the framework. If you spot a discrepancy, the source file on GitHub is authoritative — the rendered copy gets a fresh sync on the next push.
