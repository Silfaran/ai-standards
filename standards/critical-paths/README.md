# Critical-path sub-checklists

Curated rule subsets a Reviewer agent loads instead of the full backend / frontend checklist when the diff matches a known feature kind. The full checklists remain the authoritative reference; the sub-checklists are how the reviewer focuses.

## Why

After the 12-standard sprint, the backend reviewer checklist carries ~280 rules across 22+ sections. A typical "create a new CRUD endpoint" diff legitimately touches ~30 of them. Loading the entire checklist costs tokens, attention, and signal-to-noise.

A critical path declares: **for THIS kind of feature, these are the rules that always apply.** The reviewer loads the matching path, runs through it, and only opens the full checklist if the diff strays into a section the path does not cover.

## How the reviewer picks a path

1. Read the diff and the feature handoff.
2. Identify the dominant feature kind from the table below. A diff may match more than one path (e.g. an LLM-driven payment feature) — the reviewer loads ALL matching paths.
3. Run through every rule in every loaded path.
4. Open the full checklist only if a rule cited by the standard does not appear in any loaded path — flag the gap as a `minor` for the path to be extended.

The reviewer NEVER skips a rule that appears in a loaded path. The path narrows the search; it does not relax the bar.

## Paths

| Kind | Use when the diff … | Rules loaded |
|---|---|---|
| [`crud-endpoint.md`](crud-endpoint.md) | Adds a controller + handler + repository for a non-sensitive aggregate | ~35 |
| [`auth-protected-action.md`](auth-protected-action.md) | Adds an action that requires a Voter check or role gating (most server-side actions) | ~25 |
| [`pii-write-endpoint.md`](pii-write-endpoint.md) | Stores or updates personal data of a user (registration, profile edit, KYC submission) | ~30 |
| [`payment-endpoint.md`](payment-endpoint.md) | Charges, refunds, payouts, subscriptions, splits, or webhook handlers from a PSP | ~45 |
| [`llm-feature.md`](llm-feature.md) | Calls an LLM at runtime (classification, generation, translation, embedding) | ~30 |
| [`file-upload-feature.md`](file-upload-feature.md) | Accepts or serves user-uploaded files / generated documents / video | ~35 |
| [`signature-feature.md`](signature-feature.md) | Initiates, observes, or verifies a legally binding digital signature | ~35 |
| [`geo-search-feature.md`](geo-search-feature.md) | Performs proximity search, ranked matching, or renders a map | ~35 |
| [`pwa-surface.md`](pwa-surface.md) | Configures the service worker, manifest, offline behaviour, or push notifications | ~25 |

## Compositional usage

A "professional registration" feature may combine `crud-endpoint` + `auth-protected-action` + `pii-write-endpoint` + `file-upload-feature` (avatar). The reviewer loads all four and runs them in order; rules that appear in multiple paths are checked once.

## Maintenance

When a new standard ships and its rules apply to one or more existing kinds:

1. Add the new rule IDs to every matching path.
2. The smoke check (`scripts/smoke-tests.sh` check #10) verifies that every rule ID cited in `critical-paths/*.md` exists as a declared bullet in one of the reviewer checklists. A typo or a removed rule fails CI.

When a brand-new kind emerges (e.g. "blockchain transaction"), add a new path file and update this README.
