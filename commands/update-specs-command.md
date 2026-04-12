# Command: update-specs

## Description
Compares the current specs with the actual implementation after a task is completed.
Updates the specs to accurately reflect what was built, keeping documentation coherent with the codebase.

If significant differences are found between the spec and the implementation, it warns the developer
that something may not have been implemented correctly before updating.

## Invoked by
Developer

## Agent
Spec Analyzer

## Input
- The spec file: `{project-name}-docs/specs/{Aggregate}/{feature-name}-specs.md`
- The implemented code across the affected services

## Steps
1. Read the existing spec file
2. Read the implemented code across all affected services
3. Compare the spec with the actual implementation
4. If significant differences are found:
   - Warn the developer with a detailed report of what differs and why it may indicate an issue
   - Wait for the developer to confirm whether to update the spec or fix the implementation
5. If differences are minor or the developer confirms the update:
   - Update the spec file to match the actual implementation
   - Document the changes made and the reasoning behind them

## Output
- Updated spec file reflecting the actual implementation
- A diff report highlighting what changed between the original spec and the final implementation
- Warnings if significant deviations from the original spec were detected

