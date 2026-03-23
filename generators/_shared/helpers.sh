#!/usr/bin/env bash
# generators/_shared/helpers.sh — Shared utilities for ferry generators

SHARED_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Copy a .template file, stripping the .template extension
# Usage: template_copy <src> <dest_dir> [<dest_name>]
template_copy() {
    local src="$1" dest_dir="$2" dest_name="${3:-}"
    if [[ -z "$dest_name" ]]; then
        dest_name="$(basename "$src" .template)"
    fi
    cp "$src" "$dest_dir/$dest_name"
}

# Substitute {{VAR}} placeholders in a file
# Uses global: APP_NAME, APP_PORT, FERRY_VERSION
template_sub() {
    local file="$1"
    local year
    year="$(date +%Y)"
    sed -i \
        -e "s|{{APP_NAME}}|${APP_NAME}|g" \
        -e "s|{{APP_PORT}}|${APP_PORT}|g" \
        -e "s|{{FERRY_VERSION}}|${FERRY_VERSION}|g" \
        -e "s|{{YEAR}}|${year}|g" \
        "$file"
}

# Substitute all template files in a directory tree
template_sub_all() {
    local dir="$1"
    while IFS= read -r -d '' file; do
        template_sub "$file"
    done < <(find "$dir" -type f -print0)
}

# Copy a shared asset to the output directory
# Usage: shared_copy <asset_path_relative_to_shared> <dest>
shared_copy() {
    local asset="$1" dest="$2"
    cp "$SHARED_DIR/$asset" "$dest"
}

# Copy the appropriate .gitignore for a language
# Usage: shared_gitignore <type> <dest_dir>
# Types: node, python, go, rust, ruby
shared_gitignore() {
    local type="$1" dest_dir="$2"
    cp "$SHARED_DIR/templates/gitignore-${type}.template" "$dest_dir/.gitignore"
}

# Copy the shared .dockerignore
shared_dockerignore() {
    local dest_dir="$1"
    cp "$SHARED_DIR/templates/dockerignore.template" "$dest_dir/.dockerignore"
}

# Copy style.css to a destination
shared_style_css() {
    local dest="$1"
    cp "$SHARED_DIR/assets/style.css" "$dest"
}

# Count files in the output directory (for reporting)
count_files() {
    local dir="$1"
    find "$dir" -type f | wc -l
}
