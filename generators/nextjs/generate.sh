#!/usr/bin/env bash
# generators/nextjs/generate.sh — Scaffold a Next.js SSR app
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

# --- Directory tree ---
mkdir -p \
  "$OUTPUT_DIR/src/app/json" \
  "$OUTPUT_DIR/src/app/xml" \
  "$OUTPUT_DIR/src/app/text" \
  "$OUTPUT_DIR/src/app/health" \
  "$OUTPUT_DIR/public"

# Top-level files
template_copy "$TMPL/package.json.template"   "$OUTPUT_DIR"
template_copy "$TMPL/next.config.ts.template" "$OUTPUT_DIR"
template_copy "$TMPL/tsconfig.json.template"  "$OUTPUT_DIR"
template_copy "$TMPL/Dockerfile.template"     "$OUTPUT_DIR"

# App router pages & layout
template_copy "$TMPL/src/app/page.tsx.template"   "$OUTPUT_DIR/src/app"
template_copy "$TMPL/src/app/layout.tsx.template" "$OUTPUT_DIR/src/app"

# API routes
template_copy "$TMPL/src/app/json/route.ts.template"   "$OUTPUT_DIR/src/app/json"
template_copy "$TMPL/src/app/xml/route.ts.template"    "$OUTPUT_DIR/src/app/xml"
template_copy "$TMPL/src/app/text/route.ts.template"   "$OUTPUT_DIR/src/app/text"
template_copy "$TMPL/src/app/health/route.ts.template" "$OUTPUT_DIR/src/app/health"

# Shared assets
shared_gitignore  "node" "$OUTPUT_DIR"
shared_dockerignore      "$OUTPUT_DIR"
shared_style_css         "$OUTPUT_DIR/public/style.css"

# --- Substitute {{VAR}} placeholders in every file ---
template_sub_all "$OUTPUT_DIR"
