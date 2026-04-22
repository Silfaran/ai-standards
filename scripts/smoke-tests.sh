#!/usr/bin/env bash
# Static smoke tests for ai-standards.
# Detect silent framework regressions (missing model tier, dangling
# references, renamed skills) that lychee + markdownlint cannot catch.
# Run locally with `make smoke`; executed on every CI run via validate.yml.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FAIL=0
pass() { printf "  ✓ %s\n" "$1"; }
fail() { printf "  ✗ %s\n" "$1"; FAIL=1; }

section() { printf "\n== %s ==\n" "$1"; }

# -----------------------------------------------------------------------------
# Check 1 — every agent declares a valid model tier
# -----------------------------------------------------------------------------
# Every agents/*.md must contain a `## Model` section whose first non-empty
# body line starts with Opus, Sonnet, or Haiku. The orchestrator reads this
# to set the `model` arg on Agent spawns; a missing tier silently downgrades
# the agent to the caller's model instead of failing loudly.
section "Agent model tier"
for f in agents/*.md; do
  tier_line=$(awk '
    /^## Model$/ { found=1; next }
    found && /^## / { exit }
    found && NF { print; exit }
  ' "$f")
  if [ -z "$tier_line" ]; then
    fail "$f: missing '## Model' section or empty body"
    continue
  fi
  if ! printf "%s" "$tier_line" | grep -qE '^(Opus|Sonnet|Haiku)\b'; then
    fail "$f: model tier line does not start with Opus|Sonnet|Haiku: '$tier_line'"
    continue
  fi
  pass "$f"
done

# -----------------------------------------------------------------------------
# Check 2 — agent paths cited in commands resolve to real files
# -----------------------------------------------------------------------------
# Commands reference agent definition files as `agents/<name>-agent.md`. A
# rename without grep replaces the orchestrator with a broken lookup at the
# exact moment the command runs — the failure surfaces only in a live session.
section "Command → agent wiring"
missing=0
while IFS= read -r ref; do
  if [ ! -f "$ref" ]; then
    fail "referenced agent file does not exist: $ref"
    missing=1
  fi
done < <(grep -rhoE 'agents/[a-z-]+\.md' commands/ | sort -u)
[ $missing -eq 0 ] && pass "all agent paths cited in commands/ exist"

# -----------------------------------------------------------------------------
# Check 3 — skill folder name matches SKILL.md frontmatter name
# -----------------------------------------------------------------------------
# Auto-loading looks up skills by the `name:` field. If the folder is renamed
# but the frontmatter is not (or vice-versa), the skill becomes unreachable —
# no error, just a skill that never triggers on its declared paths.
section "Skill name ↔ folder"
for d in .claude/skills/*/; do
  dir_name=$(basename "$d")
  [ -f "$d/SKILL.md" ] || { fail "$d: missing SKILL.md"; continue; }
  fm_name=$(awk '/^---$/{c++; next} c==1 && /^name:/{sub(/^name:[[:space:]]*/, ""); print; exit}' "$d/SKILL.md")
  if [ "$dir_name" != "$fm_name" ]; then
    fail "$d: folder '$dir_name' ≠ frontmatter name '$fm_name'"
  else
    pass "$dir_name"
  fi
done

# -----------------------------------------------------------------------------
# Check 4 — repo-internal paths cited in CLAUDE.md / USAGE.md / README.md exist
# -----------------------------------------------------------------------------
# Lychee validates markdown link syntax; this checks backtick-wrapped paths
# (e.g. `ai-standards/standards/foo.md`) that appear inside prose and never
# get linkified. A moved file is silent until an agent tries to read it.
# Scope limited to backtick-enclosed tokens so GitHub URLs
# (https://github.com/Silfaran/ai-standards/...) do not match.
section "Docs path references"
missing=0
for doc in CLAUDE.md USAGE.md README.md ARCHITECTURE.md; do
  [ -f "$doc" ] || continue
  while IFS= read -r ref; do
    # Strip the leading "ai-standards/" since the repo root IS ai-standards.
    local_path="${ref#ai-standards/}"
    if [ ! -e "$local_path" ]; then
      fail "$doc cites missing path: $ref"
      missing=1
    fi
  done < <(grep -oE '`[^`]+`' "$doc" | grep -oE 'ai-standards/[a-zA-Z0-9_/.-]+\.(md|json|yml|yaml)' | sort -u)
done
[ $missing -eq 0 ] && pass "all ai-standards/* paths in docs resolve"

# -----------------------------------------------------------------------------
# Check 5 — every primary standard is indexed in CLAUDE.md
# -----------------------------------------------------------------------------
# An agent entering via CLAUDE.md must see every top-level standard. A new
# standards/ file that nobody remembers to list becomes a silent orphan
# (real case: quality-gates.md was reachable only via USAGE.md/ARCHITECTURE.md
# until the gap was caught). Excludes files that ride alongside a primary
# one by convention: *-reference.md (examples) and *-review-checklist.md
# (consumed by reviewer agents, cited next to their parent standard).
section "CLAUDE.md index coverage"
missing=0
for f in standards/*.md; do
  base=$(basename "$f")
  case "$base" in
    *-reference.md|*-review-checklist.md) continue ;;
  esac
  if ! grep -qF "$base" CLAUDE.md; then
    fail "standards/$base not referenced in CLAUDE.md (silent orphan)"
    missing=1
  fi
done
[ $missing -eq 0 ] && pass "all primary standards indexed in CLAUDE.md"

# -----------------------------------------------------------------------------
# Check 6 — every primary standard appears in agent-reading-protocol.md
# -----------------------------------------------------------------------------
# The reading protocol is the canonical per-role list of which standards
# each agent consumes. A standard absent from the protocol is read by no
# agent — the file exists, but its rules never reach the pipeline. The
# protocol naturally omits itself (role consumes it implicitly via the
# protocol's own definition).
section "Standards ↔ agent-reading-protocol coverage"
missing=0
protocol="standards/agent-reading-protocol.md"
for f in standards/*.md; do
  base=$(basename "$f")
  [ "$base" = "agent-reading-protocol.md" ] && continue
  if ! grep -qF "$base" "$protocol"; then
    fail "standards/$base missing from $protocol — no agent will read it"
    missing=1
  fi
done
[ $missing -eq 0 ] && pass "all standards covered by agent-reading-protocol.md"

# -----------------------------------------------------------------------------
section "Result"
if [ $FAIL -eq 0 ]; then
  echo "All smoke tests passed."
  exit 0
fi
echo "Smoke tests FAILED — see ✗ lines above."
exit 1
