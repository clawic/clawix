#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PATTERN='clawix-secrets-proxy|Secrets Vault|secrets vault|claw vault|claw open vault|/v1/vault|VAULT_|CLAWIX_VAULT'

if rg -n "$PATTERN" \
    Sources/Clawix/CodexInstructionsFile.swift \
    Sources/Clawix/Secrets \
    Sources/Clawix/Resources \
    scripts/dev.sh \
    Package.swift; then
    echo "ERROR: legacy Vault/proxy naming found in public Secrets surfaces." >&2
    exit 1
fi

echo "Secrets naming gate passed."
