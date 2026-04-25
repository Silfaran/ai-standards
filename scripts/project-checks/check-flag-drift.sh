#!/usr/bin/env bash
# Drift validator: every flag key referenced by code must have a row in
# {project-docs}/feature-flags.md (per feature-flags.md FF-001).
#
# Patterns scanned:
#   PHP:  $flags->boolean('KEY', ...)  $flags->variant('KEY', ...)
#         $this->flags->boolean('KEY', ...)
#   TS:   useFlag('KEY')   useFlag("KEY")
#         flags.boolean('KEY')

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

if [ -n "${INVENTORY_PATH:-}" ]; then
  INVENTORY="$INVENTORY_PATH"
elif [ -f ai-standards/.workspace-config-path ]; then
  DOCS_DIR="$(cat ai-standards/.workspace-config-path)"
  INVENTORY="$DOCS_DIR/feature-flags.md"
else
  printf "ERROR: cannot resolve feature-flags.md path (no INVENTORY_PATH and no ai-standards/.workspace-config-path)\n" >&2
  exit 2
fi

if [ ! -f "$INVENTORY" ]; then
  printf "ERROR: %s does not exist\n" "$INVENTORY" >&2
  exit 2
fi

# Declared keys: backtick-wrapped lower_snake identifiers in the inventory.
declared=$(grep -oE '`[a-z][a-z0-9_]+`' "$INVENTORY" | tr -d '`' | sort -u)

src_dirs=()
[ -d src ]      && src_dirs+=(src)
[ -d app ]      && src_dirs+=(app)
[ -d frontend ] && src_dirs+=(frontend)
[ -d resources ] && src_dirs+=(resources)
if [ ${#src_dirs[@]} -eq 0 ]; then
  printf "WARN: no source directories found — nothing to check\n" >&2
  exit 0
fi

# Referenced keys: extract the first single-quoted argument of flag-eval calls.
referenced=$(grep -rhoE \
  -e "flags->boolean\('[a-z][a-z0-9_]+'" \
  -e "flags->variant\('[a-z][a-z0-9_]+'" \
  -e "useFlag\(['\"][a-z][a-z0-9_]+['\"]" \
  "${src_dirs[@]}" 2>/dev/null \
  | grep -oE "['\"][a-z][a-z0-9_]+['\"]" \
  | tr -d "'\"" \
  | sort -u || true)

missing=$(comm -23 <(printf "%s\n" "$referenced") <(printf "%s\n" "$declared") || true)

if [ -z "$missing" ]; then
  printf "feature flags inventory: OK (no drift)\n"
  exit 0
fi

printf "ERROR: flag keys evaluated by code but missing from %s:\n" "$INVENTORY" >&2
while IFS= read -r key; do
  [ -n "$key" ] || continue
  printf "  - %s\n" "$key" >&2
  for f in "${src_dirs[@]}"; do
    grep -rn "$key" "$f" 2>/dev/null \
      | grep -E "(flags->boolean|flags->variant|useFlag)" \
      | head -3 \
      | sed "s/^/      /" >&2 || true
  done
done <<< "$missing"

printf "\nFix: add a row for each missing key in %s (key, kind, owner, created, expected_removal, default, variants, targeting_summary, pii_in_context).\n" "$INVENTORY" >&2
exit 1
