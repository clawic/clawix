#!/usr/bin/env bash
# Mirrors `clawix/macos/scripts/public_hygiene_check.sh`: scans the
# linux/ subtree for accidental leaks of the maintainer-private literals
# (Team ID, real bundle id, SKU, GPG key id, etc.). Non-zero on a hit.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0

# These literals must NEVER appear inside clawix/. The matching list is
# duplicated from macos/scripts/public_hygiene_check.sh; keep in sync.
PROHIBITED_PATTERNS=(
  '.signing.env'
)

for pattern in "${PROHIBITED_PATTERNS[@]}"; do
  if grep -RInE --binary-files=without-match \
       --exclude-dir=node_modules --exclude-dir=target --exclude-dir=dist \
       "$pattern" "$ROOT" >/dev/null 2>&1; then
    echo "[hygiene] forbidden literal '$pattern' present under linux/" >&2
    FAIL=1
  fi
done

exit "$FAIL"
