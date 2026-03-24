#!/usr/bin/env bash
# generators/react/generate.sh — Scaffold a React (Vite + TypeScript) SPA
#
# Receives from caller:
#   APP_NAME       — validated app name
#   APP_PORT       — port (from metadata default or --port override)
#   OUTPUT_DIR     — target directory (already created, empty)
#   SHARED_DIR     — path to generators/_shared
#   FERRY_VERSION  — ferry version string

set -euo pipefail

GEN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_shared/helpers.sh
source "$SHARED_DIR/helpers.sh"

TMPL="$GEN_DIR/templates"

# --- Source files ---
mkdir -p "$OUTPUT_DIR/src" "$OUTPUT_DIR/public"

# Top-level files
template_copy "$TMPL/index.html.template"        "$OUTPUT_DIR"
template_copy "$TMPL/package.json.template"      "$OUTPUT_DIR"
template_copy "$TMPL/vite.config.ts.template"    "$OUTPUT_DIR"
template_copy "$TMPL/tsconfig.json.template"     "$OUTPUT_DIR"
template_copy "$TMPL/tsconfig.app.json.template" "$OUTPUT_DIR"
template_copy "$TMPL/tsconfig.node.json.template" "$OUTPUT_DIR"
template_copy "$TMPL/Dockerfile.template"        "$OUTPUT_DIR"
template_copy "$TMPL/nginx.conf.template"        "$OUTPUT_DIR"

# src/
template_copy "$TMPL/src/main.tsx.template"  "$OUTPUT_DIR/src"
template_copy "$TMPL/src/App.tsx.template"   "$OUTPUT_DIR/src"
template_copy "$TMPL/src/App.css.template"   "$OUTPUT_DIR/src"

# Shared assets
shared_gitignore  "node" "$OUTPUT_DIR"
shared_dockerignore      "$OUTPUT_DIR"
shared_style_css         "$OUTPUT_DIR/public/style.css"

# --- Substitute {{VAR}} placeholders in every file ---
template_sub_all "$OUTPUT_DIR"
