#!/usr/bin/env bash
# generators/express/generate.sh — Ferry generator for TypeScript Express
#
# Expected environment variables (set by caller):
#   APP_NAME       — application name (used in package.json, HTML, etc.)
#   APP_PORT       — port the app listens on
#   OUTPUT_DIR     — absolute path to write the generated project into
#   SHARED_DIR     — absolute path to generators/_shared/
#   FERRY_VERSION  — current Ferry version string
#
set -euo pipefail

GENERATOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Validate required env vars ───────────────────────────────────────────────
: "${APP_NAME:?APP_NAME is required}"
: "${APP_PORT:?APP_PORT is required}"
: "${OUTPUT_DIR:?OUTPUT_DIR is required}"
: "${SHARED_DIR:?SHARED_DIR is required}"
: "${FERRY_VERSION:?FERRY_VERSION is required}"

# ── Load shared helpers ──────────────────────────────────────────────────────
# shellcheck source=../_shared/helpers.sh
source "$SHARED_DIR/helpers.sh"

TEMPLATES_DIR="$GENERATOR_DIR/templates"

# ── Copy templates into output dir ───────────────────────────────────────────
template_copy "$TEMPLATES_DIR/app.ts.template"           "$OUTPUT_DIR"
template_copy "$TEMPLATES_DIR/package.json.template"     "$OUTPUT_DIR"
template_copy "$TEMPLATES_DIR/tsconfig.json.template"    "$OUTPUT_DIR"
template_copy "$TEMPLATES_DIR/Dockerfile.template"       "$OUTPUT_DIR"

# ── Copy shared assets ───────────────────────────────────────────────────────
shared_gitignore   "node"   "$OUTPUT_DIR"
shared_dockerignore         "$OUTPUT_DIR"
shared_style_css            "$OUTPUT_DIR/style.css"
shared_app_json             "$OUTPUT_DIR"

# ── Substitute {{placeholders}} in every output file ────────────────────────
template_sub_all "$OUTPUT_DIR"
