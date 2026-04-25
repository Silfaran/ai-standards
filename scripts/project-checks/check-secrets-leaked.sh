#!/usr/bin/env bash
# Secret leak scanner. Wraps gitleaks (or trufflehog as a fallback) to scan
# the working tree for accidentally committed credentials.
#
# Per attack-surface-hardening.md → "Secrets scanning".
#
# Usage in CI:
#   scripts/checks/check-secrets-leaked.sh                 # working tree scan
#   scripts/checks/check-secrets-leaked.sh --history       # full git history scan (nightly)
#
# Honours scripts/checks/.gitleaks.toml as the project's allowlist file.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

MODE="working-tree"
if [ "${1:-}" = "--history" ]; then
  MODE="history"
fi

if ! command -v gitleaks >/dev/null 2>&1; then
  printf "ERROR: gitleaks not found in PATH. Install: https://github.com/gitleaks/gitleaks\n" >&2
  printf "  macOS: brew install gitleaks\n" >&2
  printf "  Linux: see release page\n" >&2
  exit 2
fi

CONFIG_ARGS=()
if [ -f scripts/checks/.gitleaks.toml ]; then
  CONFIG_ARGS=(--config scripts/checks/.gitleaks.toml)
fi

case "$MODE" in
  working-tree)
    printf "Scanning working tree (no-git mode)\n"
    if gitleaks detect --source . --no-git --redact "${CONFIG_ARGS[@]}"; then
      printf "secrets scan: OK\n"
      exit 0
    fi
    printf "\nFix: rotate the leaked credential per secrets.md (rotation policy in secrets-manifest.md), then remove the file from the working tree. Add legitimate exceptions to scripts/checks/.gitleaks.toml.\n" >&2
    exit 1
    ;;
  history)
    printf "Scanning full git history\n"
    if gitleaks detect --source . --redact "${CONFIG_ARGS[@]}"; then
      printf "secrets history scan: OK\n"
      exit 0
    fi
    printf "\nFix: rotate the leaked credential immediately. Removing the file from history (BFG / git filter-repo) does NOT undo the leak — assume the value is compromised.\n" >&2
    exit 1
    ;;
esac
