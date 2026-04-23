#!/usr/bin/env bash
# PreToolUse hook — intercepts the first Agent tool invocation from /build-plan,
# records {model, subagent_type, description, prompt_snippet, handoffs_at_spawn}
# to $SMOKE_CAPTURE_FILE, then denies the call to halt the run before the real
# subagent is spawned. Reached only via the dynamic smoke harness; the user's
# regular workspace does not install this hook.
#
# stdin: JSON with tool_name, tool_input (per Claude Code PreToolUse contract).
# stdout: JSON with hookSpecificOutput.permissionDecision = deny.
# Side effect: appends one line to $SMOKE_CAPTURE_FILE (JSONL).

set -euo pipefail

capture_file="${SMOKE_CAPTURE_FILE:-/tmp/smoke-capture.jsonl}"
input=$(cat)

# Extract tool_input fields — use // "" so jq never errors on missing keys.
model=$(printf '%s' "$input" | jq -r '.tool_input.model // ""')
subagent_type=$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // ""')
description=$(printf '%s' "$input" | jq -r '.tool_input.description // ""')
# Truncate the prompt to 2000 chars — enough to assert on agent paths without
# bloating the capture file.
prompt_snippet=$(printf '%s' "$input" | jq -r '.tool_input.prompt // ""' | head -c 2000)

# Snapshot the handoffs directory at the moment the orchestrator is about to
# spawn the first agent. Assertions verify that the context bundle was written
# BEFORE the spawn (build-plan Step 0.5 precedes Step 6).
handoffs_snapshot='[]'
if [ -d handoffs ]; then
  handoffs_snapshot=$(find handoffs -type f 2>/dev/null | sort | jq -R . | jq -s . || printf '[]')
fi

# Append capture line.
jq -cn \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg model "$model" \
  --arg subagent_type "$subagent_type" \
  --arg description "$description" \
  --arg prompt_snippet "$prompt_snippet" \
  --argjson handoffs_at_spawn "$handoffs_snapshot" \
  '{ts: $ts, model: $model, subagent_type: $subagent_type, description: $description, prompt_snippet: $prompt_snippet, handoffs_at_spawn: $handoffs_at_spawn}' \
  >> "$capture_file"

# Deny the spawn — the model-enforcement hook in the same matcher runs first;
# if it let the call through, the model arg is present and we have what we
# need. Halting here keeps the run bounded and avoids real subagent tokens.
jq -cn '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "SMOKE_CAPTURE_COMPLETE — first Agent spawn recorded by tests/harness/hooks/capture-agent.sh. Halting the orchestrator is expected behaviour for the dynamic smoke test."
  }
}'
