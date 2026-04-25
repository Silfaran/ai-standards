# Project drift validators

Scripts that consuming projects run in their own CI to detect drift between
their codebase and the inventory documents declared by `ai-standards`
standards (`secrets.md`, `gdpr-pii.md`, `feature-flags.md`, `audit-log.md`).

## Why

Several standards depend on a `{project-docs}/<inventory>.md` file staying in
sync with the application code:

| Inventory | Source standard | What goes wrong without validation |
|---|---|---|
| `secrets-manifest.md` | `secrets.md` (SC-002) | A new `EnvSecret::require('FOO')` ships without `FOO` in the manifest. Reviewer relies on memory; first leak / rotation event reveals the gap |
| `pii-inventory.md` | `gdpr-pii.md` (GD-001, GD-011) | A new SDK (Stripe, OpenAI, …) is instantiated without declaring the sub-processor. RGPD audit cannot reconstruct the data flow |
| `feature-flags.md` | `feature-flags.md` (FF-001) | A `flags->boolean('foo_v2')` call exists with no registry entry. Flag becomes immortal config debt |
| `audit-actions.md` | `audit-log.md` (AU-009) | An audit entry is written with a `metadata` shape nobody documented. Read-API consumers cannot deserialise reliably |

Reviewer agents catch most of these; these scripts catch the rest. The
combination is what makes drift expensive instead of inevitable.

## Installation in a consuming project

The `init-project` command (or a manual one-time copy) places these scripts
under the project's `scripts/checks/` directory. The project's `Makefile`
exposes them:

```text
.PHONY: check-drift
check-drift:
    @scripts/checks/check-secret-drift.sh
    @scripts/checks/check-pii-inventory-drift.sh
    @scripts/checks/check-flag-drift.sh
    @scripts/checks/check-audit-action-drift.sh
```

(Real Makefiles require literal tab indentation; replace the leading 4 spaces in your project's Makefile with a tab character before commit.)

CI runs `make check-drift` as part of the validate workflow. A non-zero exit
fails the build with a list of the missing inventory entries.

## What each script does

### `check-secret-drift.sh`

- Greps `src/` for `EnvSecret::require('NAME')` and `$_ENV['NAME']` patterns.
- For each `NAME`, asserts a row exists in `{project-docs}/secrets-manifest.md`.
- Exit non-zero if any name is missing; prints the missing names and the
  files that read them.

### `check-pii-inventory-drift.sh`

- Greps `src/` for known sub-processor SDK imports (Stripe, OpenAI/Anthropic,
  SendGrid/Twilio, Signaturit/DocuSign/Yousign, Mapbox, …). The provider list
  is `KNOWN_PROVIDERS` near the top of the script — projects extend it as
  they introduce new providers.
- For each provider found, asserts a row exists in
  `{project-docs}/pii-inventory.md` with `processors:` containing the
  provider name.
- Exit non-zero if any provider is undeclared; prints the missing providers
  and the files that import them.

### `check-flag-drift.sh`

- Greps `src/` for `flags->boolean('KEY'` and `flags->variant('KEY'` patterns
  (PHP) plus `useFlag('KEY')` (TS).
- For each `KEY`, asserts a row exists in `{project-docs}/feature-flags.md`.
- Exit non-zero with the missing keys and where they are evaluated.

### `check-audit-action-drift.sh`

- Greps `src/` for `AuditEntry::from(` calls (or the project's equivalent
  audit-write helper) and extracts the `action:` argument.
- For each action, asserts a row exists in `{project-docs}/audit-actions.md`
  documenting its `metadata` shape.
- Exit non-zero with the missing actions.

## Customising for a project

Each script reads its inventory path from `ai-standards/.workspace-config-path`
plus the conventional filename. If a project keeps its inventories elsewhere,
override `INVENTORY_PATH` at the top of the script.

The provider list in `check-pii-inventory-drift.sh` is curated per project;
add new providers as they are introduced.
