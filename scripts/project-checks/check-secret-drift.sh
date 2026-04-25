#!/usr/bin/env bash
# Drift validator: every env var the application reads must have a row in
# {project-docs}/secrets-manifest.md (per secrets.md SC-002).
#
# Patterns scanned:
#   EnvSecret::require('NAME')
#   $_ENV['NAME']
#   getenv('NAME')
#
# Run from the project root, after init-project has placed the script
# under scripts/checks/.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

# Resolve the inventory path. Honour an override; otherwise read the
# ai-standards pointer.
if [ -n "${INVENTORY_PATH:-}" ]; then
  INVENTORY="$INVENTORY_PATH"
elif [ -f ai-standards/.workspace-config-path ]; then
  DOCS_DIR="$(cat ai-standards/.workspace-config-path)"
  INVENTORY="$DOCS_DIR/secrets-manifest.md"
else
  printf "ERROR: cannot resolve secrets-manifest.md path (no INVENTORY_PATH and no ai-standards/.workspace-config-path)\n" >&2
  exit 2
fi

if [ ! -f "$INVENTORY" ]; then
  printf "ERROR: %s does not exist\n" "$INVENTORY" >&2
  exit 2
fi

# Collect declared secret names from the manifest. The manifest is markdown;
# the convention used by secrets.md is one row per secret with a backtick-
# wrapped name in the first column.
declared=$(grep -oE '`[A-Z][A-Z0-9_]+`' "$INVENTORY" | tr -d '`' | sort -u)

# Collect referenced secret names from the source.
src_dirs=()
[ -d src ]    && src_dirs+=(src)
[ -d app ]    && src_dirs+=(app)
[ -d config ] && src_dirs+=(config)
if [ ${#src_dirs[@]} -eq 0 ]; then
  printf "WARN: no source directories found (src/, app/, config/) — nothing to check\n" >&2
  exit 0
fi

referenced=$(grep -rhoE \
  -e "EnvSecret::require\('[A-Z_][A-Z0-9_]+'\)" \
  -e "\\\$_ENV\['[A-Z_][A-Z0-9_]+'\]" \
  -e "getenv\('[A-Z_][A-Z0-9_]+'\)" \
  "${src_dirs[@]}" 2>/dev/null \
  | grep -oE "'[A-Z_][A-Z0-9_]+'" \
  | tr -d "'" \
  | sort -u || true)

# Names allowlisted as non-secrets (public URLs, port numbers, public app ids).
# Projects extend this in scripts/checks/secret-drift-allowlist.txt (one name per line).
allowlist=""
if [ -f scripts/checks/secret-drift-allowlist.txt ]; then
  allowlist=$(grep -vE '^\s*(#|$)' scripts/checks/secret-drift-allowlist.txt | sort -u)
fi

# Compute the diff: referenced ∖ (declared ∪ allowlist).
combined=$(printf "%s\n%s\n" "$declared" "$allowlist" | sort -u)
missing=$(comm -23 <(printf "%s\n" "$referenced") <(printf "%s\n" "$combined") || true)

if [ -z "$missing" ]; then
  printf "secrets manifest: OK (no drift)\n"
  exit 0
fi

printf "ERROR: secrets read by code but missing from %s:\n" "$INVENTORY" >&2
while IFS= read -r name; do
  [ -n "$name" ] || continue
  printf "  - %s\n" "$name" >&2
  for f in "${src_dirs[@]}"; do
    grep -rn "$name" "$f" 2>/dev/null \
      | grep -E "(EnvSecret::require|\\\$_ENV|getenv)" \
      | head -3 \
      | sed "s/^/      /" >&2 || true
  done
done <<< "$missing"

printf "\nFix: add a row for each missing secret in %s, OR add the name to scripts/checks/secret-drift-allowlist.txt if it is genuinely a public value.\n" "$INVENTORY" >&2
exit 1
