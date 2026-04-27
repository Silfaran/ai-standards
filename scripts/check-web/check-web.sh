#!/usr/bin/env bash
# Entry script for /check-web. Runs the Playwright walker against a base URL
# and writes raw findings to the path declared by --out. The walker is a
# deterministic Node script — no LLM tokens are paid by this layer.
#
# Usage:
#   ./check-web.sh --url <base_url> --out <json_path> [--routes <file>] \
#                  [--cookie key=value]... [--max-depth N] [--max-routes N]
#
# Exit codes:
#   0 — walker completed (findings written; the JSON may still report failures)
#   1 — bad usage / missing required flag
#   2 — Playwright not installed (run `npm install` in this directory)
#   3 — walker crashed before producing any output

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WALKER="$SCRIPT_DIR/playwright-walker.mjs"

URL=""
OUT=""
ROUTES=""
MAX_DEPTH=2
MAX_ROUTES=50
COOKIES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --url)        URL="$2"; shift 2 ;;
    --out)        OUT="$2"; shift 2 ;;
    --routes)     ROUTES="$2"; shift 2 ;;
    --max-depth)  MAX_DEPTH="$2"; shift 2 ;;
    --max-routes) MAX_ROUTES="$2"; shift 2 ;;
    --cookie)     COOKIES+=("$2"); shift 2 ;;
    -h|--help)
      awk '/^# / { sub(/^# ?/, ""); print; next } /^#$/ { print ""; next } NR>1 { exit }' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      printf "Unknown flag: %s\n" "$1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$URL" ] || [ -z "$OUT" ]; then
  printf "Missing required flag(s). --url and --out are required.\n" >&2
  exit 1
fi

if [ ! -d "$SCRIPT_DIR/node_modules" ]; then
  printf "Playwright is not installed. Run:\n  cd %s && npm install\n" "$SCRIPT_DIR" >&2
  exit 2
fi

mkdir -p "$(dirname "$OUT")"

ARGS=(--url "$URL" --out "$OUT" --max-depth "$MAX_DEPTH" --max-routes "$MAX_ROUTES")
[ -n "$ROUTES" ] && ARGS+=(--routes "$ROUTES")
for c in "${COOKIES[@]:-}"; do
  [ -n "$c" ] && ARGS+=(--cookie "$c")
done

cd "$SCRIPT_DIR"
if ! node "$WALKER" "${ARGS[@]}"; then
  if [ ! -s "$OUT" ]; then
    printf "Walker crashed before producing output. Check the Playwright error above.\n" >&2
    exit 3
  fi
  printf "Walker exited non-zero but findings were written. Review %s.\n" "$OUT" >&2
fi

printf "Findings written to: %s\n" "$OUT"
