#!/usr/bin/env bash
# Read-only WSL diagnostics. No sudo, installs, profile edits or package upgrades.
set -euo pipefail
if [[ ${1:-} == --help ]]; then
  printf '%s\n' 'Usage: bash repair-dev-factory.sh (read-only WSL diagnostics)'
  exit 0
fi
if (($#)); then printf '%s\n' 'Unexpected arguments' >&2; exit 2; fi
kernel_version=''
if [[ ! -r /proc/version ]] || ! IFS= read -r kernel_version < /proc/version || [[ ${kernel_version,,} != *microsoft* ]]; then
  printf '%s\n' 'BLOCKED: this diagnostic requires WSL' >&2
  exit 2
fi
missing=0
for tool in git node npm pnpm python3 java cmake ninja jq rg; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf 'FOUND: %s\n' "$tool"
  else
    printf 'MISSING: %s\n' "$tool"
    missing=1
  fi
done
printf '%s\n' 'NOT_TESTED: builds and Windows Wi-Fi hardware'
exit "$missing"
