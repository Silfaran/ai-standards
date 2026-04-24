#!/usr/bin/env bash
# PreToolUse hook — full-mode variant of capture-agent.sh.
# Logs the Agent invocation to $SMOKE_CAPTURE_FILE (same format as the
# fast-mode hook) but ALLOWS the call to proceed instead of denying it,
# so the orchestrator runs the full pipeline (Dev → Reviewer → Tester).
#
# Default smoke-dynamic uses capture-agent.sh (deny). This variant is
# installed only when run-smoke.sh is invoked with SMOKE_FULL=1.

set -euo pipefail

capture_file="${SMOKE_CAPTURE_FILE:-/tmp/smoke-capture.jsonl}"
input=$(cat)

model=$(printf '%s' "$input" | jq -r '.tool_input.model // ""')
subagent_type=$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // ""')
description=$(printf '%s' "$input" | jq -r '.tool_input.description // ""')
prompt_snippet=$(printf '%s' "$input" | jq -r '.tool_input.prompt // ""' | head -c 4000)

handoffs_snapshot='[]'
if [ -d handoffs ]; then
  handoffs_snapshot=$(find handoffs -type f 2>/dev/null | sort | jq -R . | jq -s . || printf '[]')
fi

jq -cn \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg model "$model" \
  --arg subagent_type "$subagent_type" \
  --arg description "$description" \
  --arg prompt_snippet "$prompt_snippet" \
  --argjson handoffs_at_spawn "$handoffs_snapshot" \
  '{ts: $ts, model: $model, subagent_type: $subagent_type, description: $description, prompt_snippet: $prompt_snippet, handoffs_at_spawn: $handoffs_at_spawn}' \
  >> "$capture_file"

# Allow the spawn — empty JSON body means "no opinion, proceed".
echo '{}'
