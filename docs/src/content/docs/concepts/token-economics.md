---
title: Token economics
description: Real per-phase token costs from production-like consumer use — measured via the Anthropic SDK's total_tokens field, not estimated.
---

Every `/build-plan` run emits a per-phase token cost table at the end. The numbers below are real measurements from `total_tokens` reported directly by each subagent (PR #110), not line-count estimates.

## Two measured features

These are the first two real `/build-plan` runs in red-profesionales after PRs #100/#102/#104 shipped (the coverage-aware loading + anti-duplication + DoD-checker budget).

### Feature 1 — backend (single iter, no fast mode)

| Phase | Model | Tool uses | Total tokens | Duration |
|---|---|---:|---:|---:|
| Bundle generator | sonnet | 38 | 111,362 | 10m 38s |
| Backend Developer | opus | 98 | 234,487 | 15m 32s |
| DoD-checker | haiku | 35 | 55,462 | 1m 16s |
| Backend Reviewer | sonnet | 47 | **84,434** | 5m 19s |
| Tester | sonnet | 42 | 62,746 | 4m 27s |
| update-specs | opus | 24 | 109,922 | 2m 31s |
| **Total subagents** | — | 284 | **658,413** | ~40 min |

### Feature 2 — frontend (2 iters, fast mode on iter 2)

| Phase | Model | Tool uses | Total tokens | Duration |
|---|---|---:|---:|---:|
| Frontend Dev iter 1 | opus | 50 | 115,078 | 8m 45s |
| DoD-checker | haiku | 27 | 52,062 | 1m 25s |
| Frontend Reviewer iter 1 | sonnet | 107 | **94,851** | 10m 31s |
| Frontend Dev iter 2 | opus | 25 | 79,274 | 3m 24s |
| Frontend Reviewer iter 2 (fast) | sonnet | 14 | **47,169** | 1m 36s |
| Tester | sonnet | 42 | 105,517 | 8m 24s |
| **Total subagents** | — | 265 | **493,951** | ~34 min |

## What the data confirms

**Reviewer savings predicted by PRs #102/#104 (30-50k Sonnet/phase) — confirmed at N=2:**

| Phase | Before | After (measured) | Predicted | Verdict |
|---|---:|---:|---:|---|
| Reviewer (feature 1) | ~130k | 84k | 80-100k | ✓ bullseye |
| Reviewer iter 1 (feature 2) | ~130k | 95k | 80-100k | ✓ in band |
| Reviewer iter 2 fast | — | 47k | ~50% iter 1 | ✓ ~50% |

The fast re-review mode (PR #96) also performs as designed — 47k iter 2 = 50% of 95k iter 1.

## Per-tool-use efficiency

| Phase | Total tokens | Tool uses | Tokens / tool use |
|---|---:|---:|---:|
| Reviewer iter 1 (F2) | 94,851 | 107 | 886 |
| DoD-checker (F2) | 52,062 | 27 | 1,928 |
| Reviewer iter 2 fast (F2) | 47,169 | 14 | 3,369 |
| Tester (F2) | 105,517 | 42 | **2,512** |
| Frontend Dev iter 1 (F2) | 115,078 | 50 | 2,302 |
| Frontend Dev iter 2 (F2) | 79,274 | 25 | 3,171 |

The Reviewer's 886 tokens/tool-use is the lowest — coverage-aware loading produces many small, targeted reads instead of a single full-checklist load. The DoD-checker's 1,928/use stays inside its declared budget (max 2 tool calls per row).

The **Tester's 2,512 tokens/tool-use** is the cost frontier today. Frontend Tester at 105k vs backend Tester at 62k is a 70% gap. Possible causes under investigation: more test cases (27 vs ~8), heavier tool surface (Vitest + jsdom + sometimes Playwright vs PHPUnit), and full-loads of `logging.md` / `gdpr-pii.md` / `attack-surface-hardening.md` in the tester-bundle (PR #112 introduced section-loading; pending empirical confirmation on next frontend feature).

## Approximate cost per `/build-plan`

Using public Anthropic pricing as an order-of-magnitude:

| Model | Tokens (sum across F1+F2) | Approx cost |
|---|---:|---:|
| Opus (Backend Dev + Frontend Dev + update-specs) | ~538k | $4-7 |
| Sonnet (Bundle + Reviewer + Tester) | ~505k | $1.5-3 |
| Haiku (DoD-checker × 2) | ~107k | $0.10-0.20 |
| **Subtotal subagents** | **~1.15M** | **$6-10** |
| Orchestrator overhead (Opus, NOT in per-subagent total) | ~200-400k each run | $1-3 each run |
| **Total per `/build-plan`** | — | **~$8-13 per feature** |

For comparison, the same feature implemented by a developer using Cursor + 4-6h of their time costs roughly the same in tooling but consumes the developer's day. The framework's value-add is parallelism (BE ‖ FE), enforced architecture, and a Reviewer-approved + tested deliverable at the end.

## What's instrumented

PR #110 replaced the prior lines × 8 estimate with the Anthropic SDK's `total_tokens` field per subagent. The orchestrator emits the table verbatim at the end of every `/build-plan` run. Future regressions in any phase become visible per-feature rather than having to be inferred from aggregate cost.

## What's not yet instrumented

- **Orchestrator overhead.** The 200-400k Opus tokens the orchestrator itself consumes (system prompt, build-plan-command.md, lessons-learned reads, accumulated tool results) is not in the per-subagent table. Adding it is non-trivial because the orchestrator is the conversation, not a subagent.
- **Per-section checklist read cost.** Reviewer's per-section reads via `offset` + `limit` are not separately instrumented; only the aggregate Reviewer cost is visible.
- **Cache hit rate.** Anthropic's prompt cache is leveraged via static-first prefix ordering, but the framework does not currently report cache-hit vs cache-miss tokens. Adding this requires the SDK's cached-input-tokens telemetry.
