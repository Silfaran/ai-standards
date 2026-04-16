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
4. Read `{project-name}-docs/specs/INDEX.md` to identify related specs; deep-read **only** specs with overlapping aggregates or services — do not re-read the full spec list
5. Read the relevant codebase in depth to understand the technical context
6. If the feature has a frontend component, read `design-decisions.md` — ensure the Frontend Architecture section is consistent with established patterns. If a contradiction is needed, flag it to the developer before writing the spec
7. Ask the developer technical or business questions if information is missing or ambiguous
8. Refine the spec with technical details — architecture decisions, affected aggregates, services involved
9. If this feature introduces a new architectural decision or changes an existing one, update `decisions.md` accordingly
10. Classify the feature complexity (see **Complexity Classification** below) and include it in the plan
11. Generate the execution plan specifying:
    - The **Complexity** classification
    - Which agents must intervene and in what order
    - Which service each part of the code belongs to
    - Dependencies between steps
    - A **Standards Scope** section (see below) — this controls which files each subagent reads
12. Create the task file with required tests and Definition of Done
13. Update `{project-name}-docs/specs/INDEX.md` if the spec's status or summary changed

## Complexity Classification

The plan file must include a `## Complexity` section. This tells the `build-plan` orchestrator how to execute the plan — specifically, whether to use separate agents or consolidate them.

Evaluate the feature against these criteria:

| Complexity | Criteria | Agent strategy |
|---|---|---|
| `simple` | Single service, no API/DB changes, < 5 files, no new dependencies | 1 agent: Developer implements + writes tests. Reviewer optional (run only if the developer's handoff flags uncertainty). |
| `standard` | Single service with API/DB changes, OR 2 services with straightforward integration | Standard flow: Dev → Reviewer (loop) → Tester |
| `complex` | Multiple services, async messaging, new infrastructure, or > 3 aggregates | Full flow: DevOps → BE Dev ‖ FE Dev → Reviewers → Tester |

Write it in the plan file as:

```markdown
## Complexity: simple
```

When complexity is `simple`, the plan **must consolidate** the Developer and Tester phases into a single phase. The plan should have 1-2 phases total instead of 3-4.

---

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

| Agent | Extra reads (beyond context bundle) |
|---|---|
| Backend Developer | `backend-reference.md` (async messaging) |
| Frontend Developer | `frontend-reference.md` (composable pattern) |
| Tester | `backend-reference.md` (PHPUnit config, test examples) |
| DevOps | `backend-reference.md` (consumer worker), `new-service-checklist.md` |
```

If no extra reads are needed for an agent, write `none` — the agent will still read the context bundle (which contains the distilled standard rules relevant to this feature).

## Output
- The refined technical spec file updated in place: `{project-name}-docs/specs/{Aggregate}/{feature-name}-specs.md`
- A plan file: `{project-name}-docs/specs/{Aggregate}/{feature-name}-plan.md`
- A task file: `{project-name}-docs/specs/{Aggregate}/{feature-name}-task.md`

### Token Usage Report
After completing, list the files you read and display: `Estimated input tokens: ~{lines_read × 8}`

## Context Checkpoint

After completing this command, evaluate whether the conversation context is getting heavy (many specs refined, large codebase exploration, multiple features in one session). If so, suggest to the developer:

> "The spec is refined and ready to build. To keep context fresh and avoid token waste, I recommend opening a **new session** and running:
> `/build-plan` for `{plan-file-path}`"

If context is still light (e.g. single feature refined in a short conversation), it's fine to continue in the same session.

If the developer asked to refine multiple specs in one session, suggest a new session before starting the `/build-plan` for ANY of them — the build-plan subagents benefit most from a clean orchestrator context.

