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
4. After `claude` exits, `tests/harness/assertions.py` parses `capture.jsonl` and compares against `tests/expected/<name>.yaml`

Output is one-line-per-fixture PASS/FAIL; non-zero exit on any failure.

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
2. Write `tests/expected/<name>.json` with the expected first-spawn invariants
3. Add `<name>` to the `FIXTURES` list at the top of `tests/harness/run-smoke.sh`

Keep fixtures minimal — the goal is to exercise orchestrator decisions, not to simulate real features.
