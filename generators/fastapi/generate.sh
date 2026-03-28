#!/usr/bin/env bash
# generators/fastapi/generate.sh — FastAPI generator for Ferry
set -euo pipefail

# ---------------------------------------------------------------------------
# Source shared helpers
# ---------------------------------------------------------------------------
# shellcheck source=../_shared/helpers.sh
source "$SHARED_DIR/helpers.sh"

# ---------------------------------------------------------------------------
# Required environment
# ---------------------------------------------------------------------------
: "${APP_NAME:?APP_NAME must be set}"
: "${APP_PORT:?APP_PORT must be set}"
: "${OUTPUT_DIR:?OUTPUT_DIR must be set}"
: "${SHARED_DIR:?SHARED_DIR must be set}"
: "${FERRY_VERSION:?FERRY_VERSION must be set}"

GENERATOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$GENERATOR_DIR/templates"

# ---------------------------------------------------------------------------
# Copy templates into output directory
# ---------------------------------------------------------------------------
template_copy "$TEMPLATES_DIR/main.py.template"           "$OUTPUT_DIR"
template_copy "$TEMPLATES_DIR/requirements.txt.template"  "$OUTPUT_DIR"
template_copy "$TEMPLATES_DIR/Dockerfile.template"        "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# Copy style.css into static/ subdirectory
# ---------------------------------------------------------------------------
mkdir -p "$OUTPUT_DIR/static"
shared_style_css "$OUTPUT_DIR/static/style.css"

# ---------------------------------------------------------------------------
# Copy shared dotfiles
# ---------------------------------------------------------------------------
shared_gitignore   python "$OUTPUT_DIR"
shared_dockerignore        "$OUTPUT_DIR"
shared_app_json            "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# Substitute {{APP_NAME}}, {{APP_PORT}}, {{FERRY_VERSION}}, {{YEAR}}
# ---------------------------------------------------------------------------
template_sub_all "$OUTPUT_DIR"
