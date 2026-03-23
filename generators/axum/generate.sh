#!/usr/bin/env bash
# generators/axum/generate.sh — Ferry generator for Rust Axum

set -euo pipefail

GENERATOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_shared/helpers.sh
source "$GENERATOR_DIR/../_shared/helpers.sh"

generate() {
    local out_dir="$1"

    # Create source directory
    mkdir -p "$out_dir/src"

    # Copy and rename templates
    template_copy "$GENERATOR_DIR/templates/Cargo.toml.template"   "$out_dir" "Cargo.toml"
    template_copy "$GENERATOR_DIR/templates/Dockerfile.template"    "$out_dir" "Dockerfile"
    template_copy "$GENERATOR_DIR/templates/src/main.rs.template"  "$out_dir/src" "main.rs"

    # Copy shared files
    shared_gitignore    rust   "$out_dir"
    shared_dockerignore        "$out_dir"
    shared_style_css           "$out_dir/style.css"

    # Substitute {{APP_NAME}}, {{APP_PORT}}, {{FERRY_VERSION}}, {{YEAR}}
    template_sub_all "$out_dir"
}

generate "$OUTPUT_DIR"
