---
title: Rule ID prefixes
description: The 23 stable prefixes used in reviewer checklists — every architectural rule has a stable identifier so violations can be cited unambiguously.
---

Every bullet in the reviewer checklists carries a stable ID so a violation can be cited unambiguously — *"violates `BE-015`"* beats quoting the full prose. The prefix reflects the source-standard domain, not the checklist file.

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
| `DS-*` | Digital signatures (`SignatureGatewayInterface`, modality, templates, document hashing, retention) | `digital-signature-integration.md` |
| `AS-*` | Attack surface hardening (CSP, HSTS, CSRF, SSRF, deserialisation, lockout, bot, outbound webhook signing, SBOM, container scan, gitleaks, DAST) | `attack-surface-hardening.md` |

## Invariants of the ID scheme

- **Format**: `<PREFIX>-<3 digits>`, e.g. `BE-015`. Regex: `^(BE|FE|SE|PE|OB|CA|SC|DM|AC|LO|AZ|IN|GD|LL|PA|FS|GS|AU|FF|AN|PW|DS|AS)-\d{3}$`.
- **Stability**: IDs are never reassigned. A rule that is deleted leaves a gap in the sequence; a new rule takes the next free integer in its prefix (not the gap).
- **Global uniqueness**: an ID never refers to two different rules. When a rule applies to both backend and frontend (e.g. `SE-003` — no SSL verification disabled), the same ID appears in both checklists.
- **New rules**: when a reviewer flags a missing rule, the orchestrator assigns the next free ID in the matching prefix. Contributors do not invent IDs.

## How rule IDs are validated

`scripts/smoke-tests.sh` enforces:

- **Check 7** — every bullet in both reviewer checklists carries a valid `<PREFIX>-<3 digits>` ID; no unknown prefixes; no within-file duplicates.
- **Check 8** — every ID cited in `standards/*.md` resolves to a declared bullet in one of the reviewer checklists (catches stale cross-references).
- **Check 9** — every ID cited in `standards/critical-paths/*.md` resolves to a declared bullet (catches typos and removed rules).
- **Check 20** — the dynamic-smoke fixture's rule-ID alternation regex stays in sync with the 23-prefix valid set.

Format violations and prefix typos fail CI on every push.
