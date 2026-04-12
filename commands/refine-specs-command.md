# Command: refine-specs

## Description
Refines an existing business spec into a detailed technical spec ready for implementation.
Reads the codebase in depth to understand the technical context and asks the developer
technical and business questions if needed to fill any gaps.

Once the spec is complete, generates an execution plan specifying which agents
must intervene and in what order, and which service each part of the code belongs to.

## Invoked by
Developer

## Agent
Spec Analyzer

## Input
The business spec file created by the `create-specs` command:
`{project-name}-docs/specs/{Aggregate}/{feature-name}-specs.md`

## Steps
1. Read the existing business spec file
2. Read `{project-name}-docs/services.md` to understand the available services
3. Read the relevant codebase in depth to understand the technical context
4. Ask the developer technical or business questions if information is missing or ambiguous
5. Refine the spec with technical details — architecture decisions, affected aggregates, services involved
6. Generate the execution plan specifying:
   - Which agents must intervene and in what order
   - Which service each part of the code belongs to
   - Dependencies between steps
7. Create the task file with required tests and Definition of Done

## Output
- The refined technical spec file updated in place: `{project-name}-docs/specs/{Aggregate}/{feature-name}-specs.md`
- A plan file: `{project-name}-docs/specs/{Aggregate}/{feature-name}-plan.md`
- A task file: `{project-name}-docs/specs/{Aggregate}/{feature-name}-task.md`

## Integrations
<!-- If a project management tool is configured (Jira, Trello, Linear...), the refined spec and plan details
can be synced to the task. Comments will be added documenting any business changes and the reasoning behind them -->
