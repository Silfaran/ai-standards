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
2. Read existing specs in `{project-name}-docs/specs/` to understand the current context
3. Read relevant code if needed to better understand the existing implementation
4. Detect and warn the developer about any incompatibilities with existing features
5. Ask clarifying questions if business information is missing or ambiguous
6. Create the spec file once all information is clear

## Output
- A business-level spec file: `{project-name}-docs/specs/{Aggregate}/{feature-name}-specs.md`
- A warning report if incompatibilities with existing features are detected

