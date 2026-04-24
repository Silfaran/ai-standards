#!/usr/bin/env bash
# Dynamic smoke test for the /build-plan orchestrator.
#
# Copies tests/fixtures/<name>/ to a scratch directory, initializes fake git
# repos for each affected service so the orchestrator's pre-flight passes,
# runs `claude --print /build-plan ...` with the capture hook installed, then
# asserts on the first-Agent-spawn capture against tests/expected/<name>.yaml.
#
# Usage:
#   ./tests/harness/run-smoke.sh            # runs all fixtures
#   ./tests/harness/run-smoke.sh standard   # runs a single fixture
#
# Environment:
#   SMOKE_KEEP_WORK=1   keep the scratch directory after the run (debug)
#   SMOKE_VERBOSE=1     stream claude's stdout/stderr live

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# Fixtures to run when no argument is given. Add new fixtures here after
# wiring their expected/<name>.yaml file.
# Mode selection.
# - Default (fast mode): the first Agent spawn is intercepted and denied;
#   assertions target the shape of that single spawn + the context bundle.
# - SMOKE_FULL=1 (full mode): the capture hook logs but ALLOWS the spawn,
#   the orchestrator runs the whole pipeline (Dev → Reviewer → Tester),
#   produced handoff files get snapshotted by a PostToolUse hook, and
#   assertions target the structure of those handoffs. Only the `standard`
#   fixture is used in full mode — simple+complex carry too little signal
#   to justify the ~500k-token cost each.
SMOKE_FULL="${SMOKE_FULL:-}"

if [ -n "$SMOKE_FULL" ]; then
  FIXTURES=(standard)
else
  FIXTURES=(standard simple complex)
fi

# Each fixture's plan file path relative to the fixture root. Resolved via
# case statement for bash 3.2 compatibility (macOS default — no associative
# arrays). The orchestrator is invoked with `/build-plan <plan_rel>`; the
# name matters because the orchestrator writes handoffs under
# `handoffs/<feature-name>/`, which the per-fixture expected JSON asserts
# against.
plan_rel_for() {
  case "$1" in
    standard) echo "fake-docs/specs/board-set-title/board-set-title-plan.md" ;;
    simple)   echo "fake-docs/specs/board-title-length-validator/board-title-length-validator-plan.md" ;;
    complex)  echo "fake-docs/specs/board-activity-feed/board-activity-feed-plan.md" ;;
    *)        return 1 ;;
  esac
}

if [ $# -gt 0 ]; then
  FIXTURES=("$@")
fi

# --- Pre-flight: tools -------------------------------------------------------

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing prerequisite: $1 — $2" >&2
    exit 2
  fi
}

require claude  "install with: sudo npm install -g @anthropic-ai/claude-code"
require jq      "install with: brew install jq"
require python3 "install with: brew install python3"
require git     "install with: xcode-select --install"

# --- Per-fixture run ---------------------------------------------------------

FAIL=0

