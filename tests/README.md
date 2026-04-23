# Framework self-tests

Two layers of self-checks keep ai-standards internally coherent:

| Layer | Lives in | Runs | Cost | Entry point |
|---|---|---|---|---|
| Static smoke | `scripts/smoke-tests.sh` | Every push (CI) + local `make smoke` | 0 tokens | Shell script that parses `.md` files without executing anything |
| Dynamic smoke | `tests/` (this folder) | **Local only, manually, before cutting a release or after non-trivial changes to agents/commands/standards** | Real API tokens (user's key) | `make smoke-dynamic` |

## When to run the dynamic smoke

The dynamic smoke exercises the `/build-plan` orchestrator against a minimal fixture project and verifies invariants that static checks cannot catch:

- The orchestrator reads the `## Model` line from each agent definition and passes the correct tier to the `Agent` tool
- The orchestrator generates a `context-bundle.md` with the expected sections before spawning subagents
- The spawn sequence matches the flow declared in `commands/build-plan-command.md` for the plan's `## Complexity`

Run it when:

- You modified `commands/build-plan-command.md` (orchestrator logic)
- You added, renamed, or deleted an agent under `agents/`
- You changed the `## Model` section of any agent
- You restructured `standards/agent-reading-protocol.md`
- Before cutting a release (`chore(master): release X.Y.Z`)

Do NOT run on every commit — it consumes real API tokens from your account.

## How it works

1. `tests/harness/run-smoke.sh` copies `tests/fixtures/<name>/` to a scratch directory under `/tmp`, symlinks the current ai-standards repo into it, and initializes fake git repos for each affected service so the orchestrator's pre-flight branch check passes
2. It installs a `PreToolUse` hook (`tests/harness/hooks/capture-agent.sh`) in the scratch `.claude/settings.json` that intercepts the first `Agent` tool invocation, records `{model, subagent_type, description, prompt_snippet, handoffs_at_spawn}` to `capture.jsonl`, then denies the call to halt the run
3. Runs `claude --print` (headless Claude Code) against the fixture with a self-confirming prompt that bypasses the interactive sign-off
4. After `claude` exits, `tests/harness/assertions.py` parses `capture.jsonl` and compares against `tests/expected/<name>.json`

Output is one-line-per-fixture PASS/FAIL; non-zero exit on any failure.

## Fixtures

| Fixture | Plan complexity | Expected first spawn | What it exercises |
|---|---|---|---|
| `standard` | `standard` | Backend Developer (opus) | Dev → Reviewer → Tester branch. Validates that a single-backend plan picks backend-developer-agent.md on opus. |
| `simple` | `simple` | Backend Dev+Tester (opus) | Single-agent branch with combined implementation + testing. Validates the `simple` flow collapses Reviewer out. |
| `complex` | `complex` | DevOps (opus) | DevOps-first branch when the plan declares new infrastructure (RabbitMQ transport + Redis DB). Validates that parallel Backend ‖ Frontend is gated behind DevOps when infra is new. |

Each fixture is isolated — failures in one do not block the others.

## Prerequisites

```bash
# One-time install (requires sudo for the default npm global prefix):
sudo npm install -g @anthropic-ai/claude-code

# Verify:
claude --version
```

Your Anthropic API key must be configured for the CLI — see Claude Code's setup docs.

## Adding a new fixture

1. Create `tests/fixtures/<name>/` mirroring the structure of `standard/`
2. Write `tests/expected/<name>.json` with the expected first-spawn invariants (see existing files for the schema: `expected_first_spawn.{model, description_regex, prompt_contains, prompt_template_sections}`, `required_handoff_files`, `context_bundle.{path, required_sections}`)
3. Add `<name>` to the `FIXTURES` list and add a matching entry in the `PLAN_REL` map at the top of `tests/harness/run-smoke.sh`
4. Update the Fixtures table above with the expected first spawn

Keep fixtures minimal — the goal is to exercise orchestrator decisions, not to simulate real features.

## Flakiness tolerance

The LLM orchestrator paraphrases prose across runs — the same spec can produce a context bundle headed `## Spec digest — Technical Details` in one run and `## 4. Spec digest — Technical Details` (or occasionally `## Technical summary`) in another. Assertions that check for exact prose are brittle.

Design choice: `prompt_template_sections` and `context_bundle.required_sections` are treated as **regex** (`re.search`), not literal substrings. Write patterns that tolerate paraphrase — e.g. `"Spec|Technical"` to accept either heading — while still catching real regressions (the section disappearing altogether, or the orchestrator skipping the spec-digest step).

If a fixture still flakes after widening patterns, the legitimate fallback is to re-run (`make smoke-dynamic`) — one spurious failure in ~10 runs is the accepted noise floor. A reliably-failing fixture is a real regression.

## What the harness does NOT verify (known limitations)

- **Handoff content.** The capture hook denies the first `Agent` spawn, so no subagent actually runs. The test validates the spawn metadata (model, description, prompt shape) and the context bundle, not the files the subagent would produce. Full content verification would require L2 (real subagents on Haiku) — a 3-5 day follow-up with open design decisions on flakiness tolerance.
- **Enforcement.** `make smoke-dynamic` is manual. A non-fatal reminder is printed by `make smoke` (`scripts/smoke-tests.sh` Check 8) when structural commits accumulate since the last release tag, but CI does not block on a stale dynamic smoke — running it on every push would burn real tokens for marginal value.
- **Review / Tester phase behaviour.** Reviewer and Tester agents are spawned later in the flow; their prompts and tier propagation are not captured because the harness halts at the first spawn.
