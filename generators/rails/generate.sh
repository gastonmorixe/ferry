#!/usr/bin/env bash
# generators/rails/generate.sh — Ferry generator for Rails
#
# Receives from caller:
#   APP_NAME      validated app name
#   APP_PORT      port (default: 3000)
#   OUTPUT_DIR    target directory (already created, empty)
#   SHARED_DIR    path to generators/_shared
#   FERRY_VERSION ferry version string
set -euo pipefail

GENERATOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load shared helpers
# shellcheck source=../_shared/helpers.sh
source "$SHARED_DIR/helpers.sh"

TMPL="$GENERATOR_DIR/templates"

# Derive a CamelCase module name from APP_NAME (e.g. my-app -> MyApp)
APP_NAME_CAMEL="$(echo "$APP_NAME" | sed 's/[_-]\([a-z]\)/\U\1/g; s/^\([a-z]\)/\U\1/g')"

# ---------------------------------------------------------------------------
# 1. Top-level files
# ---------------------------------------------------------------------------
template_copy "$TMPL/Gemfile.template"   "$OUTPUT_DIR"
template_copy "$TMPL/config.ru.template" "$OUTPUT_DIR"

# Gemfile.lock — empty placeholder so Docker COPY layer exists
touch "$OUTPUT_DIR/Gemfile.lock"

# ---------------------------------------------------------------------------
# 2. config/
# ---------------------------------------------------------------------------
mkdir -p "$OUTPUT_DIR/config/environments"
template_copy "$TMPL/config/boot.rb.template"                     "$OUTPUT_DIR/config"
template_copy "$TMPL/config/application.rb.template"              "$OUTPUT_DIR/config"
template_copy "$TMPL/config/routes.rb.template"                   "$OUTPUT_DIR/config"
template_copy "$TMPL/config/environment.rb.template"              "$OUTPUT_DIR/config"
template_copy "$TMPL/config/environments/production.rb.template"  "$OUTPUT_DIR/config/environments"

# ---------------------------------------------------------------------------
# 3. app/controllers/
# ---------------------------------------------------------------------------
mkdir -p "$OUTPUT_DIR/app/controllers"
template_copy "$TMPL/app/controllers/application_controller.rb.template" "$OUTPUT_DIR/app/controllers"
template_copy "$TMPL/app/controllers/info_controller.rb.template"         "$OUTPUT_DIR/app/controllers"

# ---------------------------------------------------------------------------
# 4. app/views/
# ---------------------------------------------------------------------------
mkdir -p "$OUTPUT_DIR/app/views/info"
mkdir -p "$OUTPUT_DIR/app/views/layouts"
template_copy "$TMPL/app/views/info/index.html.erb.template"           "$OUTPUT_DIR/app/views/info"
template_copy "$TMPL/app/views/layouts/application.html.erb.template"  "$OUTPUT_DIR/app/views/layouts"

# ---------------------------------------------------------------------------
# 5. bin/
# ---------------------------------------------------------------------------
mkdir -p "$OUTPUT_DIR/bin"
template_copy "$TMPL/bin/rails.template" "$OUTPUT_DIR/bin" "rails"
chmod +x "$OUTPUT_DIR/bin/rails"

# ---------------------------------------------------------------------------
# 6. Dockerfile
# ---------------------------------------------------------------------------
template_copy "$TMPL/Dockerfile.template" "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# 7. public/ directory (style.css)
# ---------------------------------------------------------------------------
mkdir -p "$OUTPUT_DIR/public"
shared_style_css "$OUTPUT_DIR/public/style.css"

# ---------------------------------------------------------------------------
# 8. Shared dotfiles
# ---------------------------------------------------------------------------
shared_gitignore    ruby "$OUTPUT_DIR"
shared_dockerignore      "$OUTPUT_DIR"
shared_app_json          "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# 9. Substitute {{VARIABLES}} in all generated files
#    Run standard substitutions first, then APP_NAME_CAMEL
# ---------------------------------------------------------------------------
template_sub_all "$OUTPUT_DIR"

# Substitute {{APP_NAME_CAMEL}} (not handled by shared template_sub)
find "$OUTPUT_DIR" -type f -print0 | while IFS= read -r -d '' f; do
    sed -i "s|{{APP_NAME_CAMEL}}|${APP_NAME_CAMEL}|g" "$f"
done
