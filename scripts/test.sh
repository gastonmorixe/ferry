#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

if ! command -v bats >/dev/null 2>&1; then
    printf 'ERROR: bats is required. Run make bootstrap first.\n' >&2
    exit 1
fi

bats test/unit
bats test/integration
bats test/generators
