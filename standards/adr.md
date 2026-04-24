# Architecture Decision Records (ADR)

Standard format for recording architectural decisions in every project that consumes this framework. ADRs live in the project's docs repo, not here — this file only defines the format, lifecycle, and the rules every ADR must follow.

## Where ADRs live

Every project has a single `{project-docs}/decisions.md` file containing all ADRs for that project, separated by `---`. The path is defined in `{project-docs}/workspace.md` under the `decisions:` key (resolve `{project-docs}` from `ai-standards/.workspace-config-path`).

One file (not one-file-per-ADR) is the current default. The split can be done later if the single file becomes unwieldy — the migration is mechanical (each `## ADR-NNN` block becomes one file in `{project-docs}/decisions/ADR-NNN-<slug>.md`). Until then, single-file keeps the decision log greppable in one place.

## ID convention

- **Format:** `ADR-<3 digits>`, e.g. `ADR-001`, `ADR-042`.
- **Stability:** IDs are never reassigned. If an ADR is deprecated or superseded, its ID stays occupied — the new one takes the next free integer.
- **Gaps are allowed.** `ADR-006` can come after `ADR-007` chronologically if decisions were reordered — the order matters by ID, not by file position.
- **Citations** from specs / handoffs use `ADR-NNN` verbatim. The Spec Analyzer is responsible for assigning the next free ID when a new decision is recorded.

## Status lifecycle

Every ADR carries exactly one of these status values, declared on the first line under the heading:

| Status | Meaning |
|---|---|
| `proposed` | Written but not yet ratified — under review by the developer. The rationale and consequences may still change. Do NOT cite a `proposed` ADR in a spec — wait for acceptance. |
| `accepted` | Ratified — the project follows this decision. The default status for every ADR in `decisions.md` unless marked otherwise. |
| `deprecated` | The decision no longer applies. The rationale is kept for historical context, but new code must not follow it. Must include a `## Deprecated` trailer explaining why. |
| `superseded by ADR-NNN` | The decision was replaced by a newer ADR. The ID of the replacement goes in the status line. The replacing ADR, in turn, carries a `## Supersedes` trailer referencing the old one. |

**Supersedes chain.** When ADR-007 replaces ADR-003:

- ADR-003 keeps its original prose, adds a `## Deprecated` section, and updates its status line to `superseded by ADR-007`.
- ADR-007 adds a `## Supersedes` section: "Replaces ADR-003. Reason: ..." 

Never delete the old ADR — the history of why a decision was changed is itself valuable.

## Structure

Every ADR follows this skeleton:

```markdown
## ADR-NNN — <one-line summary in verb-first form>

**Status:** <accepted | proposed | deprecated | superseded by ADR-MMM>

**Decision:** <the actual decision, imperative tense — "All services use DBAL", not "We've decided to use DBAL">

**Rationale:** <why this decision over the alternatives considered — this is the part that survives the longest>

**Consequences:** <positive and negative implications. Every "yes" brings "no" — list both>

[Optional: ## Alternatives Considered]
[Optional: ## Amended <date> — <one-line reason + reference>]
[Optional: ## Supersedes — references ADR-MMM]
[Optional: ## Deprecated — required if status contains "deprecated" or "superseded"]

---
```

### Field rules

- **Summary (heading):** verb-first, present tense, less than 80 characters. Examples: *"Database isolation — one database per service"*, *"Async messaging serializer — JSON, not PHP native"*.
- **Decision:** imperative mood. What IS the rule, not what was considered. Keep to 1-3 sentences.
- **Rationale:** the "why" that outlives the decision itself. When someone reads this 2 years later to understand whether the decision still applies, this paragraph is what they will use.
- **Consequences:** both positive and negative. An ADR that lists only upsides is incomplete — every architectural choice closes other doors, and those doors matter.
- **Alternatives Considered:** optional but recommended for non-obvious choices. Not required for "the only reasonable default" decisions.
- **Amended:** when a decision is modified without being fully superseded. Include the date and the spec / PR that drove the amendment.

## When to write a new ADR

Write one when the decision:

- Affects multiple services, or a single service's architecture in a way another agent / future developer needs to respect
- Is non-obvious — a reasonable person could have chosen differently
- Closes a door the project would otherwise have to re-evaluate each time it comes up

Do **not** write one for:

- Implementation details that live naturally inside code (variable names, file organization inside a service, specific library choices that don't affect the API)
- Temporary workarounds — those go in `{project-docs}/lessons-learned/` instead, unless the workaround hardens into a permanent choice
- Decisions that are already covered by a global standard in `ai-standards/` — do not duplicate framework rules into per-project ADRs

## Who writes and updates ADRs

- **Spec Analyzer** is the primary author. When a spec introduces a new architectural decision, the Spec Analyzer records it as a new ADR in the same refine-specs cycle that produces the spec.
- **Developers and Reviewers** can propose an ADR — they write it with status `proposed` and flag it for the developer. Developer ratifies → status flips to `accepted`.
- Framework-level decisions (things that apply to every project consuming `ai-standards/`) do NOT go here — they go into the relevant standards file in `ai-standards/standards/`. Only project-scoped decisions live in `{project-docs}/decisions.md`.

## Template

Copy-paste from [`templates/adr-entry-template.md`](../templates/adr-entry-template.md) when adding a new ADR.
