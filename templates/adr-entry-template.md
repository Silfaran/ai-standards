# ADR entry template

Paste the block below into `{project-docs}/decisions.md`, keep the `---` separator between ADRs, fill in the placeholders, and replace `NNN` with the next free integer (look at the highest existing `ADR-NNN` heading in the file and increment).

Delete any optional section that does not apply — do NOT leave empty headings behind.

---

```markdown
## ADR-NNN — <one-line summary, verb-first>

**Status:** accepted

**Decision:** <what the rule IS, imperative tense — 1-3 sentences>

**Rationale:** <why this choice over the alternatives — the paragraph that survives the longest>

**Consequences:**
- <positive implication>
- <negative implication — do not skip this bullet>
- <additional consequences as needed>

## Alternatives Considered

- **<Alternative A>:** <one line on why it was rejected>
- **<Alternative B>:** <one line on why it was rejected>
```

## Variants

### When amending an existing ADR without superseding it

Append a trailer to the original ADR — do NOT open a new one:

```markdown
**Amended:** <YYYY-MM-DD> by `<path/to/spec-or-PR-that-drove-the-amendment>` (was: <one-line description of the previous version>).
```

### When a new ADR supersedes an old one

On the new ADR, add:

```markdown
## Supersedes

Replaces ADR-MMM. Reason: <why the old decision no longer holds>.
```

On the old ADR, update its status line to `superseded by ADR-NNN` and add:

```markdown
## Deprecated

Replaced by ADR-NNN on <YYYY-MM-DD>. <one line on the change that triggered the replacement>.
```

Never delete the superseded ADR — the history of why a decision changed is itself valuable.

See [`standards/adr.md`](../standards/adr.md) for the full rules.
