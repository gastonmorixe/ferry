#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

if ! command -v shellcheck >/dev/null 2>&1; then
    printf 'ERROR: shellcheck is required. Run make bootstrap first.\n' >&2
    exit 1
fi

files=(
    ferry
    scripts/bootstrap-dev.sh
    scripts/lint.sh
    scripts/test.sh
    generators/_shared/helpers.sh
    generators/actix/generate.sh
    generators/actix/metadata.sh
    generators/axum/generate.sh
    generators/axum/metadata.sh
    generators/django/generate.sh
    generators/django/metadata.sh
    generators/express/generate.sh
    generators/express/metadata.sh
    generators/fastapi/generate.sh
    generators/fastapi/metadata.sh
    generators/go-fiber/generate.sh
    generators/go-fiber/metadata.sh
    generators/go-net/generate.sh
    generators/go-net/metadata.sh
    generators/nestjs/generate.sh
    generators/nestjs/metadata.sh
    generators/nextjs/generate.sh
    generators/nextjs/metadata.sh
    generators/rails/generate.sh
    generators/rails/metadata.sh
    generators/react/generate.sh
    generators/react/metadata.sh
    test/test_helper/common.bash
    test/test_helper/generators_common.bash
)

# SC1091: sourced file not found (expected — test helpers source ferry)
# SC2034: variable appears unused (exported for subprocesses)
# SC2015: A && B || C pattern (deliberate set -e guard in TUI selector)
shellcheck -x -e SC1091,SC2034,SC2015 "${files[@]}"
