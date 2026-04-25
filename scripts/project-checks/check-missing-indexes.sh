#!/usr/bin/env bash
# Heuristic: extract every column referenced in a WHERE / ORDER BY / JOIN
# clause from the project's repositories, then verify that column appears
# in some CREATE INDEX / CREATE UNIQUE INDEX statement under migrations/.
#
# Per performance.md PE-001 (every column appearing in WHERE / ORDER BY /
# UUID reference must be indexed).
#
# This is an ASSIST, not a blocker. Multi-column queries, compound indexes,
# composite primary keys, and dynamic SQL produce false positives — the
# script's exit code is 0 by default; pass --strict to fail CI on any
# unindexed column. The intent is "give the reviewer a starting list".
#
# Usage:
#   scripts/checks/check-missing-indexes.sh           # report only
#   scripts/checks/check-missing-indexes.sh --strict  # exit non-zero on findings

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

STRICT=0
[ "${1:-}" = "--strict" ] && STRICT=1

src_dirs=()
[ -d src ] && src_dirs+=(src)
[ -d app ] && src_dirs+=(app)
if [ ${#src_dirs[@]} -eq 0 ]; then
  printf "WARN: no source directories found (src/, app/) — nothing to check\n" >&2
  exit 0
fi

if [ ! -d migrations ] && [ ! -d db/migrations ]; then
  printf "WARN: no migrations/ directory found — nothing to check\n" >&2
  exit 0
fi
mig_dirs=()
[ -d migrations ] && mig_dirs+=(migrations)
[ -d db/migrations ] && mig_dirs+=(db/migrations)

# 1. Extract column names cited after WHERE / AND / OR in repository queries.
#    Patterns matched (PHP single-quoted SQL):
#      WHERE foo = ?
#      AND   foo = :bar
#      ORDER BY foo
#    Captures only `[a-z_][a-z0-9_]*` tokens; aliases like `t.foo` produce `foo`.
referenced=$(grep -rhoE \
  -e "WHERE\s+[a-zA-Z_.]+\s*[=<>!]" \
  -e "AND\s+[a-zA-Z_.]+\s*[=<>!]" \
  -e "OR\s+[a-zA-Z_.]+\s*[=<>!]" \
  -e "ORDER\s+BY\s+[a-zA-Z_.]+" \
  "${src_dirs[@]}" 2>/dev/null \
  | sed -E 's/^.*(WHERE|AND|OR|ORDER\s+BY)\s+([a-zA-Z_]+\.)?([a-zA-Z_][a-zA-Z0-9_]*).*$/\3/I' \
  | grep -vE '^(SELECT|FROM|WHERE|AND|OR|NOT|NULL|TRUE|FALSE|ORDER|BY|LIMIT|OFFSET|GROUP|HAVING|JOIN|ON|AS|IN|LIKE|BETWEEN|EXISTS|CASE|WHEN|THEN|ELSE|END|DESC|ASC)$' \
  | sort -u || true)

if [ -z "$referenced" ]; then
  printf "missing-indexes: nothing to check (no WHERE/ORDER BY found in src/)\n"
  exit 0
fi

# 2. Extract every column that appears in a CREATE INDEX statement.
#    Patterns matched:
#      CREATE INDEX idx_x ON table (col1, col2)
#      CREATE UNIQUE INDEX idx_x ON table (col)
#      ->addIndex(['col1', 'col2'])              (Phinx fluent)
indexed=$( {
  grep -rhoE -e "CREATE (UNIQUE )?INDEX[^(]*\([^)]+\)" "${mig_dirs[@]}" 2>/dev/null \
    | grep -oE "\([^)]+\)" \
    | tr -d '()' \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | grep -oE '[a-zA-Z_][a-zA-Z0-9_]*' || true
  grep -rhoE "addIndex\(\[[^]]+\]" "${mig_dirs[@]}" 2>/dev/null \
    | grep -oE "'[a-zA-Z_][a-zA-Z0-9_]*'" \
    | tr -d "'" || true
  # PRIMARY KEY columns are auto-indexed.
  grep -rhoE "PRIMARY KEY[^(]*\([^)]+\)" "${mig_dirs[@]}" 2>/dev/null \
    | grep -oE "\([^)]+\)" \
    | tr -d '()' \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | grep -oE '[a-zA-Z_][a-zA-Z0-9_]*' || true
  # `id` is the convention PK in this stack — always covered.
  printf "id\n"
} | sort -u || true)

# 3. Diff: referenced ∖ indexed.
missing=$(comm -23 <(printf "%s\n" "$referenced") <(printf "%s\n" "$indexed") || true)

if [ -z "$missing" ]; then
  printf "missing-indexes: OK (every WHERE/ORDER BY column appears in an index)\n"
  exit 0
fi

printf "missing-indexes: candidate columns referenced in queries but not found in any CREATE INDEX statement:\n" >&2
while IFS= read -r col; do
  [ -n "$col" ] || continue
  printf "  - %s — referenced in:\n" "$col" >&2
  for f in "${src_dirs[@]}"; do
    grep -rnE "WHERE.*[^a-z_]${col}[^a-z0-9_]|AND.*[^a-z_]${col}[^a-z0-9_]|OR.*[^a-z_]${col}[^a-z0-9_]|ORDER BY.*[^a-z_]${col}[^a-z0-9_]" "$f" 2>/dev/null \
      | head -2 \
      | sed 's/^/      /' >&2 || true
  done
done <<< "$missing"

printf "\nReview each candidate. False positives:\n" >&2
printf "  - The column is part of a composite index whose first column is NOT this one.\n" >&2
printf "  - The query is in a path that does not need an index (a one-row config table, a debug-only path).\n" >&2
printf "  - The column is the second member of a compound PRIMARY KEY.\n" >&2
printf "Add a CREATE INDEX (CONCURRENTLY on populated tables) for true positives — see performance.md PE-001.\n" >&2

if [ $STRICT -eq 1 ]; then
  exit 1
fi
exit 0
