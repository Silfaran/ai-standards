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
3. Read `{project-name}-docs/decisions.md` to understand existing architectural decisions
4. Read the relevant codebase in depth to understand the technical context
5. Ask the developer technical or business questions if information is missing or ambiguous
6. Refine the spec with technical details — architecture decisions, affected aggregates, services involved
7. If this feature introduces a new architectural decision or changes an existing one, update `decisions.md` accordingly
8. Generate the execution plan specifying:
   - Which agents must intervene and in what order
   - Which service each part of the code belongs to
   - Dependencies between steps
   - A **Standards Scope** section (see below) — this controls which files each subagent reads
9. Create the task file with required tests and Definition of Done

## Standards Scope

The plan file must include a `Standards Scope` section that tells the `build-plan` orchestrator which standards each agent needs. This prevents agents from reading irrelevant standards and reduces token consumption.

Analyze the feature and determine which of these apply:

| Condition | Include |
|---|---|
| Feature uses async messaging (RabbitMQ, domain events cross-service) | `backend-reference.md` (async sections) |
| Feature scaffolds a new backend service | `backend-reference.md` + `new-service-checklist.md` |
| First controller, AppController, or ApiExceptionSubscriber in a service | `backend-reference.md` (scaffold sections) |
| First composable, store, or page pattern in a frontend service | `frontend-reference.md` |
| Feature adds a new frontend that calls existing backends | `new-service-checklist.md` (CORS section) |

Write the section in this format in the plan file:

```markdown
## Standards Scope

| Agent | Extra reads (beyond standard rules files) |
|---|---|
| Backend Developer | `backend-reference.md` (async messaging) |
| Frontend Developer | `frontend-reference.md` (composable pattern) |
| Tester | `backend-reference.md` (PHPUnit config, test examples) |
| DevOps | `backend-reference.md` (consumer worker), `new-service-checklist.md` |
```

If no extra reads are needed for an agent, write `none` — the agent will still read its standard rules files as defined in its agent definition.

## Output
- The refined technical spec file updated in place: `{project-name}-docs/specs/{Aggregate}/{feature-name}-specs.md`
- A plan file: `{project-name}-docs/specs/{Aggregate}/{feature-name}-plan.md`
- A task file: `{project-name}-docs/specs/{Aggregate}/{feature-name}-task.md`

### Token Usage Report
After completing, list the files you read and display: `Estimated input tokens: ~{lines_read × 8}`

