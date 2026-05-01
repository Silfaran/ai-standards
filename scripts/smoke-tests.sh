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
# documented prefixes (BE|FE|SE|PE|OB|CA|SC|DM|AC|LO|AZ|IN|GD|LL|PA|FS|GS|AU|FF|AN|PW|DS|AS) + 3 digits. An ID that
# maps to two different rule texts makes reviewer citations ambiguous; an
# unknown prefix is a typo that will spread through agent usage. When the same
# ID appears in multiple checklists, the rule text must match exactly — that
# is the legitimate reuse pattern (one rule, two audiences).
section "Reviewer checklist rule IDs"
format_violations=0
bad_prefix=0
dupes=0

valid_prefix='BE|FE|SE|PE|OB|CA|SC|DM|AC|LO|AZ|IN|GD|LL|PA|FS|GS|AU|FF|AN|PW|DS|AS'
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
# Check 8 — cross-rule references resolve to declared IDs
# -----------------------------------------------------------------------------
# Several standards cite rules from other standards ("(per AZ-001)",
# "mirror PA-006", "see GD-005"). A rename of the cited rule would silently
# break the citation: the standard reads as if the rule still applies, but
# the prose no longer matches the checklist. Catch the gap by extracting
# every cited ID from standards/*.md and asserting it appears as a defined
# bullet in one of the reviewer checklists.
#
# Allowed citation forms (loose by design — false positives are cheap):
#   AZ-001        bare ID anywhere
#   `AZ-001`      backticked
#   (AZ-001)      parenthesised
#   per AZ-001    "per <id>" / "see <id>" / "mirror <id>"
section "Cross-rule references"
declared_ids=$(grep -oE '\*\*('"$valid_prefix"')-[0-9]{3}\*\*' \
    standards/backend-review-checklist.md standards/frontend-review-checklist.md \
  | grep -oE "($valid_prefix)-[0-9]{3}" | sort -u)

