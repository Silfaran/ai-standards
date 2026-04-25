#!/usr/bin/env bash
# Container image vulnerability scanner. Wraps Trivy to fail CI on HIGH or
# CRITICAL findings in a built image.
#
# Per attack-surface-hardening.md → "Container image security".
#
# Usage in CI (after `docker build -t app:ci .`):
#   scripts/checks/check-container-image.sh app:ci
#
# Honours scripts/checks/.trivyignore for documented exceptions.

set -euo pipefail

if [ $# -lt 1 ]; then
  printf "Usage: %s <image-tag>\n" "$(basename "$0")" >&2
  exit 2
fi

IMAGE="$1"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

if ! command -v trivy >/dev/null 2>&1; then
  printf "ERROR: trivy not found in PATH. Install: https://aquasecurity.github.io/trivy/\n" >&2
  printf "  macOS: brew install trivy\n" >&2
  printf "  Linux: see install docs\n" >&2
  exit 2
fi

IGNORE_ARGS=()
if [ -f scripts/checks/.trivyignore ]; then
  IGNORE_ARGS=(--ignorefile scripts/checks/.trivyignore)
fi

printf "Scanning %s for HIGH and CRITICAL vulnerabilities\n" "$IMAGE"

if trivy image \
    --severity HIGH,CRITICAL \
    --exit-code 1 \
    --no-progress \
    --scanners vuln,secret,misconfig \
    "${IGNORE_ARGS[@]}" \
    "$IMAGE"; then
  printf "container image scan: OK\n"
  exit 0
fi

printf "\nFix:\n" >&2
printf "  - Bump the affected base image / package to a patched version.\n" >&2
printf "  - If a finding is a documented false positive or an accepted risk, add it to scripts/checks/.trivyignore with a reference to the ADR / issue.\n" >&2
printf "  - CRITICAL findings block the deploy until resolved or explicitly accepted in writing.\n" >&2
exit 1
