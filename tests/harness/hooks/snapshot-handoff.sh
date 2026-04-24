#!/usr/bin/env bash
# PostToolUse hook — full-mode only.
# Snapshots any file written under handoffs/ to $SMOKE_HANDOFFS_SNAPSHOT_DIR
# so assertions can inspect the produced handoffs AFTER the orchestrator
# reaches build-plan Step 10 (which deletes the handoffs directory).
#
# Fires after EVERY successful Write. We filter on the file path: only
# paths containing `/handoffs/` (so the feature-folder stays intact) get
# copied. Copy, not move — the orchestrator still needs the file to feed
# the next phase's subagent.

set -euo pipefail

[ -n "${SMOKE_HANDOFFS_SNAPSHOT_DIR:-}" ] || { echo '{}'; exit 0; }

input=$(cat)
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""')

# Only Write matters — Edit edits existing files, NotebookEdit is unrelated.
[ "$tool_name" = "Write" ] || { echo '{}'; exit 0; }

file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""')

# Match any path containing `/handoffs/` — the orchestrator always writes
# under `{workspace_root}/handoffs/{feature-name}/` per build-plan.
case "$file_path" in
  */handoffs/*)
    # Compute relative subpath from handoffs/ onwards so the snapshot
    # preserves the feature-folder structure.
    rel="${file_path##*/handoffs/}"
    dest="$SMOKE_HANDOFFS_SNAPSHOT_DIR/$rel"
    mkdir -p "$(dirname "$dest")"
    cp "$file_path" "$dest" 2>/dev/null || true
    ;;
esac

echo '{}'
