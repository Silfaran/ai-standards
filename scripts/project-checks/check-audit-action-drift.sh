#!/usr/bin/env bash
# Drift validator: every audit action emitted by code must have its
# `metadata` shape documented in {project-docs}/audit-actions.md
# (per audit-log.md AU-009).
#
# Patterns scanned:
#   action: 'foo.bar'        (named arg in AuditEntry::from(...))
#   ->action('foo.bar', ...)  (alternative builder pattern)
#
# Action identifiers follow the convention `aggregate.verb` from audit-log.md.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

if [ -n "${INVENTORY_PATH:-}" ]; then
  INVENTORY="$INVENTORY_PATH"
elif [ -f ai-standards/.workspace-config-path ]; then
  DOCS_DIR="$(cat ai-standards/.workspace-config-path)"
  INVENTORY="$DOCS_DIR/audit-actions.md"
else
  printf "ERROR: cannot resolve audit-actions.md path (no INVENTORY_PATH and no ai-standards/.workspace-config-path)\n" >&2
  exit 2
fi

if [ ! -f "$INVENTORY" ]; then
  printf "ERROR: %s does not exist\n" "$INVENTORY" >&2
  exit 2
fi

# Declared actions: backtick-wrapped `aggregate.verb` strings in the inventory.
declared=$(grep -oE '`[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)?`' "$INVENTORY" | tr -d '`' | sort -u)

src_dirs=()
[ -d src ] && src_dirs+=(src)
[ -d app ] && src_dirs+=(app)
if [ ${#src_dirs[@]} -eq 0 ]; then
  printf "WARN: no source directories found (src/, app/) — nothing to check\n" >&2
  exit 0
fi

# Referenced actions: extract single-quoted aggregate.verb strings near
# audit-write helpers. The grep is loose by design — the cost of including
# a non-audit string by accident is having to allowlist it; the cost of
# missing one is undocumented metadata.
referenced=$(grep -rhoE \
  -e "action:\s*'[a-z][a-z0-9_]*\.[a-z][a-z0-9_.]+'" \
  -e "->action\('[a-z][a-z0-9_]*\.[a-z][a-z0-9_.]+'" \
  "${src_dirs[@]}" 2>/dev/null \
  | grep -oE "'[a-z][a-z0-9_]*\.[a-z][a-z0-9_.]+'" \
  | tr -d "'" \
  | sort -u || true)

# Allowlist for actions that are intentionally undocumented (exceptional cases
# only — if you find yourself adding to this often, the inventory is the wrong
# place for the doc).
allowlist=""
if [ -f scripts/checks/audit-action-drift-allowlist.txt ]; then
  allowlist=$(grep -vE '^\s*(#|$)' scripts/checks/audit-action-drift-allowlist.txt | sort -u)
fi

combined=$(printf "%s\n%s\n" "$declared" "$allowlist" | sort -u)
missing=$(comm -23 <(printf "%s\n" "$referenced") <(printf "%s\n" "$combined") || true)

if [ -z "$missing" ]; then
  printf "audit actions inventory: OK (no drift)\n"
  exit 0
fi

printf "ERROR: audit actions emitted by code but missing from %s:\n" "$INVENTORY" >&2
while IFS= read -r action; do
  [ -n "$action" ] || continue
  printf "  - %s\n" "$action" >&2
  for f in "${src_dirs[@]}"; do
    grep -rn "$action" "$f" 2>/dev/null \
      | head -3 \
      | sed "s/^/      /" >&2 || true
  done
done <<< "$missing"

printf "\nFix: document each missing action in %s with its metadata shape (per audit-log.md AU-009).\n" "$INVENTORY" >&2
exit 1
