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
# Check 7 — reviewer checklist rule IDs are well-formed and globally unique
# -----------------------------------------------------------------------------
# Every bullet in the reviewer checklists must carry a stable ID matching the
# documented prefixes (BE|FE|SE|PE|OB|CA|SC|DM|AC|LO|AZ|IN|GD|LL|PA|FS|GS|AU) + 3 digits. An ID that
# maps to two different rule texts makes reviewer citations ambiguous; an
# unknown prefix is a typo that will spread through agent usage. When the same
# ID appears in multiple checklists, the rule text must match exactly — that
# is the legitimate reuse pattern (one rule, two audiences).
section "Reviewer checklist rule IDs"
format_violations=0
bad_prefix=0
dupes=0

valid_prefix='BE|FE|SE|PE|OB|CA|SC|DM|AC|LO|AZ|IN|GD|LL|PA|FS|GS|AU'
id_regex="\*\*(${valid_prefix})-[0-9]{3}\*\*"

for cl in standards/backend-review-checklist.md standards/frontend-review-checklist.md; do
  # Every bullet line (starts with "- [ ] ") must contain a bolded ID.
  bad=$(awk '/^- \[ \]/ && !/\*\*('"$valid_prefix"')-[0-9]{3}\*\*/' "$cl")
  if [ -n "$bad" ]; then
    fail "$cl: bullets without a valid rule ID:"
    printf "%s\n" "$bad" | sed 's/^/    /'
    format_violations=1
  fi

  # Any ID that DOES appear must use a known prefix (regex enforces this, but
  # we double-check in case someone adds a new prefix without updating docs).
  unknown=$(grep -oE '\*\*[A-Z]{2}-[0-9]{3}\*\*' "$cl" | grep -vE "$id_regex" || true)
  if [ -n "$unknown" ]; then
    fail "$cl: unknown prefix used:"
    printf "%s\n" "$unknown" | sort -u | sed 's/^/    /'
    bad_prefix=1
  fi
done

# Within-file duplicates: an ID that appears twice in the same checklist
# makes reviewer citations ambiguous ("violates SE-021 where?"). Across files,
# reuse is allowed — a rule that applies to both backend and frontend rightly
# appears in both checklists, possibly with context-adapted wording.
# Uses POSIX awk — no gawk extensions (BSD awk on macOS lacks match()'s array arg).
for cl in standards/backend-review-checklist.md standards/frontend-review-checklist.md; do
  within=$(awk '
    /^- \[ \]/ {
      if (match($0, /\*\*[A-Z]{2}-[0-9]{3}\*\*/) == 0) next
      id = substr($0, RSTART + 2, RLENGTH - 4)
      if (id in seen) print id
      else seen[id] = 1
    }
  ' "$cl" | sort -u)

  if [ -n "$within" ]; then
    fail "$cl: rule IDs duplicated within the same file:"
    printf "%s\n" "$within" | sed 's/^/    /'
    dupes=1
  fi
done

[ $format_violations -eq 0 ] && [ $bad_prefix -eq 0 ] && [ $dupes -eq 0 ] \
  && pass "all checklist bullets have valid, non-conflicting rule IDs"

# -----------------------------------------------------------------------------
# Check 8 — dynamic smoke staleness reminder (non-fatal)
# -----------------------------------------------------------------------------
# Count commits since the most recent release tag that touched the structural
# files exercised by `make smoke-dynamic` (agents/, build-plan-command.md,
# agent-reading-protocol.md). Non-zero = the orchestrator's runtime behaviour
# may have drifted since the last time anyone ran the dynamic smoke. Print
# a reminder, do NOT fail — full enforcement would require running the
# dynamic smoke on every push (real tokens), a trade-off the user declined.
section "Dynamic smoke staleness"
last_tag=$(git describe --tags --abbrev=0 2>/dev/null || true)
if [ -z "$last_tag" ]; then
  pass "no release tag yet — dynamic smoke cadence starts at v0.1.0"
else
  changed=$(git log --format='%h %s' "$last_tag"..HEAD -- \
      agents/ \
      commands/build-plan-command.md \
      standards/agent-reading-protocol.md 2>/dev/null | wc -l | tr -d ' ')
  if [ "$changed" -eq 0 ]; then
    pass "no structural changes since $last_tag — dynamic smoke still valid"
  else
    printf "  ! %d structural commit(s) since %s — run \`make smoke-dynamic\` before the next release\n" \
      "$changed" "$last_tag"
    printf "    (this is a reminder, not a failure — CI stays green)\n"
    git log --format='      - %h %s' "$last_tag"..HEAD -- \
      agents/ \
      commands/build-plan-command.md \
      standards/agent-reading-protocol.md 2>/dev/null | head -10
  fi
fi

# -----------------------------------------------------------------------------
section "Result"
if [ $FAIL -eq 0 ]; then
  echo "All smoke tests passed."
  exit 0
fi
echo "Smoke tests FAILED — see ✗ lines above."
exit 1