# Extract citations from standards/*.md (excluding the checklist files themselves
# and any *-reference.md, which exist as illustration not contract).
cited_ids=$(grep -ohE "($valid_prefix)-[0-9]{3}" standards/*.md \
  | grep -vE '^$' | sort -u || true)

# Diff: cited that are not declared.
unknown_refs=$(comm -23 <(printf "%s\n" "$cited_ids") <(printf "%s\n" "$declared_ids") || true)

if [ -z "$unknown_refs" ]; then
  pass "every cited rule ID resolves to a declared bullet"
else
  fail "rule IDs cited in standards but not declared in any checklist:"
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    printf "    - %s — cited in:\n" "$ref"
    grep -lE "(^|[^A-Z0-9])$ref([^0-9]|$)" standards/*.md \
      | grep -vE '(backend-review-checklist|frontend-review-checklist)\.md' \
      | sed 's/^/        /'
  done <<< "$unknown_refs"
fi

# -----------------------------------------------------------------------------
# Check 9 — critical-path rule IDs resolve to declared bullets
# -----------------------------------------------------------------------------
# standards/critical-paths/*.md curate subsets of the reviewer checklists
# per feature kind. Every rule ID cited there must exist as a declared bullet
# in one of the reviewer checklists; a typo or a removed rule would silently
# misroute reviewer attention. The check reuses the declared_ids set computed
# above (Check 8) and asserts critical-path citations are a subset of it.
section "Critical-path rule IDs"
if [ -d standards/critical-paths ]; then
  cp_cited=$(grep -ohE "($valid_prefix)-[0-9]{3}" standards/critical-paths/*.md 2>/dev/null \
    | grep -vE '^$' | sort -u || true)
  cp_unknown=$(comm -23 <(printf "%s\n" "$cp_cited") <(printf "%s\n" "$declared_ids") || true)
  if [ -z "$cp_unknown" ]; then
    pass "every rule ID cited in critical-paths/ resolves to a declared bullet"
  else
    fail "rule IDs cited in critical-paths/ but not declared in any checklist:"
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      printf "    - %s — cited in:\n" "$ref"
      grep -lE "(^|[^A-Z0-9])$ref([^0-9]|$)" standards/critical-paths/*.md \
        | sed 's/^/        /'
    done <<< "$cp_unknown"
  fi
else
  printf "  (skipped — no standards/critical-paths/ directory)\n"
fi

# -----------------------------------------------------------------------------
# Check 10 — per-phase bundle paths cited consistently
# -----------------------------------------------------------------------------
# v0.40.0 split the single context-bundle into dev-bundle.md (Developer /
# Dev+Tester / DevOps) and tester-bundle.md (Tester). The orchestrator picks
# which bundle each role gets. A typo or a half-finished rename would silently
# misroute one role to the wrong bundle — Tester loaded with implementation
# rules (token waste) or Developer missing implementation rules (incorrect
# code). Catch the gap by asserting both filenames appear in both files that
# define the contract, with enough occurrences to indicate active use.
section "Per-phase bundle path coherence"
bundle_fail=0
for bundle in dev-bundle.md tester-bundle.md; do
  bp_count=$(grep -cF "$bundle" commands/build-plan-command.md)
  ap_count=$(grep -cF "$bundle" standards/agent-reading-protocol.md)
  if [ "$bp_count" -lt 2 ]; then
    fail "$bundle cited fewer than 2× in commands/build-plan-command.md (got $bp_count) — bundle may be half-removed"
    bundle_fail=1
  fi
  if [ "$ap_count" -lt 1 ]; then
    fail "$bundle not cited in standards/agent-reading-protocol.md — Mode A description out of sync"
    bundle_fail=1
  fi
done
[ $bundle_fail -eq 0 ] && pass "dev-bundle.md and tester-bundle.md cited in build-plan-command.md and agent-reading-protocol.md"

# -----------------------------------------------------------------------------
# Check 11 — DoD-checker phase wired into build-plan flows
# -----------------------------------------------------------------------------
# v0.40.0 introduced agents/dod-checker-agent.md (Haiku) as a mechanical gate
# between Dev and Reviewer. The agent file is covered by Check 1 (model tier)
# and Check 2 (path resolves from commands/). What checks 1+2 do NOT catch:
# someone removing the DoD-checker phase from the flow diagrams in
# build-plan-command.md while leaving the agent file in place. The orchestrator
# would silently skip the gate and burn Reviewer tokens on incomplete work
# again. Assert the phase name appears in the prose AND that the per-phase
# files table declares its model as Haiku.
section "DoD-checker phase wiring"
dod_fail=0
flow_mentions=$(grep -cE "DoD-checker|dod-checker" commands/build-plan-command.md)
if [ "$flow_mentions" -lt 5 ]; then
  fail "DoD-checker mentioned only ${flow_mentions}× in commands/build-plan-command.md — flows likely incomplete (expected ≥5: standard flow, complex flow, prompt template, files-per-phase row × 2)"
  dod_fail=1
fi
if ! grep -qE '\| *DoD-checker[^|]*\| *`agents/dod-checker-agent\.md` *\| *`?haiku`?' commands/build-plan-command.md; then
  fail "DoD-checker row in 'Files per phase' table missing or wrong model tier (must be haiku)"
  dod_fail=1
fi
[ $dod_fail -eq 0 ] && pass "DoD-checker phase wired into flows + Haiku tier declared"

# -----------------------------------------------------------------------------
# Check 12 — reviewer fast-mode declared coherently in BE + FE
# -----------------------------------------------------------------------------
# v0.40.0 added a "## Fast re-review mode" opt-in to both reviewer agents that
# trims iteration ≥2 cost when the diff is mechanical. The two reviewer files
# are independently maintained. Drift between them = one side faster, the
# other slower, for no semantic reason. Assert both files declare the section
# header AND the corresponding "## Re-review mode" output marker.
section "Reviewer fast-mode coherence"
fast_fail=0
for f in agents/backend-reviewer-agent.md agents/frontend-reviewer-agent.md; do
  if ! grep -qF "## Fast re-review mode" "$f"; then
    fail "$f: missing '## Fast re-review mode' section"
    fast_fail=1
  fi
  if ! grep -qF "## Re-review mode" "$f"; then
    fail "$f: missing '## Re-review mode' output marker"
    fast_fail=1
  fi
done
[ $fast_fail -eq 0 ] && pass "fast re-review mode declared in both reviewer agents"

# -----------------------------------------------------------------------------
# Check 13 — Dev → Tester quality-gate trust contract
# -----------------------------------------------------------------------------
# v0.40.0 introduced a multi-file contract: Devs produce '## Quality-Gate
# Results' + '## DoD coverage' sections in their handoff; Tester reads them
# and skips re-running gates that already report clean ('## Quality-gate
# re-execution policy'). A silent rename of any of these section names breaks
# the contract — Tester would fall back to running everything from scratch
# (correct fallback, but the optimisation is silently dead). Assert the four
# sections exist where they need to.
section "Quality-gate trust contract"
qg_fail=0
if ! grep -qF "## Quality-gate re-execution policy" agents/tester-agent.md; then
  fail "agents/tester-agent.md: missing '## Quality-gate re-execution policy' section"
  qg_fail=1
fi
for f in agents/backend-developer-agent.md agents/frontend-developer-agent.md; do
  if ! grep -qF "## Quality-Gate Results" "$f"; then
    fail "$f: missing '## Quality-Gate Results' section reference"
    qg_fail=1
  fi
  if ! grep -qF "## DoD coverage" "$f"; then
    fail "$f: missing '## DoD coverage' section reference"
    qg_fail=1
  fi
done
[ $qg_fail -eq 0 ] && pass "Dev/Tester contract intact (Quality-Gate Results, DoD coverage, re-execution policy)"

# -----------------------------------------------------------------------------
# Check 14 — three invocation modes declared in the reading protocol
# -----------------------------------------------------------------------------
# The reading protocol moved from two modes to three when /check-web added
# Mode C. A silent regression to "Two Invocation Modes" or removal of any
# mode header would leave Mode A / B / C wiring without a top-level contract.
# Trivial cost, catches a class of regression that no other check sees.
section "Three invocation modes"
modes_fail=0
protocol="standards/agent-reading-protocol.md"
if ! grep -qF "Three Invocation Modes" "$protocol"; then
  fail "$protocol: 'Three Invocation Modes' header missing"
  modes_fail=1
fi
for mode_header in "### Mode A" "### Mode B" "### Mode C"; do
  if ! grep -qF "$mode_header" "$protocol"; then
    fail "$protocol: '$mode_header' section missing"
    modes_fail=1
  fi
done
[ $modes_fail -eq 0 ] && pass "Mode A + Mode B + Mode C declared with 'Three Invocation Modes' top header"

# -----------------------------------------------------------------------------
# Check 15 — critical paths declare coverage map and trigger structure
# -----------------------------------------------------------------------------
# Coverage-aware checklist loading (added in v0.42.x) requires every critical
# path to declare both ## Coverage map vs full checklist and ## When to load
# this path with PRIMARY/SECONDARY/DO NOT load classification. Without these
# the reviewer falls back to defensive full-checklist loading and the empirical
# 30-50k Sonnet saving evaporates.
section "Critical paths coverage + triggers"
cp_struct_fail=0
for f in standards/critical-paths/*.md; do
  base=$(basename "$f")
  [ "$base" = "README.md" ] && continue
  if ! grep -qF "## Coverage map vs full checklist" "$f"; then
    fail "$f: missing '## Coverage map vs full checklist' section"
    cp_struct_fail=1
  fi
  if ! grep -qF "## When to load this path" "$f"; then
    fail "$f: missing '## When to load this path' section"
    cp_struct_fail=1
  fi
  # Each path's When-to-load must classify with PRIMARY/SECONDARY/DO NOT load.
  # We check for the labels in any case (markdown bold or plain).
  if ! grep -qE 'PRIMARY trigger' "$f"; then
    fail "$f: '## When to load this path' missing 'PRIMARY trigger' classification"
    cp_struct_fail=1
  fi
  if ! grep -qE 'SECONDARY trigger' "$f"; then
    fail "$f: '## When to load this path' missing 'SECONDARY trigger' classification"
    cp_struct_fail=1
  fi
  if ! grep -qE 'DO NOT load' "$f"; then
    fail "$f: '## When to load this path' missing 'DO NOT load' classification"
    cp_struct_fail=1
  fi
done
[ $cp_struct_fail -eq 0 ] && pass "every critical path declares coverage map + PRIMARY/SECONDARY/DO NOT load triggers"

# -----------------------------------------------------------------------------
# Check 16 — reviewer agents enforce gap citation on checklist section loads
# -----------------------------------------------------------------------------
# PR #102 made the citation requirement load-bearing: every checklist section
# the reviewer loads must cite the gap that triggered it ("Loaded §X because
# diff includes Y; not covered by loaded paths Z"). Without this, the reviewer
# slides back to defensive full-checklist loading and the 30-50k Sonnet saving
# evaporates. Assert both reviewer agents retain the two anchor phrases that
# make the rule enforceable.
section "Reviewer gap-citation enforcement"
cite_fail=0
for f in agents/backend-reviewer-agent.md agents/frontend-reviewer-agent.md; do
  if ! grep -qF "rejected as defensive overhead" "$f"; then
    fail "$f: missing 'rejected as defensive overhead' enforcement clause — citation requirement is unenforceable"
    cite_fail=1
  fi
  if ! grep -qF "cite the gap" "$f"; then
    fail "$f: missing 'cite the gap' phrase — citation anchor is gone"
    cite_fail=1
  fi
done
[ $cite_fail -eq 0 ] && pass "both reviewer agents enforce gap citation on checklist section loads"

# -----------------------------------------------------------------------------
# Check 17 — DoD-checker tool-call budget intact
# -----------------------------------------------------------------------------
# PR #100 capped DoD-checker tool calls per row to keep Haiku-tier cost
# bounded (empirical: 36 calls for 26 rows before, ~2 calls/row after).
# The ceiling lives in agents/dod-checker-agent.md as a `## Tool-call budget
# per row (load-bearing)` section. A future cleanup that drops it would
# silently regress the cheapest agent's cost ceiling.
section "DoD-checker tool-call budget"
if grep -qF "Tool-call budget per row" agents/dod-checker-agent.md; then
  pass "agents/dod-checker-agent.md declares its tool-call budget"
else
  fail "agents/dod-checker-agent.md: missing 'Tool-call budget per row' section — Haiku cost ceiling unprotected"
fi

# -----------------------------------------------------------------------------
# Check 18 — build-plan anti-duplication rule intact
# -----------------------------------------------------------------------------
# PR #100 added an anti-duplication rule for both per-phase bundles: the spec
# is in the subagent prompt's reading order separately, so reproducing spec
# content inside the bundle is duplicate context billed once per spawn. The
# rule lives in commands/build-plan-command.md as a `### Anti-duplication
# rule for both bundles` block. A silent removal regresses bundle size by
# 200-300 lines per spawn.
section "build-plan anti-duplication rule"
if grep -qF "Anti-duplication rule for both bundles" commands/build-plan-command.md \
   && grep -qF "Do NOT reproduce spec content" commands/build-plan-command.md; then
  pass "commands/build-plan-command.md retains the anti-duplication rule"
else
  fail "commands/build-plan-command.md: missing 'Anti-duplication rule for both bundles' header or 'Do NOT reproduce spec content' anchor — bundle size ceiling unprotected"
fi

# -----------------------------------------------------------------------------
# Check 19 — dynamic smoke staleness reminder (non-fatal)
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