run_fixture() {
  local name="$1"
  local fixture_dir="$ROOT/tests/fixtures/$name"
  local expected_file="$ROOT/tests/expected/$name.json"

  if [ ! -d "$fixture_dir" ]; then
    echo "✗ $name: fixture not found at $fixture_dir" >&2
    return 1
  fi
  if [ ! -f "$expected_file" ]; then
    echo "✗ $name: expected file not found at $expected_file" >&2
    return 1
  fi

  local work
  work="$(mktemp -d -t ai-smoke-"$name"-XXXXXX)"
  if [ -z "${SMOKE_KEEP_WORK:-}" ]; then
    trap 'rm -rf "$work"' RETURN
  fi

  echo ""
  echo "== Running fixture: $name =="
  echo "   scratch: $work"

  # Copy fixture contents (including dotfiles).
  cp -R "$fixture_dir"/. "$work"/

  # Full-mode: swap settings.json for the full-pipeline variant that allows
  # Agent spawns + snapshots handoff writes. The fixture only ships this
  # variant for `standard` — fast mode is always available for every fixture.
  if [ -n "$SMOKE_FULL" ]; then
    if [ ! -f "$work/.claude/settings.full.json" ]; then
      echo "✗ $name: full mode requested but .claude/settings.full.json missing in fixture" >&2
      return 1
    fi
    mv "$work/.claude/settings.full.json" "$work/.claude/settings.json"
  else
    # Fast mode — remove the full-mode settings file if the fixture ships it.
    rm -f "$work/.claude/settings.full.json"
  fi

  # Symlink the current ai-standards repo into the scratch dir. The slash
  # command stub reads ai-standards/commands/build-plan-command.md — the link
  # keeps the orchestrator pointed at the version under test, not a cached
  # copy. Use a relative symlink so `realpath` resolves from inside $work.
  ln -s "$ROOT" "$work/ai-standards"

  # Initialize fake git repos for every affected service. The orchestrator's
  # pre-flight branch check (build-plan Step 3) requires HEAD on master.
  for service_dir in "$work"/task-service "$work"/login-service \
                     "$work"/notification-service "$work"/task-front \
                     "$work"/login-front; do
    [ -d "$service_dir" ] || continue
    (
      cd "$service_dir"
      git init --quiet --initial-branch=master
      git config user.email "smoke@fixture.local"
      git config user.name  "smoke fixture"
      git add -A
      git commit --quiet -m "chore: fixture baseline"
    )
  done

  # Also init the workspace root as a git repo so git-aware orchestrator
  # checks do not fail on the containing directory.
  (
    cd "$work"
    # Avoid .git-in-.git recursion by only init-ing if none present.
    if [ ! -d .git ]; then
      # Exclude ai-standards symlink and fake-docs from the top-level repo
      # so nested git state stays intact.
      printf 'ai-standards\nfake-docs\nhandoffs\n' > .gitignore
      git init --quiet --initial-branch=master
      git config user.email "smoke@fixture.local"
      git config user.name  "smoke fixture"
      git add .gitignore
      git commit --quiet -m "chore: fixture root"
    fi
  )

  local capture_file="$work/capture.jsonl"
  : > "$capture_file"
  export SMOKE_CAPTURE_FILE="$capture_file"

  # Full-mode only: persistent snapshot directory for handoff files. The
  # orchestrator deletes `{workspace_root}/handoffs/<feature>/` at
  # build-plan Step 10; the snapshot hook copies every handoff write to
  # this directory so assertions can still read them after the run.
  local snapshot_dir=""
  if [ -n "$SMOKE_FULL" ]; then
    snapshot_dir="$work/handoffs-snapshot"
    mkdir -p "$snapshot_dir"
    export SMOKE_HANDOFFS_SNAPSHOT_DIR="$snapshot_dir"
  else
    unset SMOKE_HANDOFFS_SNAPSHOT_DIR
  fi

  # Tell the orchestrator exactly what to do and pre-confirm sign-off so it
  # advances through Steps 0-6 without waiting for an interactive prompt.
  local plan_rel
  plan_rel="$(plan_rel_for "$name")" || {
    echo "✗ $name: no plan_rel_for() case — add one in tests/harness/run-smoke.sh" >&2
    return 1
  }
  local feature_name
  feature_name="$(basename "$(dirname "$plan_rel")")"
  local prompt
  if [ -n "$SMOKE_FULL" ]; then
    prompt="$(cat <<EOF
/build-plan $plan_rel

This is an automated FULL dynamic smoke test — run the full pipeline to
completion. Pre-confirmed: the plan is complete, sign-off is granted.
Proceed through pre-flight (all fake services are on master). The fake
services are empty stubs — when a subagent cannot run Docker / PHPUnit /
vue-tsc because the service has no real Symfony or Vue app, it must
honestly report "could not execute because X" in its handoff and mark
the affected DoD items as "pending human verification". Do NOT fabricate
test results. Produce real handoff files in handoffs/$feature_name/ for
every phase. Stop cleanly when the pipeline finishes — no need to commit.
EOF
    )"
  else
    prompt="$(cat <<EOF
/build-plan $plan_rel

This is an automated dynamic smoke test of the orchestrator itself — no real
feature will be implemented. Confirmed: the plan is complete, sign-off is
granted. Proceed through pre-flight (all fake services are on master), write
the context bundle under handoffs/$feature_name/, and attempt the first
Agent spawn. A PreToolUse hook will intercept that spawn and halt the run;
this is expected behaviour.
EOF
    )"
  fi

  # Full mode needs a much higher turn budget — Dev + Reviewer + Tester
  # plus orchestrator overhead easily crosses 100 turns.
  local max_turns=60
  [ -n "$SMOKE_FULL" ] && max_turns=250

  local claude_log="$work/claude.log"
  local claude_exit=0
  (
    cd "$work"
    if [ -n "${SMOKE_VERBOSE:-}" ]; then
      claude --print --max-turns "$max_turns" --output-format text <<<"$prompt" 2>&1 | tee "$claude_log" || claude_exit=$?
    else
      claude --print --max-turns "$max_turns" --output-format text <<<"$prompt" >"$claude_log" 2>&1 || claude_exit=$?
    fi
    exit $claude_exit
  ) || claude_exit=$?

  echo "   claude exit: $claude_exit"
  echo "   captures:    $(wc -l <"$capture_file" | tr -d ' ')"
  if [ -n "$SMOKE_FULL" ]; then
    local handoff_count
    handoff_count=$(find "$snapshot_dir" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    echo "   handoffs:    $handoff_count"
  fi

  local mode_flag="fast"
  [ -n "$SMOKE_FULL" ] && mode_flag="full"

  # Always run assertions — a zero-capture run is itself a failure mode.
  local assertion_args=(
    --fixture "$name"
    --capture "$capture_file"
    --expected "$expected_file"
    --workdir "$work"
    --mode "$mode_flag"
  )
  [ -n "$SMOKE_FULL" ] && assertion_args+=(--snapshot-dir "$snapshot_dir")

  if python3 "$ROOT/tests/harness/assertions.py" "${assertion_args[@]}"; then
    echo "✓ $name"
    return 0
  else
    echo "✗ $name"
    if [ -z "${SMOKE_VERBOSE:-}" ]; then
      echo "   --- last 40 lines of claude.log ---"
      tail -40 "$claude_log" | sed 's/^/   /'
    fi
    return 1
  fi
}

for fixture in "${FIXTURES[@]}"; do
  run_fixture "$fixture" || FAIL=1
done

echo ""
if [ $FAIL -eq 0 ]; then
  echo "All dynamic smoke fixtures passed."
  exit 0
fi
echo "Dynamic smoke FAILED — see ✗ lines above."
exit 1
