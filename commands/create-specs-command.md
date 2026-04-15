# Command: create-specs

## Description
Creates a business-level spec for a new feature or task.
Does not require technical knowledge — the developer describes what needs to be done in business terms.

The Spec Analyzer reads existing specs and code if needed to understand the context,
and warns about any incompatibilities with existing features before creating the spec.

## Invoked by
Developer

## Agent
Spec Analyzer

## Input
A business description of the feature or task to implement. No technical details required.

Example:
> "I want users to be able to invite other users to a board by email"

## Steps
1. Receive the business description from the developer
2. Read `{project-name}-docs/specs/INDEX.md` to understand all existing features at a glance
3. Identify which existing specs might have incompatibilities based on the index (same aggregate, same service, or overlapping UI area)
4. Deep-read **only** the identified specs — do not read specs that clearly have no overlap
5. Read relevant code if needed to better understand the existing implementation
6. Detect and warn the developer about any incompatibilities with existing features
7. Ask clarifying questions if business information is missing or ambiguous
8. Create the spec file once all information is clear
9. Update `{project-name}-docs/specs/INDEX.md` — add a row for the new spec

## Output
- A business-level spec file: `{project-name}-docs/specs/{Aggregate}/{feature-name}-specs.md`
- A warning report if incompatibilities with existing features are detected

### Token Usage Report
After completing, list the files you read and display: `Estimated input tokens: ~{lines_read × 8}`

## Sections to fill in the spec file

Fill **only** these sections — use the template at `ai-standards/templates/feature-specs-template.md`:

| Section | Fill? |
|---|---|
| Status | Yes — always `Pending implementation` |
| Business Description | Yes |
| Affected Aggregate(s) | Yes |
| Affected Service(s) | Yes — service names only, no technical detail |
| User Stories | Yes |
| Business Rules | Yes |
| Out of Scope | Yes |
| Dependencies | Yes — feature-level only (e.g. "Board CRUD must be implemented") |
| Technical Details (and all subsections) | **NO — leave empty with the placeholder comment** |

> **STOP before Technical Details.** That section and everything under it (API endpoints, data model,
> domain architecture, frontend architecture, folder structure, migrations, etc.) is filled exclusively
> by `refine-specs`. Writing technical content in `create-specs` skips a required step and produces
> specs that have not been validated against the actual codebase.

