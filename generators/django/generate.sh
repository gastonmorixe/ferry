#!/usr/bin/env bash
# generators/django/generate.sh — Ferry generator for Django
#
# Receives from caller:
#   APP_NAME      validated app name
#   APP_PORT      port (default: 8000)
#   OUTPUT_DIR    target directory (already created, empty)
#   SHARED_DIR    path to generators/_shared
#   FERRY_VERSION ferry version string
set -euo pipefail

GENERATOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load shared helpers
# shellcheck source=../_shared/helpers.sh
source "$SHARED_DIR/helpers.sh"

TMPL="$GENERATOR_DIR/templates"

# ---------------------------------------------------------------------------
# 1. Top-level files
# ---------------------------------------------------------------------------
template_copy "$TMPL/manage.py.template"          "$OUTPUT_DIR"
template_copy "$TMPL/requirements.txt.template"   "$OUTPUT_DIR"
template_copy "$TMPL/Dockerfile.template"         "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# 2. config/ package (fixed name avoids directory renaming)
# ---------------------------------------------------------------------------
mkdir -p "$OUTPUT_DIR/config"
template_copy "$TMPL/project/__init__.py.template" "$OUTPUT_DIR/config" "__init__.py"
template_copy "$TMPL/project/settings.py.template" "$OUTPUT_DIR/config"
template_copy "$TMPL/project/urls.py.template"     "$OUTPUT_DIR/config"
template_copy "$TMPL/project/views.py.template"    "$OUTPUT_DIR/config"
template_copy "$TMPL/project/wsgi.py.template"     "$OUTPUT_DIR/config"

# ---------------------------------------------------------------------------
# 3. static/ directory (style.css)
# ---------------------------------------------------------------------------
mkdir -p "$OUTPUT_DIR/static"
shared_style_css "$OUTPUT_DIR/static/style.css"

# ---------------------------------------------------------------------------
# 4. Shared dotfiles
# ---------------------------------------------------------------------------
shared_gitignore    python "$OUTPUT_DIR"
shared_dockerignore        "$OUTPUT_DIR"
shared_app_json            "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# 5. Substitute {{VARIABLES}} in all generated files
# ---------------------------------------------------------------------------
template_sub_all "$OUTPUT_DIR"
