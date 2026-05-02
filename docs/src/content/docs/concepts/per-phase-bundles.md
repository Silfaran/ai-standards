---
title: Per-phase bundles
description: How the orchestrator builds two compact bundles (dev + tester) that distill only the rules relevant to the current feature, instead of every subagent re-reading 4-5 full standards files.
---

Before any subagent spawns, `/build-plan` Step 0.5 generates two bundle files under `{workspace_root}/handoffs/{feature-name}/`:

| Bundle | Consumed by | Target size | Contents |
|---|---|---|---|
| `dev-bundle.md` | Backend Developer, Frontend Developer, Dev+Tester (simple flow), DevOps | 200–400 lines | Invariants + naming/git rules + selected standards sections + decisions + design-decisions + spec digest pointer |
| `tester-bundle.md` | Tester | 150–200 lines | Invariants + naming/git rules + logging/redaction + GDPR/PII + attack-surface hardening + spec digest pointer + lessons-learned filtered to test design |

Reviewers and the DoD-checker do NOT receive a bundle — they have their own protocols (coverage-aware checklist loading + DoD spot-check).

## Why two bundles, not one

The Developer needs the full implementation surface — Domain Service patterns, controller wiring, `services.yaml` examples, scaffold details. The Tester does not. Loading 200+ lines of implementation rules into every Tester run is duplicate context the Tester will never act on. Splitting cuts the Tester's bundle by 30-40%.

## Cache-friendly ordering

Each bundle is written **most-static first, most-dynamic last**. Content identical across the subagents spawned in a single `/build-plan` session reuses Anthropic's 5-minute prompt cache; content that changes invalidates the cache from that byte forward.

Static-first ordering means the Developer's first call warms the cache for every later call (DoD-checker, Reviewer iter 1, Tester) — they share the invariants + naming + standards prefix.

## Anti-duplication rule

The spec is in every subagent's reading order separately (step 3 of the Developer / Tester / DevOps prompt template). Reproducing 200-300 lines of spec inside the bundle is duplicate context billed once per spawn.

The bundle's spec section is a **pointer + 5-10 line digest**, never a copy:

```markdown
## Spec digest

See `{spec_path}` § Technical Details (and § Definition of Done for the tester bundle).
Key shape (for routing decisions only — read the spec for full requirements):

- {1 line: aggregate(s) touched}
- {1 line: write or read; sync or async; HTTP or message handler}
- {1 line: external dependencies (LLM / payments / signature / file / geo)}
- {1 line: surfaces a UI — yes/no}
- {1 line: anything unusual the subagent should know to scope its reading}
```

If the spec digest exceeds ~15 lines, the orchestrator wrote too much. Trim and re-emit.

## Cheap-extraction protocol

The orchestrator does NOT read every in-scope standard's full body to decide what to include in the bundle. Instead:

1. **Index first.** For each standard listed in the plan's `Standards Scope`, run `grep -nE "^##+ " standards/<name>.md` once to get the section index (line numbers + heading text). ~50-100 tokens per file.
2. **Match feature type to sections.** The plan's `Standards Scope` already names the relevant sections. Match heading text; do NOT re-derive relevance from prose.
3. **Read targeted ranges.** For each matched section, use `Read` with `offset` + `limit` against the line range from step 1. ~150 lines × N matched sections costs far less than reading 8-12 standards × ~300 lines each.
4. **Full-file read permitted ONLY when 4+ sections of the same standard are matched.** At that point offset+limit overhead exceeds the saving.

This is the same shape as the Reviewer's [coverage-aware loading](/ai-standards/concepts/coverage-aware-loading/), applied to the bundle generator's read pattern. Empirical: bundle generation 111k → ~20-50k Sonnet tokens per `/build-plan`.

Smoke check 22 anchors the protocol's load-bearing phrases so a future edit cannot silently regress to full-file reads.
