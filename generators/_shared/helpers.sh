#!/usr/bin/env bash
# generators/_shared/helpers.sh — Shared utilities for ferry generators

SHARED_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Portable in-place sed (BSD sed on macOS requires -i '').
sed_inplace() {
	if sed --version >/dev/null 2>&1; then
		sed -i "$@"
	else
		sed -i '' "$@"
	fi
}

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
    sed_inplace \
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

# Copy shared country metadata for ISO code enrichment
shared_country_meta() {
    local dest="$1"
    cp "$SHARED_DIR/assets/country-meta.min.json" "$dest"
}

# Copy vendored IP database assets into generated apps.
# Refresh the vendored copies with scripts/update-ipdb-assets.sh.
# Sources: sapics/ip-location-db (country + ASN), X4BNet/lists_vpn (VPN + datacenter CIDRs),
# Tor Project (exit list), PeeringDB (ASN→info_type classification).
shared_ipdb_assets() {
    local dest_dir="$1"
    local asset_dir
    local files=(
        geo-whois-asn-country-ipv4-num.csv
        iptoasn-asn-ipv4-num.csv
        x4bnet-vpn-ipv4.txt
        x4bnet-datacenter-ipv4.txt
        tor-exits.txt
        peeringdb-asn-types.json
        ipdb-source.json
    )

    asset_dir="$SHARED_DIR/assets/ipdb"
    for f in "${files[@]}"; do
        [[ -f "$asset_dir/$f" ]] || {
            echo "missing vendored asset: $asset_dir/$f (run scripts/update-ipdb-assets.sh)" >&2
            return 1
        }
    done

    mkdir -p "$dest_dir/data"
    for f in "${files[@]}"; do
        cp "$asset_dir/$f" "$dest_dir/data/$f"
    done
}

# Copy shared app.json healthcheck template
# Usage: shared_app_json <dest_dir> [<health_path>]
# Default health_path is /health; React should pass /
shared_app_json() {
    local dest_dir="$1" health_path="${2:-/health}"
    cp "$SHARED_DIR/app.json.template" "$dest_dir/app.json"
    sed_inplace "s|{{HEALTHCHECK_PATH}}|${health_path}|g" "$dest_dir/app.json"
}

# Count files in the output directory (for reporting)
count_files() {
    local dir="$1"
    find "$dir" -type f | wc -l
}
