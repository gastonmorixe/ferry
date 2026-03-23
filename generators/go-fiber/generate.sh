#!/usr/bin/env bash
# generators/go-fiber/generate.sh — Generator for Go (Fiber) apps

set -euo pipefail

GENERATOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_shared/helpers.sh
source "$GENERATOR_DIR/../_shared/helpers.sh"

generate() {
    local out_dir="$1"

    # Copy and rename all templates
    template_copy "$GENERATOR_DIR/templates/main.go.template"    "$out_dir" "main.go"
    template_copy "$GENERATOR_DIR/templates/go.mod.template"     "$out_dir" "go.mod"
    template_copy "$GENERATOR_DIR/templates/Dockerfile.template" "$out_dir" "Dockerfile"

    # Copy shared files
    shared_gitignore    go   "$out_dir"
    shared_dockerignore      "$out_dir"
    shared_style_css         "$out_dir/style.css"

    # Substitute {{APP_NAME}}, {{APP_PORT}}, {{FERRY_VERSION}}, {{YEAR}}
    template_sub_all "$out_dir"
}

generate "$OUTPUT_DIR"
