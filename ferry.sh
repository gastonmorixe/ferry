#!/usr/bin/env bash
#
# ferry — Deploy web apps via Dokku + Cloudflare Tunnel
#
# https://github.com/gastonmorixe/ferry
#
set -euo pipefail

FERRY_VERSION="0.12.3"
###############################################################################
# Constants & Config
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
# CONFIG_FILE is no longer used — ingress is managed via the Cloudflare API
# (remotely-managed tunnel). Kept as a comment for historical reference.
ENV_FILE="$SCRIPT_DIR/.env"
CERT_DIR="$SCRIPT_DIR/tunnels/providers/cloudflare"

###############################################################################
# Terminal Capabilities
###############################################################################

# Detect color tier: 256 → 16 → none
_COLOR_TIER=0
if [[ -t 1 ]]; then
    _num_colors=$(tput colors 2>/dev/null || echo 0)
    if ((_num_colors >= 256)); then
        _COLOR_TIER=256
    elif ((_num_colors >= 8)); then
        _COLOR_TIER=16
    fi
fi

# TTY detection (for interactive features)
_IS_TTY=false
[[ -t 0 ]] && _IS_TTY=true

# Terminal width
_term_width() { tput cols 2>/dev/null || echo 80; }

_divider_line() {
    local width="${1:-0}"
    (( width > 40 )) && width=40
    (( width < 0 )) && width=0

    local line=""
    while (( width > 0 )); do
        line+="─"
        ((width--))
    done

    printf '%s' "$line"
}

# --- 256-color palette (muted, modern) ---
if ((_COLOR_TIER >= 256)); then
    C_SUCCESS='\033[38;5;108m'    # sage green
    C_ERROR='\033[38;5;167m'      # muted red
    C_WARN='\033[38;5;179m'       # warm amber
    C_INFO='\033[38;5;110m'       # steel blue
    C_ACCENT='\033[38;5;139m'     # soft purple
    C_CHROME='\033[38;5;240m'     # dark gray — borders
    C_DIM='\033[38;5;245m'        # mid gray — secondary text
    C_WHITE='\033[38;5;252m'      # soft white — primary text
    C_BOLD='\033[1m'
    C_RESET='\033[0m'
elif ((_COLOR_TIER >= 16)); then
    C_SUCCESS='\033[0;32m'
    C_ERROR='\033[0;31m'
    C_WARN='\033[1;33m'
    C_INFO='\033[0;34m'
    C_ACCENT='\033[0;35m'
    C_CHROME='\033[2m'
    C_DIM='\033[2m'
    C_WHITE='\033[0m'
    C_BOLD='\033[1m'
    C_RESET='\033[0m'
else
    C_SUCCESS='' C_ERROR='' C_WARN='' C_INFO=''
    C_ACCENT='' C_CHROME='' C_DIM='' C_WHITE=''
    C_BOLD='' C_RESET=''
fi


ferry_intro() {
    local _date
    _date=$(date '+%Y-%m-%d %H:%M %z')
    if ((_COLOR_TIER >= 256)); then
        echo -e "  ${C_INFO}⛵${C_RESET} ${C_BOLD}${C_WHITE}ferry${C_RESET} ${C_DIM}v${FERRY_VERSION}${C_RESET}"
        echo -e "  ${C_DIM}${_date}  ·  ${SCRIPT_DIR}${C_RESET}"
    elif ((_COLOR_TIER >= 16)); then
        echo -e "  ${C_BOLD}ferry${C_RESET} ${C_DIM}v${FERRY_VERSION}${C_RESET}"
        echo -e "  ${C_DIM}${_date}${C_RESET}"
    else
        echo "  ferry v${FERRY_VERSION}"
        echo "  ${_date}"
    fi
}

YES=false
_AUTH_CHECKED=false

###############################################################################
# Helpers
###############################################################################

info()    { echo -e "  ${C_INFO}·${C_RESET} $*"; }
success() { echo -e "  ${C_SUCCESS}✓${C_RESET} $*"; }
warn()    { echo -e "  ${C_WARN}!${C_RESET} $*"; }
error()   { echo -e "  ${C_ERROR}✗${C_RESET} $*"; }
dim()     { echo -e "  ${C_DIM}$*${C_RESET}"; }
step()    { echo -e "  ${C_ACCENT}[$1]${C_RESET} $2"; }
header()  { echo ""; echo -e "  ${C_BOLD}${C_WHITE}$*${C_RESET}"; }

section_header() {
    local title="$1"
    # Keep the full header block at 40 visible columns so headers line up.
    local line_len=$((40 - ${#title} - 1))
    ((line_len < 0)) && line_len=0
    local line
    line=$(_divider_line "$line_len")
    echo ""
    echo -e "  ${C_BOLD}${C_WHITE}${title}${C_RESET} ${C_CHROME}${line}${C_RESET}"
}

kv() {
    local key="$1" value="$2" indent="${3:-4}"
    local pad
    pad=$(printf '%*s' "$indent" '')
    printf '%s%b%-18s%b %s\n' "$pad" "$C_DIM" "$key" "$C_RESET" "$value"
}

kv_color() {
    local key="$1" value="$2" color="$3" indent="${4:-4}"
    local pad
    pad=$(printf '%*s' "$indent" '')
    printf '%s%b%-18s%b %b%s%b\n' "$pad" "$C_DIM" "$key" "$C_RESET" "$color" "$value" "$C_RESET"
}

box() {
    local lines=()
    if [[ $# -gt 0 ]]; then
        lines=("$@")
    else
        while IFS= read -r line; do lines+=("$line"); done
    fi

    local max_len=0
    for line in "${lines[@]}"; do
        local stripped
        stripped=$(echo -e "$line" | sed 's/\x1b\[[0-9;]*m//g')
        (( ${#stripped} > max_len )) && max_len=${#stripped}
    done
    (( max_len < 30 )) && max_len=30

    local border
    border=$(_divider_line $((max_len + 2)))

    echo -e "  ${C_CHROME}╭${border}╮${C_RESET}"
    for line in "${lines[@]}"; do
        local stripped
        stripped=$(echo -e "$line" | sed 's/\x1b\[[0-9;]*m//g')
        local pad_len=$((max_len - ${#stripped}))
        local pad=""
        ((pad_len > 0)) && pad=$(printf '%*s' "$pad_len" '')
        echo -e "  ${C_CHROME}│${C_RESET} ${line}${pad} ${C_CHROME}│${C_RESET}"
    done
    echo -e "  ${C_CHROME}╰${border}╯${C_RESET}"
}

prompt() {
    local label="$1" default="${2:-}"
    if [[ -n "$default" ]]; then
        echo -en "  ${C_DIM}${label}${C_RESET} ${C_DIM}[${default}]${C_RESET} ${C_ACCENT}❯${C_RESET} "
    else
        echo -en "  ${C_DIM}${label}${C_RESET} ${C_ACCENT}❯${C_RESET} "
    fi
}

prompt_hint() {
    local hint="${1:-}"
    [[ -z "$hint" ]] && return 0
    echo -e "  ${C_DIM}${hint}${C_RESET}"
}

tui_read() {
    local __var="$1" label="$2" default="${3:-}" allow_empty="${4:-false}"
    local reply

    while true; do
        prompt "$label" "$default"
        prompt_hint "type ${C_BOLD}back${C_RESET}${C_DIM} to go back, ${C_BOLD}quit${C_RESET}${C_DIM} to exit"
        IFS= read -r reply || return 3

        case "${reply,,}" in
            back|b|cancel) return 2 ;;
            quit|q|exit)   return 3 ;;
        esac

        if [[ -z "$reply" && -n "$default" ]]; then
            reply="$default"
        fi

        if [[ -z "$reply" && "$allow_empty" != true ]]; then
            warn "A value is required. Type back to return."
            continue
        fi

        printf -v "$__var" '%s' "$reply"
        return 0
    done
}

confirm() {
    local msg="${1:-Continue?}"
    if $YES; then return 0; fi
    if ! $_IS_TTY; then return 2; fi

    local confirm_rc=0
    if tui_select "$msg" "Yes" "No"; then
        confirm_rc=0
    else
        confirm_rc=$?
    fi
    case "$confirm_rc" in
        0)
            case "$_TUI_SELECTED" in
                0) return 0 ;;
                1) return 2 ;;
            esac
            ;;
        2|3) return "$confirm_rc" ;;
        *) return 2 ;;
    esac
}

confirm_name() {
    local name="$1"
    if $YES; then return 0; fi
    if ! $_IS_TTY; then return 2; fi

    echo ""
    echo -e "  ${C_ERROR}Type '${C_BOLD}${name}${C_RESET}${C_ERROR}' to confirm:${C_RESET}"
    prompt_hint "type ${C_BOLD}back${C_RESET}${C_DIM} to cancel, ${C_BOLD}quit${C_RESET}${C_DIM} to exit"

    local reply
    while true; do
        echo -en "  ${C_ACCENT}❯${C_RESET} "
        IFS= read -r reply || return 3
        case "${reply,,}" in
            back|b|cancel) return 2 ;;
            quit|q|exit)   return 3 ;;
        esac
        if [[ "$reply" == "$name" ]]; then
            return 0
        fi
        warn "Name did not match. Try again or type back."
    done
}

dokku_cmd() {
    docker compose -f "$COMPOSE_FILE" exec -T dokku dokku "$@" 2>&1 </dev/null
}

###############################################################################
# Cloudflare Auth
###############################################################################

# Token creation URL
CF_TOKEN_URL="https://dash.cloudflare.com/profile/api-tokens"

env_set() {
    # Set a key=value in .env, creating or updating as needed
    local key="$1" value="$2"
    if [[ -f "$ENV_FILE" ]] && grep -q "^${key}=" "$ENV_FILE"; then
        # Use awk instead of sed to avoid delimiter collisions with special chars
        awk -v k="$key" -v v="$value" 'BEGIN{FS=OFS="="} $1==k{$0=k"="v}{print}' \
            "$ENV_FILE" > "${ENV_FILE}.tmp" && mv "${ENV_FILE}.tmp" "$ENV_FILE"
    else
        echo "${key}=${value}" >> "$ENV_FILE"
    fi
    # Also export for current session
    export "$key=$value"
}

cf_token_verify() {
    # Verify the current CF_API_TOKEN. Returns 0 if valid.
    # Sets _cf_token_status to: "valid", "invalid", "expired", or "missing"
    # Tries /user/tokens/verify first (user tokens), then falls back to
    # /accounts/{id}/tokens/verify (account tokens).
    if [[ -z "$CF_API_TOKEN" ]]; then
        _cf_token_status="missing"
        return 1
    fi

    local resp
    # Try user token endpoint first
    resp=$(cf_api GET "/user/tokens/verify" 2>/dev/null) || true

    # If user endpoint fails and we have an account ID, try account endpoint
    if ! cf_api_ok "$resp" 2>/dev/null; then
        if [[ -n "$CF_ACCOUNT_ID" ]]; then
            resp=$(cf_api GET "/accounts/${CF_ACCOUNT_ID}/tokens/verify" 2>/dev/null) || true
        else
            # No account ID yet — try to discover it to test account token
            local acct_resp acct_id
            acct_resp=$(cf_api GET "/accounts?page=1&per_page=1" 2>/dev/null) || true
            acct_id=$(echo "$acct_resp" | jq -r '.result[0].id // empty' 2>/dev/null) || true
            if [[ -n "$acct_id" ]]; then
                resp=$(cf_api GET "/accounts/${acct_id}/tokens/verify" 2>/dev/null) || true
            fi
        fi
    fi

    if cf_api_ok "$resp" 2>/dev/null; then
        local status_val
        status_val=$(echo "$resp" | jq -r '.result.status // "unknown"')
        if [[ "$status_val" == "active" ]]; then
            _cf_token_status="valid"
            return 0
        elif [[ "$status_val" == "expired" ]]; then
            _cf_token_status="expired"
            return 1
        else
            _cf_token_status="invalid"
            return 1
        fi
    else
        # Last resort: try listing zones — if it works, the token is valid
        local zones_resp
        zones_resp=$(cf_api GET "/zones?per_page=1" 2>/dev/null) || true
        if cf_api_ok "$zones_resp" 2>/dev/null; then
            _cf_token_status="valid"
            return 0
        fi
        _cf_token_status="invalid"
        return 1
    fi
}

cf_discover_account_id() {
    # Auto-discover and cache the Cloudflare account ID from the API token
    if [[ -n "$CF_ACCOUNT_ID" ]]; then
        echo "$CF_ACCOUNT_ID"
        return 0
    fi

    local account_id="" account_name=""

    # Try /accounts endpoint first
    local resp
    resp=$(cf_api GET "/accounts?page=1&per_page=1" 2>/dev/null) || true
    if cf_api_ok "$resp" 2>/dev/null; then
        account_id=$(echo "$resp" | jq -r '.result[0].id // empty')
        account_name=$(echo "$resp" | jq -r '.result[0].name // empty')
    fi

    # Fallback: extract account from zones response
    if [[ -z "$account_id" ]]; then
        resp=$(cf_api GET "/zones?per_page=1" 2>/dev/null) || true
        if cf_api_ok "$resp" 2>/dev/null; then
            account_id=$(echo "$resp" | jq -r '.result[0].account.id // empty')
            account_name=$(echo "$resp" | jq -r '.result[0].account.name // empty')
        fi
    fi

    if [[ -n "$account_id" ]]; then
        CF_ACCOUNT_ID="$account_id"
        env_set "CF_ACCOUNT_ID" "$account_id"
        info "Discovered account: $account_name ($account_id)"
        echo "$account_id"
        return 0
    fi

    return 1
}

cf_check_permissions() {
    # Test what the current token can do. Prints a report.
    # Returns 0 if all critical permissions pass, 1 if any critical ones fail.
    local all_ok=true

    # Test 1: List zones (Zone:Read)
    local zones_resp zones_ok=false zone_count=0
    zones_resp=$(cf_api GET "/zones?per_page=50" 2>/dev/null) || true
    if cf_api_ok "$zones_resp" 2>/dev/null; then
        zone_count=$(echo "$zones_resp" | jq -r '.result_info.total_count // 0')
        zones_ok=true
    fi
    if $zones_ok; then
        echo -e "    ${C_SUCCESS}✓${C_RESET} Zone:Read          — $zone_count zone(s) accessible"
    else
        echo -e "    ${C_ERROR}✗${C_RESET} Zone:Read          — cannot list zones"
        all_ok=false
    fi

    # Test 2: DNS read probe (Edit is required for deploy; this only verifies read access)
    local dns_ok=false
    if $zones_ok && ((zone_count > 0)); then
        local first_zone_id
        first_zone_id=$(echo "$zones_resp" | jq -r '.result[0].id')
        local dns_resp
        dns_resp=$(cf_api GET "/zones/${first_zone_id}/dns_records?per_page=1" 2>/dev/null) || true
        if cf_api_ok "$dns_resp" 2>/dev/null; then
            dns_ok=true
        fi
    fi
    if $dns_ok; then
        echo -e "    ${C_SUCCESS}✓${C_RESET} DNS:Edit           — can read DNS records (Edit required for deploy)"
    else
        echo -e "    ${C_ERROR}✗${C_RESET} DNS:Edit           — cannot access DNS records"
        all_ok=false
    fi

    # Test 3: Tunnel:Read — list tunnels
    local tunnel_list_ok=false tunnel_resp=""
    if [[ -n "$CF_ACCOUNT_ID" ]]; then
        tunnel_resp=$(cf_api GET "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel?per_page=50" 2>/dev/null) || true
        if cf_api_ok "$tunnel_resp" 2>/dev/null; then
            tunnel_list_ok=true
        fi
    fi
    if $tunnel_list_ok; then
        echo -e "    ${C_SUCCESS}✓${C_RESET} Tunnel:Read        — can list tunnels"
    else
        echo -e "    ${C_ERROR}✗${C_RESET} Tunnel:Read        — cannot list tunnels (required for login tunnel bootstrap)"
        all_ok=false
    fi

    # Test 4: Tunnel:Edit — read tunnel configuration (zone-scoped tokens often fail here)
    local tunnel_edit_ok=false tunnel_probe_id=""
    if $tunnel_list_ok && [[ -n "$CF_ACCOUNT_ID" ]]; then
        if [[ -n "$TUNNEL_ID" ]]; then
            tunnel_probe_id="$TUNNEL_ID"
        else
            tunnel_probe_id=$(echo "$tunnel_resp" | jq -r '.result[0].id // empty')
        fi
        if [[ -n "$tunnel_probe_id" ]]; then
            local cfg_resp
            cfg_resp=$(cf_api GET "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${tunnel_probe_id}/configurations" 2>/dev/null) || true
            if cf_api_ok "$cfg_resp" 2>/dev/null; then
                tunnel_edit_ok=true
            fi
        fi
    fi
    if $tunnel_edit_ok; then
        echo -e "    ${C_SUCCESS}✓${C_RESET} Tunnel:Edit        — can read tunnel config"
    else
        echo -e "    ${C_ERROR}✗${C_RESET} Tunnel:Edit        — cannot read tunnel config (Account → Cloudflare Tunnel → Edit)"
        all_ok=false
    fi

    # List accessible zones
    if $zones_ok && ((zone_count > 0)); then
        echo ""
        echo -e "    ${C_BOLD}${C_WHITE}Accessible zones:${C_RESET}"
        echo "$zones_resp" | jq -r '.result[] | "      " + .name + " (" + .status + ")"'
    fi

    $all_ok
}

cf_tunnel_get_token() {
    # Fetch connector token for a remotely-managed tunnel. Prints token to stdout.
    local tunnel_id="$1"
    local resp token
    resp=$(cf_api GET "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${tunnel_id}/token" 2>/dev/null) || true
    if ! cf_api_ok "$resp" 2>/dev/null; then
        return 1
    fi
    # API may return result as a bare string or as {token: "..."}
    token=$(echo "$resp" | jq -r 'if (.result|type)=="string" then .result else (.result.token // empty) end' 2>/dev/null) || true
    if [[ -z "$token" || "$token" == "null" ]]; then
        return 1
    fi
    echo "$token"
}

cf_tunnel_create() {
    # Create a remotely-managed tunnel (config_src=cloudflare).
    # Prints "id<TAB>name<TAB>token" on success.
    local name="$1"
    local body resp tunnel_id tunnel_name token
    body=$(jq -n --arg name "$name" '{name:$name, config_src:"cloudflare"}')
    resp=$(cf_api POST "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel" "$body" 2>/dev/null) || true
    if ! cf_api_ok "$resp" 2>/dev/null; then
        error "Failed to create tunnel: $(cf_api_error "$resp")"
        return 1
    fi
    tunnel_id=$(echo "$resp" | jq -r '.result.id // empty')
    tunnel_name=$(echo "$resp" | jq -r '.result.name // empty')
    token=$(echo "$resp" | jq -r '.result.token // empty')
    if [[ -z "$tunnel_id" ]]; then
        error "Tunnel create response missing id"
        return 1
    fi
    if [[ -z "$token" || "$token" == "null" ]]; then
        token=$(cf_tunnel_get_token "$tunnel_id") || {
            error "Tunnel created ($tunnel_id) but connector token could not be fetched"
            return 1
        }
    fi
    printf '%s\t%s\t%s\n' "$tunnel_id" "$tunnel_name" "$token"
}

_cf_maybe_restart_cloudflared() {
    # Recreate cloudflared if the compose service exists / is up so it picks up TUNNEL_TOKEN.
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        return 0
    fi
    if ! command -v docker &>/dev/null; then
        return 0
    fi
    local state
    state=$(docker compose -f "$COMPOSE_FILE" ps --format '{{.State}}' cloudflared 2>/dev/null || true)
    if [[ -z "$state" ]]; then
        dim "cloudflared not running yet — token will apply on next: docker compose up -d"
        return 0
    fi
    cloudflared_restart || {
        warn "Tunnel credentials saved, but cloudflared restart failed. Run: ferry reload"
        return 0
    }
}

cf_ensure_tunnel() {
    # Ensure host TUNNEL_ID + TUNNEL_TOKEN exist in .env (remotely-managed tunnel).
    # Usage: cf_ensure_tunnel [preferred_name] [require_exact_name]
    # Idempotent: keeps a valid existing pair; fills missing token; otherwise list/pick/create.
    local preferred_name="${1:-ferry}"
    local require_exact_name="${2:-false}"
    local list_resp count match_id="" match_name="" tunnel_id="" tunnel_name="" tunnel_token=""

    if [[ -z "$CF_ACCOUNT_ID" ]]; then
        error "CF_ACCOUNT_ID required for tunnel setup. Re-run ferry login after account discovery succeeds."
        return 1
    fi

    # Path A: both already set — verify the tunnel still exists
    if [[ -n "$TUNNEL_ID" && -n "${TUNNEL_TOKEN:-}" ]]; then
        local verify_resp
        verify_resp=$(cf_api GET "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}" 2>/dev/null) || true
        if cf_api_ok "$verify_resp" 2>/dev/null; then
            local deleted
            deleted=$(echo "$verify_resp" | jq -r '.result.deleted_at // empty')
            if [[ -z "$deleted" ]]; then
                tunnel_name=$(echo "$verify_resp" | jq -r '.result.name // empty')
                if ! $require_exact_name || [[ "$tunnel_name" == "$preferred_name" ]]; then
                    success "Host tunnel ready: ${tunnel_name:-tunnel} ($TUNNEL_ID)"
                    _cf_maybe_restart_cloudflared
                    return 0
                fi
                warn "Configured TUNNEL_ID names '$tunnel_name', not requested '$preferred_name'. Reconfiguring..."
            else
                warn "Configured TUNNEL_ID is missing or deleted in Cloudflare. Reconfiguring..."
            fi
        else
            warn "Configured TUNNEL_ID is missing or deleted in Cloudflare. Reconfiguring..."
        fi
        if $require_exact_name; then
            TUNNEL_ID=""
            TUNNEL_TOKEN=""
        fi
    fi

    # Path B: ID set, token missing — preserve legacy token fetch unless a name was explicit.
    if [[ -n "$TUNNEL_ID" && -z "${TUNNEL_TOKEN:-}" ]]; then
        if $require_exact_name; then
            local verify_resp deleted
            verify_resp=$(cf_api GET "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}" 2>/dev/null) || true
            if cf_api_ok "$verify_resp" 2>/dev/null; then
                deleted=$(echo "$verify_resp" | jq -r '.result.deleted_at // empty')
                if [[ -z "$deleted" ]]; then
                    tunnel_name=$(echo "$verify_resp" | jq -r '.result.name // empty')
                    if [[ "$tunnel_name" != "$preferred_name" ]]; then
                        warn "Configured TUNNEL_ID names '$tunnel_name', not requested '$preferred_name'. Reconfiguring..."
                        TUNNEL_ID=""
                    fi
                else
                    TUNNEL_ID=""
                fi
            else
                TUNNEL_ID=""
            fi
        fi
        if [[ -n "$TUNNEL_ID" ]]; then
            info "Fetching connector token for TUNNEL_ID=$TUNNEL_ID..."
            tunnel_token=$(cf_tunnel_get_token "$TUNNEL_ID") || {
                error "Could not fetch TUNNEL_TOKEN for $TUNNEL_ID."
                error "Token needs Account → Cloudflare Tunnel → Edit, and the tunnel must be remotely managed (config_src=cloudflare)."
                return 1
            }
            env_set "TUNNEL_TOKEN" "$tunnel_token"
            success "TUNNEL_TOKEN saved to $ENV_FILE"
            _cf_maybe_restart_cloudflared
            return 0
        fi
    fi

    # Path C: list existing tunnels and pick / create
    info "Looking up Cloudflare tunnels..."
    list_resp=$(cf_api GET "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel?is_deleted=false&per_page=50" 2>/dev/null) || true
    if ! cf_api_ok "$list_resp" 2>/dev/null; then
        error "Cannot list tunnels: $(cf_api_error "$list_resp")"
        error "API token needs Account → Cloudflare Tunnel → Edit"
        return 1
    fi

    count=$(echo "$list_resp" | jq '[.result[] | select((.deleted_at // null) == null)] | length')
    match_id=$(echo "$list_resp" | jq -r --arg n "$preferred_name" \
        '[.result[] | select((.deleted_at // null) == null and .name == $n)][0].id // empty')
    match_name=$(echo "$list_resp" | jq -r --arg n "$preferred_name" \
        '[.result[] | select((.deleted_at // null) == null and .name == $n)][0].name // empty')

    # An explicit noninteractive name is a safety boundary: never adopt another tunnel.
    # With no exact match, create the requested remote-managed tunnel before legacy branches.
    if $require_exact_name && $YES && [[ -z "$match_id" ]]; then
        info "No active tunnel named '${preferred_name}'. Creating remotely-managed tunnel..."
        local created
        created=$(cf_tunnel_create "$preferred_name") || return 1
        tunnel_id=$(echo "$created" | cut -f1)
        tunnel_name=$(echo "$created" | cut -f2)
        tunnel_token=$(echo "$created" | cut -f3)
        success "Created tunnel: $tunnel_name ($tunnel_id)"
    elif ((count == 0)); then
        info "No tunnels found. Creating remotely-managed tunnel '${preferred_name}'..."
        if ! $YES && [[ -t 0 ]]; then
            local create_choice=0
            if confirm "Create tunnel '${preferred_name}'?"; then
                create_choice=0
            else
                create_choice=$?
            fi
            case "$create_choice" in
                0) ;;
                2) error "Tunnel setup cancelled."; return 1 ;;
                3) return 3 ;;
                *) error "Tunnel setup cancelled."; return 1 ;;
            esac
        fi
        local created
        created=$(cf_tunnel_create "$preferred_name") || return 1
        tunnel_id=$(echo "$created" | cut -f1)
        tunnel_name=$(echo "$created" | cut -f2)
        tunnel_token=$(echo "$created" | cut -f3)
        success "Created tunnel: $tunnel_name ($tunnel_id)"
    elif ((count == 1)); then
        tunnel_id=$(echo "$list_resp" | jq -r '[.result[] | select((.deleted_at // null) == null)][0].id')
        tunnel_name=$(echo "$list_resp" | jq -r '[.result[] | select((.deleted_at // null) == null)][0].name')
        info "Found existing tunnel: $tunnel_name ($tunnel_id)"
        if ! $YES && [[ -t 0 ]]; then
            local use_choice=0
            if confirm "Use this tunnel for Ferry?"; then
                use_choice=0
            else
                use_choice=$?
            fi
            case "$use_choice" in
                0) ;;
                2)
                    info "Creating new tunnel '${preferred_name}' instead..."
                    local created
                    created=$(cf_tunnel_create "$preferred_name") || return 1
                    tunnel_id=$(echo "$created" | cut -f1)
                    tunnel_name=$(echo "$created" | cut -f2)
                    tunnel_token=$(echo "$created" | cut -f3)
                    ;;
                3) return 3 ;;
                *) error "Tunnel setup cancelled."; return 1 ;;
            esac
        fi
        if [[ -z "$tunnel_token" ]]; then
            tunnel_token=$(cf_tunnel_get_token "$tunnel_id") || {
                error "Could not fetch connector token for tunnel $tunnel_id (is it remotely managed?)."
                return 1
            }
        fi
    else
        # Multiple tunnels: prefer name match, else interactive pick / -y heuristics
        if [[ -n "$match_id" ]] && $YES; then
            tunnel_id="$match_id"
            tunnel_name="$match_name"
            info "Using tunnel matching --tunnel-name: $tunnel_name ($tunnel_id)"
        elif $YES; then
            # Prefer remotely-managed, else first active
            tunnel_id=$(echo "$list_resp" | jq -r '
                (
                  [.result[] | select((.deleted_at // null) == null and (.config_src // "") == "cloudflare")][0].id
                ) // (
                  [.result[] | select((.deleted_at // null) == null)][0].id
                ) // empty
            ')
            tunnel_name=$(echo "$list_resp" | jq -r --arg id "$tunnel_id" \
                '.result[] | select(.id == $id) | .name' | head -1)
            info "Non-interactive: selected tunnel $tunnel_name ($tunnel_id)"
        else
            # Build selector options: existing tunnels + create-new
            local opts=()
            local ids=() names=()
            while IFS=$'\t' read -r tid tname tsrc; do
                [[ -z "$tid" ]] && continue
                ids+=("$tid")
                names+=("$tname")
                opts+=("${tname}|${tid} (${tsrc:-local})")
            done < <(echo "$list_resp" | jq -r \
                '.result[] | select((.deleted_at // null) == null) | [.id, .name, (.config_src // "local")] | @tsv')
            opts+=("Create new tunnel '${preferred_name}'|remotely managed (config_src=cloudflare)")

            tui_select --no-back "Select host tunnel for Ferry" "${opts[@]}" || {
                case $? in
                    2) error "Tunnel setup cancelled."; return 1 ;;
                    3) return 3 ;;
                    *) return 1 ;;
                esac
            }

            if ((_TUI_SELECTED >= ${#ids[@]})); then
                local created
                created=$(cf_tunnel_create "$preferred_name") || return 1
                tunnel_id=$(echo "$created" | cut -f1)
                tunnel_name=$(echo "$created" | cut -f2)
                tunnel_token=$(echo "$created" | cut -f3)
                success "Created tunnel: $tunnel_name ($tunnel_id)"
            else
                tunnel_id="${ids[$_TUI_SELECTED]}"
                tunnel_name="${names[$_TUI_SELECTED]}"
                info "Selected tunnel: $tunnel_name ($tunnel_id)"
            fi
        fi

        if [[ -z "$tunnel_token" ]]; then
            tunnel_token=$(cf_tunnel_get_token "$tunnel_id") || {
                error "Could not fetch connector token for tunnel $tunnel_id (is it remotely managed?)."
                dim "Create a new remotely-managed tunnel, or re-run: ferry login --tunnel-name ${preferred_name}"
                return 1
            }
        fi
    fi

    env_set "TUNNEL_ID" "$tunnel_id"
    env_set "TUNNEL_TOKEN" "$tunnel_token"
    success "TUNNEL_ID saved: $tunnel_id"
    success "TUNNEL_TOKEN saved to $ENV_FILE"
    _cf_maybe_restart_cloudflared
    return 0
}

cert_find_for_hostname() {
    # Given a hostname, walk up domain labels to find a matching zone cert.
    # Prints "<path> <zone>" on stdout if found, returns 1 if not.
    # Example: app.example.com -> checks app.example.com.cert -> example.com.cert
    local hostname="$1"
    local domain="$hostname"

    # Check the full hostname first, then walk up by stripping labels
    while [[ "$domain" == *.* ]]; do
        local cert_path="${CERT_DIR}/${domain}.cert"
        if [[ -f "$cert_path" ]]; then
            echo "$cert_path $domain"
            return 0
        fi
        domain="${domain#*.}"
    done
    return 1
}

cert_list_zones() {
    # List all available zone names from cert files
    local cert_file
    for cert_file in "$CERT_DIR"/*.cert; do
        [[ -f "$cert_file" ]] || continue
        local basename
        basename=$(basename "$cert_file" .cert)
        echo "$basename"
    done
}

cert_check_all() {
    # Report all zone certs (replaces cert_check_all)
    local found=false
    local cert_file
    for cert_file in "$CERT_DIR"/*.cert; do
        [[ -f "$cert_file" ]] || continue
        found=true
        local zone
        zone=$(basename "$cert_file" .cert)
        echo -e "    ${C_WARN}Zone cert: ${zone}${C_RESET} ${C_DIM}(fallback for *.${zone} subdomains)${C_RESET}"
    done
    if ! $found; then
        echo -e "    ${C_DIM}No zone certs found (not needed if API token is configured)${C_RESET}"
        return 1
    fi
    return 0
}

cf_auth_check() {
    # Startup auth banner — clear about implications.
    # Non-blocking: warns but does not exit.

    if [[ -z "$CF_API_TOKEN" ]]; then
        echo ""
        box "${C_ERROR}${C_BOLD}Cloudflare API not configured${C_RESET}" \
            "" \
            "  Without it, you cannot:" \
            "    ${C_ERROR}✗${C_RESET} Deploy to domains without a zone cert" \
            "    ${C_ERROR}✗${C_RESET} Auto-create or delete DNS records" \
            "    ${C_ERROR}✗${C_RESET} Manage multiple Cloudflare zones" \
            "" \
            "  Run ${C_ACCENT}ferry login${C_RESET} to set up."
        echo ""
        return 1
    fi

    # Token exists — quick verify (silent on success)
    if ! cf_token_verify; then
        echo ""
        case "$_cf_token_status" in
            expired)
                box "${C_ERROR}${C_BOLD}API token has expired${C_RESET}" \
                    "" \
                    "  DNS operations will fail." \
                    "  Run ${C_ACCENT}ferry login${C_RESET} to fix."
                ;;
            *)
                box "${C_ERROR}${C_BOLD}API token is invalid${C_RESET}" \
                    "" \
                    "  DNS operations will fail." \
                    "  Run ${C_ACCENT}ferry login${C_RESET} to fix."
                ;;
        esac
        echo ""
        return 1
    fi

    # Valid token — auto-discover account ID silently
    if [[ -z "$CF_ACCOUNT_ID" ]]; then
        cf_discover_account_id >/dev/null 2>&1 || true
    fi

    return 0
}

cf_require_auth() {
    # Hard gate: requires valid API auth. Offers to run login if missing.
    # Use this before operations that NEED the API (DNS create/delete).
    local context="${1:-This operation}"

    if [[ -z "$CF_API_TOKEN" ]] || ! cf_token_verify; then
        echo ""
        error "${context} requires a valid Cloudflare API token."
        echo ""
        local auth_choice=0
        if confirm "Run login setup now?"; then
            auth_choice=0
        else
            auth_choice=$?
        fi
        case "$auth_choice" in
            0)
                if cmd_login; then
                    :
                else
                    local login_rc=$?
                    case "$login_rc" in
                        2) return 2 ;;
                        3) return 3 ;;
                        *) return 1 ;;
                    esac
                fi
                # Re-check after login
                if [[ -z "$CF_API_TOKEN" ]] || ! cf_token_verify; then
                    error "Still not authenticated. Cannot proceed."
                    return 1
                fi
                success "Authenticated! Continuing..."
                echo ""
                return 0
            ;;
            2) return 2 ;;
            3) return 3 ;;
            *) return 2 ;;
        esac
    fi
    return 0
}

###############################################################################
# Spinner
###############################################################################

_SPINNER_PID=""
_SPINNER_FRAMES=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

spinner_start() {
    local msg="${1:-}"
    # Non-interactive: just print the message
    if ! $_IS_TTY || ((_COLOR_TIER == 0)); then
        [[ -n "$msg" ]] && info "$msg"
        return
    fi

    (
        local i=0
        while true; do
            printf '\r  %b%s%b %s' "$C_ACCENT" "${_SPINNER_FRAMES[$((i % 10))]}" "$C_RESET" "$msg"
            ((i++)) || true
            sleep 0.08
        done
    ) &
    _SPINNER_PID=$!
    disown "$_SPINNER_PID" 2>/dev/null || true
}

spinner_stop() {
    local status="${1:-success}" msg="${2:-}"
    if [[ -n "$_SPINNER_PID" ]]; then
        kill "$_SPINNER_PID" 2>/dev/null || true
        wait "$_SPINNER_PID" 2>/dev/null || true
        _SPINNER_PID=""
        printf '\r\033[2K'
    fi
    case "$status" in
        success) [[ -n "$msg" ]] && success "$msg" ;;
        error)   [[ -n "$msg" ]] && error "$msg" ;;
        warn)    [[ -n "$msg" ]] && warn "$msg" ;;
    esac
}

###############################################################################
# Ctrl+C Trap
###############################################################################

cleanup() {
    # Kill any running spinner
    if [[ -n "$_SPINNER_PID" ]]; then
        kill "$_SPINNER_PID" 2>/dev/null || true
        wait "$_SPINNER_PID" 2>/dev/null || true
        _SPINNER_PID=""
        printf '\r\033[2K'
    fi
    tput cnorm 2>/dev/null || true
    echo ""
    warn "Interrupted! Operation may be incomplete."
    exit 130
}

# trap is set in _ferry_init() to avoid side effects when sourced for testing

###############################################################################
# Config Generation
###############################################################################

# _generate_default_config and _generate_config_from_dokku removed in v0.8.0.
# Ingress is now managed via the Cloudflare API (remotely-managed tunnel).
# No local config.yml file is needed.

###############################################################################
# Preflight Checks
###############################################################################

preflight() {
    local errors=0
    local running=""

    if ! command -v docker &>/dev/null; then
        error "docker not found"
        ((errors++)) || true
    fi

    if ! docker info &>/dev/null; then
        error "Docker daemon not running or permission denied"
        ((errors++)) || true
    fi

    if [[ ! -f "$COMPOSE_FILE" ]]; then
        error "docker-compose.yml not found at $COMPOSE_FILE"
        ((errors++)) || true
    fi

    if [[ -f "$COMPOSE_FILE" ]]; then
        running="$(docker compose -f "$COMPOSE_FILE" ps --format '{{.Name}}:{{.State}}' 2>/dev/null || true)"
    fi

    if [[ -z "$TUNNEL_ID" ]]; then
        error "TUNNEL_ID not set in $ENV_FILE"
        ((errors++)) || true
    fi

    # Check containers are running
    if ! echo "$running" | grep -q "cloudflared:running"; then
        error "cloudflared container is not running"
        ((errors++)) || true
    fi
    if ! echo "$running" | grep -q "dokku:running"; then
        error "dokku container is not running"
        ((errors++)) || true
    fi

    if ((errors > 0)); then
        error "Preflight failed with $errors error(s). Fix the above issues first."
        return 1
    fi

    # Auth check (non-blocking — just warns, once per session)
    if ! $_AUTH_CHECKED; then
        cf_auth_check || true
        _AUTH_CHECKED=true
    fi
}

sync_missing_ingress_from_dokku() {
    # Ensure every Dokku app domain exists in tunnel ingress (via API).
    local apps
    apps=$(dokku_list_apps 2>/dev/null) || return 1
    local ingress
    ingress=$(_tunnel_get_ingress) || return 1

    local added=0
    local -a added_rules=()
    while IFS= read -r app; do
        [[ -z "$app" ]] && continue
        local domains
        domains=$(dokku_app_domains_all "$app") || return 1
        while IFS= read -r domain; do
            [[ -z "$domain" ]] && continue
            local has
            has=$(printf '%s' "$ingress" | python3 -c "
import json, sys
hostname = sys.argv[1]
rules = json.load(sys.stdin)
for r in rules:
    if r.get('hostname') == hostname:
        print('yes')
        sys.exit(0)
print('no')
" "$domain")
            if [[ "$has" != "yes" ]]; then
                # Add to local list, will push once at the end
                ingress=$(printf '%s' "$ingress" | python3 -c "
import json, sys
hostname = sys.argv[1]
rules = json.load(sys.stdin)
new_rule = {'hostname': hostname, 'service': 'http://dokku:80'}
if len(rules) > 0 and 'hostname' not in rules[-1]:
    rules.insert(-1, new_rule)
else:
    rules.append(new_rule)
print(json.dumps(rules))
" "$domain") || return 1
                ((added++)) || true
                added_rules+=("$app"$'\t'"$domain")
            fi
        done <<< "$domains"
    done <<< "$apps"

    if ((added > 0)); then
        if ! $YES; then
            {
                echo ""
                box "${C_WARN}${C_BOLD}Ingress recovery needed${C_RESET}" \
                    "" \
                    "  Dokku already knows about these app domains, but the Cloudflare Tunnel" \
                    "  ingress list is missing them. Ferry can restore them now so the tunnel" \
                    "  keeps routing those hosts to Dokku." \
                    ""
                for rule in "${added_rules[@]}"; do
                    local rule_app rule_domain
                    IFS=$'\t' read -r rule_app rule_domain <<< "$rule"
                    printf '  %s- %s → http://dokku:80 (Dokku app %s)%s\n' \
                        "$C_DIM" "$rule_domain" "$rule_app" "$C_RESET"
                done
                echo ""
            } >&2
            local recovery_choice=0
            if confirm "Restore these ingress rule(s) now?"; then
                recovery_choice=0
            else
                recovery_choice=$?
            fi
            case "$recovery_choice" in
                0) ;;
                2)
                    echo "  ${C_WARN}!${C_RESET} Skipped ingress recovery." >&2
                    echo "0"
                    return 0
                    ;;
                3) return 3 ;;
                *) echo "0"; return 0 ;;
            esac
        fi

        _tunnel_put_ingress "$ingress" >/dev/null || return 1
        {
            printf '  ! Restored %d missing ingress rule(s) from Dokku before deploy\n' "$added"
            printf '    Why: Dokku already reports these app domains, but the Cloudflare Tunnel ingress list was missing them.\n'
            for rule in "${added_rules[@]}"; do
                local rule_app rule_domain
                IFS=$'\t' read -r rule_app rule_domain <<< "$rule"
                printf '    - %s -> http://dokku:80 (Dokku app %s)\n' "$rule_domain" "$rule_app"
            done
        } >&2
    fi
    echo "$added"
}

app_effective_status() {
    local name="$1"
    local domain="$2"
    local runtime_status has_ingress="no" ingress_state
    runtime_status=$(dokku_app_status "$name")
    if [[ -n "$domain" ]]; then
        ingress_state=$(yaml_has_hostname "$domain") || ingress_state="unknown"
        case "$ingress_state" in
            yes) has_ingress="yes" ;;
            unknown) has_ingress="unknown" ;;
            *) has_ingress="no" ;;
        esac
    fi

    case "$runtime_status" in
        running)
            if [[ "$has_ingress" == "yes" || "$has_ingress" == "unknown" ]]; then
                echo "running"
            else
                echo "unroutable"
            fi
            ;;
        *)
            echo "$runtime_status"
            ;;
    esac
}

###############################################################################
# Tunnel Ingress Operations (via Cloudflare API)
###############################################################################

# Cached tunnel ingress (one Cloudflare API fetch per status run).
_INGRESS_CACHE=""
_INGRESS_CACHE_ERROR=""
_INGRESS_CACHE_LOADED=false

tunnel_ingress_reset_cache() {
    _INGRESS_CACHE=""
    _INGRESS_CACHE_ERROR=""
    _INGRESS_CACHE_LOADED=false
}

tunnel_ingress_fetch() {
    if $_INGRESS_CACHE_LOADED; then
        [[ -z "$_INGRESS_CACHE_ERROR" ]]
        return
    fi
    _INGRESS_CACHE_LOADED=true
    local response
    response=$(cf_api "GET" "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" 2>/dev/null) || {
        _INGRESS_CACHE_ERROR="fetch failed"
        return 1
    }
    if ! cf_api_ok "$response" 2>/dev/null; then
        _INGRESS_CACHE_ERROR=$(cf_api_error "$response")
        return 1
    fi
    _INGRESS_CACHE=$(printf '%s' "$response" | python3 -c "
import json, sys
data = json.load(sys.stdin)
ingress = data.get('result',{}).get('config',{}).get('ingress',[])
print(json.dumps(ingress))
")
}

# Fetch current tunnel ingress from cache/API.
# Prints JSON array of ingress rules to stdout.
_tunnel_get_ingress() {
    tunnel_ingress_fetch || return 1
    printf '%s' "$_INGRESS_CACHE"
}

# Push a full ingress list to the Cloudflare API.
# Expects JSON array on stdin.
_tunnel_put_ingress() {
    local ingress_json="$1"
    local body
    body=$(printf '{"config":{"ingress":%s}}' "$ingress_json")
    local response
    response=$(cf_api "PUT" "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" "$body" 2>/dev/null) || return 1
    if ! cf_api_ok "$response"; then
        error "Failed to update tunnel config: $(cf_api_error "$response")"
        return 1
    fi
    printf '%s' "$response"
}

yaml_list_ingress() {
    local ingress
    ingress=$(_tunnel_get_ingress) || return 1
    printf '%s' "$ingress" | python3 -c "
import json, sys
rules = json.load(sys.stdin)
for r in rules:
    hostname = r.get('hostname', '(catch-all)')
    service = r.get('service', '?')
    print(f'{hostname}\t{service}')
"
}

yaml_has_hostname() {
    local hostname="$1"
    local ingress
    if ! tunnel_ingress_fetch; then
        echo "unknown"
        return 1
    fi
    ingress="$_INGRESS_CACHE"
    printf '%s' "$ingress" | python3 -c "
import json, sys
hostname = sys.argv[1]
rules = json.load(sys.stdin)
for r in rules:
    if r.get('hostname') == hostname:
        print('yes')
        sys.exit(0)
print('no')
" "$hostname"
}

yaml_add_ingress() {
    local hostname="$1"
    local service="$2"
    local ingress
    ingress=$(_tunnel_get_ingress) || return 1

    local new_ingress
    new_ingress=$(printf '%s' "$ingress" | python3 -c "
import json, sys
hostname = sys.argv[1]
service = sys.argv[2]
rules = json.load(sys.stdin)

# Check duplicate
for r in rules:
    if r.get('hostname') == hostname:
        print(f\"ERROR: hostname '{hostname}' already exists in ingress\", file=sys.stderr)
        sys.exit(1)

# Insert before catch-all (last rule)
new_rule = {'hostname': hostname, 'service': service}
if len(rules) > 0 and 'hostname' not in rules[-1]:
    rules.insert(-1, new_rule)
else:
    rules.append(new_rule)

print(json.dumps(rules))
" "$hostname" "$service") || return 1

    _tunnel_put_ingress "$new_ingress" >/dev/null || return 1
    echo "ok"
}

yaml_remove_ingress() {
    local hostname="$1"
    local ingress
    ingress=$(_tunnel_get_ingress) || return 1

    local new_ingress
    new_ingress=$(printf '%s' "$ingress" | python3 -c "
import json, sys
hostname = sys.argv[1]
rules = json.load(sys.stdin)
new_rules = [r for r in rules if r.get('hostname') != hostname]
if len(new_rules) == len(rules):
    print(f\"WARNING: hostname '{hostname}' not found in ingress\", file=sys.stderr)
print(json.dumps(new_rules))
" "$hostname") || return 1

    _tunnel_put_ingress "$new_ingress" >/dev/null || return 1
    echo "ok"
}

yaml_prune_ingress() {
    local prune_hosts="${1:-}"
    local ingress
    ingress=$(_tunnel_get_ingress) || return 1

    local new_ingress
    new_ingress=$(printf '%s' "$ingress" | python3 -c "
import json, sys
prune_hosts = set(x for x in sys.argv[1].split('\\n') if x)
rules = json.load(sys.stdin)
new_rules = [r for r in rules if r.get('hostname') not in prune_hosts]
print(json.dumps(new_rules))
" "$prune_hosts") || return 1

    _tunnel_put_ingress "$new_ingress" >/dev/null || return 1
    echo "ok"
}

yaml_validate() {
    local ingress
    ingress=$(_tunnel_get_ingress) || return 1
    printf '%s' "$ingress" | python3 -c "
import json, sys
rules = json.load(sys.stdin)
if not rules:
    print('ERROR: no ingress rules found', file=sys.stderr)
    sys.exit(1)
last = rules[-1]
if 'hostname' in last:
    print('ERROR: last ingress rule must be catch-all (no hostname)', file=sys.stderr)
    sys.exit(1)
if last.get('service') != 'http_status:404':
    print(f\"ERROR: catch-all service is '{last.get(\"service\")}', expected 'http_status:404'\", file=sys.stderr)
    sys.exit(1)
print(f'ok: {len(rules)} rules, catch-all valid')
"
}

###############################################################################
# Cloudflare API Operations
###############################################################################

CF_API_BASE="https://api.cloudflare.com/client/v4"

# _zone_id_cache is declared in _ferry_init() to avoid side effects when sourced
# declare -A _zone_id_cache

cf_api() {
    # Generic Cloudflare API call helper
    # Usage: cf_api GET "/zones" or cf_api POST "/zones/$zid/dns_records" '{"json":"body"}'
    local method="$1" path="$2" body="${3:-}"

    if [[ -z "$CF_API_TOKEN" ]]; then
        error "CF_API_TOKEN not set in $ENV_FILE"
        return 1
    fi

    local args=(
        -s -X "$method"
        --max-time 15
        -H "Authorization: Bearer ${CF_API_TOKEN}"
        -H "Content-Type: application/json"
    )

    if [[ -n "$body" ]]; then
        args+=(-d "$body")
    fi

    curl "${args[@]}" "${CF_API_BASE}${path}"
}

cf_api_ok() {
    # Check if a CF API JSON response has success=true
    local response="$1"
    [[ "$(echo "$response" | jq -r '.success')" == "true" ]]
}

cf_api_error() {
    # Extract first error message from a CF API response
    local response="$1"
    echo "$response" | jq -r '.errors[0].message // "unknown error"'
}

cf_resolve_zone_id() {
    # Given a hostname like "app.mydomain.com", resolve the zone_id via API.
    # Walks up the domain labels: tries "app.mydomain.com", then "mydomain.com".
    # Caches results in _zone_id_cache for the session.
    local hostname="$1"

    if [[ -z "$CF_API_TOKEN" ]]; then
        return 1
    fi

    # Walk up domain labels
    local domain="$hostname"
    while [[ "$domain" == *.* ]]; do
        # Check cache first
        if [[ -n "${_zone_id_cache[$domain]:-}" ]]; then
            echo "${_zone_id_cache[$domain]}"
            return 0
        fi

        local response
        response=$(cf_api GET "/zones?name=${domain}&status=active")

        if cf_api_ok "$response"; then
            local zone_id
            zone_id=$(echo "$response" | jq -r '.result[0].id // empty')
            if [[ -n "$zone_id" ]]; then
                _zone_id_cache[$domain]="$zone_id"
                echo "$zone_id"
                return 0
            fi
        fi

        # Strip leftmost label: app.mydomain.com -> mydomain.com
        domain="${domain#*.}"
    done

    error "Could not find Cloudflare zone for '$hostname'"
    return 1
}

cf_dns_create_cname() {
    # Create a proxied CNAME record pointing hostname to the tunnel
    local hostname="$1"
    local tunnel_target="${TUNNEL_ID}.cfargotunnel.com"

    local zone_id
    zone_id=$(cf_resolve_zone_id "$hostname") || return 1

    local body
    body=$(jq -n \
        --arg name "$hostname" \
        --arg content "$tunnel_target" \
        '{type: "CNAME", name: $name, content: $content, proxied: true, ttl: 1}')

    local response
    response=$(cf_api POST "/zones/${zone_id}/dns_records" "$body")

    if cf_api_ok "$response"; then
        return 0
    else
        local msg
        msg=$(cf_api_error "$response")
        # "Record already exists" is not an error for us
        if [[ "$msg" == *"already exists"* ]]; then
            return 0
        fi
        error "Failed to create DNS record for '$hostname': $msg"
        return 1
    fi
}

cf_dns_delete_record() {
    # Delete a DNS record by hostname (finds record ID first)
    local hostname="$1"

    local zone_id
    zone_id=$(cf_resolve_zone_id "$hostname") || return 1

    local response
    response=$(cf_api GET "/zones/${zone_id}/dns_records?type=CNAME&name=${hostname}")

    if ! cf_api_ok "$response"; then
        error "Failed to query DNS records: $(cf_api_error "$response")"
        return 1
    fi

    local record_id
    record_id=$(echo "$response" | jq -r '.result[0].id // empty')

    if [[ -z "$record_id" ]]; then
        warn "DNS record for '$hostname' not found (may already be deleted)"
        return 0
    fi

    local del_response
    del_response=$(cf_api DELETE "/zones/${zone_id}/dns_records/${record_id}")

    if cf_api_ok "$del_response"; then
        return 0
    else
        error "Failed to delete DNS record: $(cf_api_error "$del_response")"
        return 1
    fi
}

cf_dns_list_records() {
    # List DNS records for a zone (resolved from hostname)
    local hostname="$1"
    local record_type="${2:-}"  # optional: CNAME, A, etc.

    local zone_id
    zone_id=$(cf_resolve_zone_id "$hostname") || return 1

    local query="/zones/${zone_id}/dns_records?name=${hostname}"
    if [[ -n "$record_type" ]]; then
        query+="&type=${record_type}"
    fi

    cf_api GET "$query"
}

###############################################################################
# DNS Operations
###############################################################################

dns_create_cname() {
    local hostname="$1"

    # Prefer API method (works across all zones, no cert.pem needed)
    if [[ -n "$CF_API_TOKEN" ]]; then
        if cf_dns_create_cname "$hostname"; then
            echo "Added CNAME $hostname via API"
            return 0
        fi
        warn "API method failed, falling back to cloudflared..."
    fi

    # Fallback: zone-scoped cert via cloudflared tunnel route dns
    local _cert_result
    _cert_result=$(cert_find_for_hostname "$hostname") || true
    if [[ -z "$_cert_result" ]]; then
        error "No CF_API_TOKEN and no zone cert found for '$hostname'"
        error "Run ferry login to set up API access"
        return 1
    fi
    local _cert_path="${_cert_result%% *}"
    local _cert_zone="${_cert_result#* }"
    warn "Using zone cert fallback (${_cert_zone} subdomains only)"
    docker compose -f "$COMPOSE_FILE" run --rm -T \
        -v "${_cert_path}:/tmp/cert.pem:ro" \
        cloudflared --origincert /tmp/cert.pem \
        tunnel route dns \
        "$TUNNEL_ID" "$hostname" 2>&1
}

dns_delete_record() {
    local hostname="$1"

    if [[ -z "$CF_API_TOKEN" ]]; then
        error "CF_API_TOKEN required for DNS record deletion"
        return 1
    fi

    cf_dns_delete_record "$hostname"
}

dns_check() {
    local hostname="$1"
    dig +short "$hostname" 2>/dev/null | head -1
}

# Print each host nameserver, one per line. Uses systemd-resolved's
# authoritative D-Bus / CLI surface (`resolvectl dns`) rather than parsing
# /etc/resolv.conf — on systems where NetworkManager wrote that file directly
# (`resolv.conf mode: foreign`) it's a compatibility stub, not the source of
# truth. Falls back to the resolved-owned flat file, then to libc's
# /etc/resolv.conf only on hosts without systemd-resolved.
_detect_host_resolvers() {
    if command -v resolvectl >/dev/null 2>&1; then
        # `resolvectl dns` output is one line per link:
        #   Global: 192.168.1.1
        #   Link 2 (eth0): 192.168.1.1 fe80::1
        #   Link 3 (tailscale0):
        resolvectl dns 2>/dev/null \
            | awk -F': ' 'NF >= 2 && $2 != "" {
                n = split($2, a, /[[:space:]]+/);
                for (i = 1; i <= n; i++) if (a[i] != "") print a[i]
              }' \
            | awk 'NF && !seen[$0]++'
        return
    fi
    local src="/run/systemd/resolve/resolv.conf"
    [[ -r "$src" ]] || src="/etc/resolv.conf"
    awk '/^nameserver[[:space:]]/ {print $2}' "$src" 2>/dev/null \
        | awk 'NF && !seen[$0]++'
}

# Probe a resolver from the host. Returns 0 if it answers a real query.
_probe_resolver() {
    local ns="$1"
    [[ -n "$ns" ]] || return 1
    dig +short +time=2 +tries=1 "@$ns" cloudflare.com 2>/dev/null \
        | grep -qE '^[0-9]'
}

# Probe DNS from inside the Docker network Ferry's services use. Spins up an
# ephemeral busybox on the `webserver` network and resolves a real Cloudflare
# hostname — the exact failure mode that takes cloudflared offline if broken.
_probe_container_dns() {
    docker run --rm --network webserver busybox:latest \
        nslookup argotunnel.com >/dev/null 2>&1
}

###############################################################################
# Cloudflared Operations
###############################################################################

cloudflared_restart() {
    info "Restarting cloudflared..."
    # Use 'up -d' instead of 'restart' — restart cannot recover a container
    # that failed to create (e.g. exit 127 from a stale bind-mount on reboot).
    # 'up -d --force-recreate' rebuilds the container from the compose definition.
    docker compose -f "$COMPOSE_FILE" up -d --force-recreate cloudflared 2>&1

    local attempts=0
    local max_attempts=5
    while ((attempts < max_attempts)); do
        sleep 3
        local state
        state=$(docker compose -f "$COMPOSE_FILE" ps --format '{{.State}}' cloudflared 2>/dev/null || true)
        if [[ "$state" != "running" ]]; then
            ((attempts++)) || true
            continue
        fi
        # Check for at least one tunnel connection
        local conns
        conns=$(docker compose -f "$COMPOSE_FILE" logs --tail=10 cloudflared 2>&1 | \
            grep -c "Registered tunnel connection" || true)
        if ((conns > 0)); then
            success "cloudflared restarted (${conns} connection(s) registered)"
            return 0
        fi
        ((attempts++)) || true
    done

    error "cloudflared did not register tunnel connections within timeout"
    return 1
}

cloudflared_tunnel_status() {
    # Check recent logs for connection info
    docker compose -f "$COMPOSE_FILE" logs --tail=50 cloudflared 2>&1 | \
        grep -c "Registered tunnel connection" || echo "0"
}

###############################################################################
# Dokku Operations
###############################################################################

dokku_app_exists() {
    local name="$1"
    dokku_cmd apps:exists "$name" &>/dev/null
}

dokku_list_apps() {
    local output
    output=$(dokku_cmd apps:list 2>/dev/null) || {
        warn "Failed to list Dokku apps"
        return 1
    }
    # Drop Dokku banner lines: "=====>" (info), "----->" (step),
    # and " ! ..." (warning — e.g. "You haven't deployed any applications yet").
    # Dokku app names cannot start with these characters, so this filter is safe.
    printf '%s\n' "$output" | awk '/^[[:space:]]*[-=!]/ { next } NF'
}

dokku_app_domains_all() {
    local name="$1"
    local output
    output=$(dokku_cmd domains:report "$name" 2>/dev/null) || return 1
    printf '%s\n' "$output" | awk -F':' '
        /Domains app vhosts:|Domains global vhosts:/ {
            value = $2
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            if (value == "" || value == "disabled") {
                next
            }
            gsub(/,/, " ", value)
            count = split(value, items, /[[:space:]]+/)
            for (i = 1; i <= count; i++) {
                if (items[i] != "") {
                    print items[i]
                }
            }
        }
    ' | awk '!seen[$0]++'
}

dokku_app_domains() {
    local name="$1"
    dokku_app_domains_all "$name" | head -1
}

dokku_list_all_domains() {
    local apps domains=""
    apps=$(dokku_list_apps 2>/dev/null) || return 1

    local app app_domains
    while IFS= read -r app; do
        [[ -z "$app" ]] && continue
        app_domains=$(dokku_app_domains_all "$app") || return 1
        [[ -n "$app_domains" ]] && domains+="${app_domains}"$'\n'
    done <<< "$apps"

    printf '%s' "$domains" | awk 'NF && !seen[$0]++'
}

dokku_app_ports() {
    local name="$1"
    dokku_cmd ports:report "$name" 2>/dev/null | \
        grep "Ports map:" | head -1 | sed 's/.*Ports map:\s*//' | xargs
}

dokku_app_status() {
    local name="$1"
    local ps_output
    ps_output=$(dokku_cmd ps:report "$name" 2>/dev/null || true)
    if echo "$ps_output" | grep -q "Running:.*true"; then
        echo "running"
    elif echo "$ps_output" | grep -q "Deployed:.*false"; then
        echo "not deployed"
    else
        echo "stopped"
    fi
}

###############################################################################
# Resource / Runtime Helpers (used by deploy + tune)
###############################################################################

# Calculate a safe V8 --max-old-space-size for a container memory limit.
# Leaves ~48 MiB headroom for V8 internals, code, buffers; floors at 64 MiB.
ferry_calc_node_heap() {
    local mem="${1:-0}"
    local heap=$((mem - 48))
    ((heap < 64)) && heap=64
    echo "$heap"
}

# Detect runtime from project files in an app source directory.
# Echoes: node | python | go | rust | ruby | static | ""
ferry_detect_runtime_from_dir() {
    local dir="${1:-}"
    [[ -d "$dir" ]] || { echo ""; return 0; }
    if [[ -f "$dir/package.json" ]]; then echo "node"; return 0; fi
    if [[ -f "$dir/pyproject.toml" || -f "$dir/requirements.txt" || -f "$dir/Pipfile" ]]; then echo "python"; return 0; fi
    if [[ -f "$dir/go.mod" ]]; then echo "go"; return 0; fi
    if [[ -f "$dir/Cargo.toml" ]]; then echo "rust"; return 0; fi
    if [[ -f "$dir/Gemfile" ]]; then echo "ruby"; return 0; fi
    echo ""
}

# Read the FERRY_RUNTIME Dokku config var for an app.
# Returns 0 even when the key is unset (dokku config:get exits non-zero in that case).
ferry_app_runtime() {
    local name="$1"
    local val=""
    val=$(dokku_cmd config:get "$name" FERRY_RUNTIME 2>/dev/null || true)
    printf '%s' "${val//[$'\r\n']/}"
}

# Parse current memory limit (MB) from `dokku resource:report`.
ferry_app_memory_limit() {
    local name="$1"
    local out=""
    out=$(dokku_cmd resource:report "$name" 2>/dev/null || true)
    printf '%s' "$out" \
        | awk '/_default_ limit memory:/ { gsub(/[^0-9]/, "", $NF); print $NF; exit }'
}

# Read current NODE_OPTIONS dokku config for an app.
ferry_app_node_options() {
    local name="$1"
    local val=""
    val=$(dokku_cmd config:get "$name" NODE_OPTIONS 2>/dev/null || true)
    printf '%s' "${val//[$'\r\n']/}"
}

###############################################################################
# Git & Deploy Helpers
###############################################################################

detect_app_port() {
    # Detect the app port from project files.
    # Prints "PORT SOURCE_DESCRIPTION" on stdout. Returns 1 if nothing detected.
    # Priority: Dockerfile EXPOSE > package.json framework > scripts.start > Procfile
    local dir="$1"

    # 1. Dockerfile EXPOSE
    if [[ -f "$dir/Dockerfile" ]]; then
        local dport
        dport=$(grep -i '^[[:space:]]*EXPOSE[[:space:]]' "$dir/Dockerfile" 2>/dev/null \
            | head -1 | awk '{print $2}' | grep -oE '^[0-9]+') || true
        if [[ -n "$dport" ]]; then
            echo "$dport Dockerfile EXPOSE"
            return 0
        fi
    fi

    # 2. package.json — framework detection
    if [[ -f "$dir/package.json" ]] && command -v jq &>/dev/null; then
        local deps
        deps=$(jq -r '(.dependencies // {}) + (.devDependencies // {}) | keys[]' \
            "$dir/package.json" 2>/dev/null) || true

        local fw
        for fw in next nuxt remix fastify express; do
            if echo "$deps" | grep -qx "$fw"; then
                echo "3000 ${fw} (package.json)"
                return 0
            fi
        done

        # 3. package.json scripts.start — port flags
        local start_script
        start_script=$(jq -r '.scripts.start // empty' "$dir/package.json" 2>/dev/null) || true
        if [[ -n "$start_script" ]]; then
            local sport
            sport=$(echo "$start_script" \
                | grep -oE '\-\-port[[:space:]]+[0-9]+|\-p[[:space:]]+[0-9]+' \
                | head -1 | grep -oE '[0-9]+') || true
            if [[ -n "$sport" ]]; then
                echo "$sport start script (--port)"
                return 0
            fi
            sport=$(echo "$start_script" | grep -oE 'PORT=[0-9]+' \
                | head -1 | grep -oE '[0-9]+') || true
            if [[ -n "$sport" ]]; then
                echo "$sport start script (PORT=)"
                return 0
            fi
        fi
    fi

    # 4. Procfile
    if [[ -f "$dir/Procfile" ]]; then
        local pport
        pport=$(grep -oE '\-\-port[[:space:]]+[0-9]+|\-p[[:space:]]+[0-9]+' \
            "$dir/Procfile" 2>/dev/null | head -1 | grep -oE '[0-9]+') || true
        if [[ -n "$pport" ]]; then
            echo "$pport Procfile (--port)"
            return 0
        fi
    fi

    # 5. No detection
    return 1
}

repo_clone() {
    # Clone a GitHub repo. Args: $1=repo slug or URL, $2=target directory.
    # Returns 0 on success or if already cloned. Returns 1 on failure.
    local input="$1" target_dir="$2"

    # Normalize: strip https://github.com/ prefix and .git suffix
    local slug="$input"
    slug="${slug#https://github.com/}"
    slug="${slug#http://github.com/}"
    slug="${slug#github.com/}"
    slug="${slug%.git}"

    # Validate format: owner/repo
    if ! [[ "$slug" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
        error "Invalid repo format '$slug'. Expected: owner/repo"
        return 1
    fi

    # Skip if already cloned
    if [[ -d "$target_dir/.git" ]]; then
        info "Repository already cloned at $target_dir"
        return 0
    fi

    # Clone (full history — Dokku needs it for buildpack detection)
    if ! command -v gh &>/dev/null; then
        error "gh (GitHub CLI) is required for cloning. Install: https://cli.github.com"
        return 1
    fi

    gh repo clone "$slug" "$target_dir"
}

dokku_push() {
    # Push app to Dokku. Args: $1=app dir, $2=app name, $3=branch (optional).
    # Returns exit code from git push.
    local dir="$1" name="$2" push_branch="${3:-}"

    # Auto-detect branch if not specified
    if [[ -z "$push_branch" ]]; then
        push_branch=$(git -C "$dir" branch --show-current 2>/dev/null) || true
        if [[ -z "$push_branch" ]]; then
            push_branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null) || true
        fi
        if [[ -z "$push_branch" ]] || [[ "$push_branch" == "HEAD" ]]; then
            error "Cannot detect branch (detached HEAD?). Use --branch to specify."
            return 1
        fi
    fi

    local remote_url="ssh://dokku@localhost:3022/$name"

    # Add or update dokku remote
    if git -C "$dir" remote get-url dokku &>/dev/null; then
        git -C "$dir" remote set-url dokku "$remote_url"
    else
        git -C "$dir" remote add dokku "$remote_url"
    fi

    info "Pushing $push_branch → dokku:master..."
    git -C "$dir" push dokku "$push_branch:master"
}

post_deploy_verify() {
    # Verify the app is live. Args: $1=hostname, $2=app name.
    # Retries 5 times with 3s delay. Returns 0 on 2xx/3xx, 1 on failure.
    local hostname="$1" name="$2"
    local attempts=0 max_attempts=5

    while ((attempts < max_attempts)); do
        local http_code
        http_code=$(curl -sI --max-time 10 "https://$hostname" 2>/dev/null \
            | head -1 | awk '{print $2}') || true
        if [[ -n "$http_code" ]] && [[ "$http_code" =~ ^[23][0-9][0-9]$ ]]; then
            success "App is live at https://$hostname (HTTP $http_code)"
            return 0
        fi
        ((attempts++)) || true
        if ((attempts < max_attempts)); then
            info "Waiting for app to come online... (attempt $attempts/$max_attempts)"
            sleep 3
        fi
    done

    warn "App not responding at https://$hostname after $max_attempts attempts"
    warn "This is normal if the app is still building."
    dim "    Check build progress: ferry logs $name"
    return 1
}

###############################################################################
# Command: status
###############################################################################

cmd_status() {
    preflight

    section_header "System Status"

    # --- Infrastructure ---
    section_header "Infrastructure"
    echo ""

    # Docker Compose services
    local cf_status dokku_status
    cf_status=$(docker compose -f "$COMPOSE_FILE" ps --format '{{.Name}} ({{.Status}})' cloudflared 2>/dev/null || echo "unknown")
    dokku_status=$(docker compose -f "$COMPOSE_FILE" ps --format '{{.Name}} ({{.Status}})' dokku 2>/dev/null || echo "unknown")
    kv "Docker Compose" "$cf_status | $dokku_status"

    # Tunnel connections
    local conn_count
    conn_count=$(docker compose -f "$COMPOSE_FILE" logs --tail=100 cloudflared 2>&1 | \
        grep -c "Registered tunnel connection" || true)
    if ((conn_count >= 4)); then
        kv_color "Cloudflare Tunnel" "Connected ($conn_count connections)" "$C_SUCCESS"
    elif ((conn_count > 0)); then
        kv_color "Cloudflare Tunnel" "Partial ($conn_count connections)" "$C_WARN"
    else
        kv_color "Cloudflare Tunnel" "Unknown (no connection logs)" "$C_ERROR"
    fi

    # DNS (adaptive — auto-detects host resolvers, probes container path)
    local -a host_resolvers
    mapfile -t host_resolvers < <(_detect_host_resolvers)

    local host_dns_str=""
    if ((${#host_resolvers[@]} == 0)); then
        host_dns_str="${C_ERROR}none detected${C_RESET}"
    else
        for ns in "${host_resolvers[@]}"; do
            if _probe_resolver "$ns"; then
                host_dns_str+="${C_SUCCESS}${ns} ✓${C_RESET}  "
            else
                host_dns_str+="${C_ERROR}${ns} ✗${C_RESET}  "
            fi
        done
    fi
    printf '    %b%-18s%b ' "$C_DIM" "Host DNS" "$C_RESET"
    echo -e "$host_dns_str"

    if _probe_container_dns; then
        printf '    %b%-18s%b ' "$C_DIM" "Container DNS" "$C_RESET"
        echo -e "${C_SUCCESS}✓ argotunnel.com resolves from webserver net${C_RESET}"
    else
        printf '    %b%-18s%b ' "$C_DIM" "Container DNS" "$C_RESET"
        echo -e "${C_ERROR}✗ DNS broken inside webserver net${C_RESET}"
    fi

    # API token status
    if [[ -n "$CF_API_TOKEN" ]]; then
        if cf_token_verify; then
            kv_color "Cloudflare API" "Authenticated" "$C_SUCCESS"
            local zones_resp zone_names
            zones_resp=$(cf_api GET "/zones?per_page=50" 2>/dev/null) || true
            if cf_api_ok "$zones_resp" 2>/dev/null; then
                zone_names=$(echo "$zones_resp" | jq -r '[.result[].name] | join(", ")')
                kv "Zones" "$zone_names"
            fi
        else
            printf '    %b%-18s%b ' "$C_DIM" "Cloudflare API" "$C_RESET"
            echo -e "${C_ERROR}Token ${_cf_token_status}${C_RESET} ${C_DIM}— run${C_RESET} ${C_ACCENT}ferry login${C_RESET}"
        fi
    else
        printf '    %b%-18s%b ' "$C_DIM" "Cloudflare API" "$C_RESET"
        echo -e "${C_WARN}Not configured${C_RESET} ${C_DIM}— run${C_RESET} ${C_ACCENT}ferry login${C_RESET}"
    fi

    # --- Apps ---
    section_header "Apps"
    echo ""

    local apps
    apps=$(dokku_list_apps) || true
    if [[ -z "$apps" ]]; then
        dim "(no apps)"
    else
        printf "    ${C_DIM}%-14s %-30s %-14s %-14s %-5s %s${C_RESET}\n" "NAME" "DOMAIN" "PORTS" "STATUS" "DNS" "LIVE"
        # Table divider removed for compact/mobile TUI rendering.
        # printf "    ${C_CHROME}%s${C_RESET}\n" "$(_divider_line 85)"

        while IFS= read -r app; do
            local domain ports status dns_result dns_icon status_icon
            domain=$(dokku_app_domains "$app")
            ports=$(dokku_app_ports "$app")
            status=$(app_effective_status "$app" "$domain")
            dns_result=$(dns_check "$domain" 2>/dev/null || true)
            if [[ -n "$dns_result" ]]; then
                dns_icon="${C_SUCCESS}✓${C_RESET}"
            else
                dns_icon="${C_ERROR}✗${C_RESET}"
            fi

            case "$status" in
                running)        status_icon="${C_SUCCESS}●${C_RESET}" ;;
                unroutable)     status_icon="${C_WARN}○${C_RESET}" ;;
                "not deployed") status_icon="${C_WARN}○${C_RESET}" ;;
                *)              status_icon="${C_ERROR}○${C_RESET}" ;;
            esac

            # Live end-to-end HTTP check through the public domain
            local live_result live_color
            if [[ -n "$domain" && "$status" == "running" ]]; then
                local http_code
                http_code=$(curl -so /dev/null -w '%{http_code}' --max-time 5 \
                    "https://${domain}" 2>/dev/null) || http_code="000"
                if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
                    live_result="[${http_code}] OK"
                    live_color="$C_SUCCESS"
                elif [[ "$http_code" == "000" ]]; then
                    live_result="[timeout]"
                    live_color="$C_ERROR"
                elif [[ "$http_code" =~ ^3[0-9][0-9]$ ]]; then
                    live_result="[${http_code}]"
                    live_color="$C_WARN"
                else
                    live_result="[${http_code}] FAIL"
                    live_color="$C_ERROR"
                fi
            else
                live_result="—"
                live_color="$C_DIM"
            fi

            printf "    %-14s %-30s %-14s " "$app" "$domain" "$ports"
            echo -e "${status_icon} ${status}     ${dns_icon}  ${live_color}${live_result}${C_RESET}"
        done <<< "$apps"
    fi

    # --- Ingress Rules ---
    section_header "Ingress Rules"
    echo ""

    local ingress_available=true
    tunnel_ingress_reset_cache
    if ! tunnel_ingress_fetch; then
        ingress_available=false
        warn "Cannot read tunnel ingress: ${_INGRESS_CACHE_ERROR:-unknown error}"
        dim "    Fix Account → Cloudflare Tunnel → Edit on your API token, then re-run: ferry login"
    fi

    local i=1
    while IFS=$'\t' read -r hostname service; do
        if [[ "$hostname" == "(catch-all)" ]]; then
            echo -e "    ${C_DIM}${i}. (catch-all)            →  ${service}${C_RESET}"
        else
            printf "    %d. %-24s ${C_CHROME}→${C_RESET}  %s\n" "$i" "$hostname" "$service"
        fi
        ((i++))
    done < <(yaml_list_ingress)

    # --- Cross-validation ---
    echo ""
    local warnings=0
    if ! $ingress_available; then
        warn "Skipping ingress cross-validation (tunnel config unavailable)"
        echo ""
        return 0
    fi
    local all_domains=""
    all_domains=$(dokku_list_all_domains 2>/dev/null) || true

    while IFS= read -r app; do
        local matched=0
        while IFS= read -r domain; do
            [[ -z "$domain" ]] && continue
            local has
            has=$(yaml_has_hostname "$domain")
            if [[ "$has" == "yes" ]]; then
                matched=1
                break
            fi
        done < <(dokku_app_domains_all "$app")

        if ((matched == 0)); then
            local domain
            domain=$(dokku_app_domains "$app")
            if [[ -n "$domain" ]]; then
                warn "App '${app}' (${domain}) has no matching ingress rule"
            else
                warn "App '${app}' has no matching ingress rule"
            fi
            ((warnings++)) || true
        fi
    done <<< "$apps"

    while IFS=$'\t' read -r hostname service; do
        if [[ "$hostname" == "(catch-all)" ]]; then
            continue
        fi
        if ! grep -Fxq "$hostname" <<< "$all_domains"; then
            warn "Ingress rule '${hostname}' has no matching Dokku app (run: ferry prune reconcile)"
            ((warnings++)) || true
        fi
    done < <(yaml_list_ingress)

    if ((warnings == 0)); then
        success "All apps and ingress rules are in sync"
    fi

    echo ""
}


###############################################################################
# Command: list
###############################################################################

cmd_list() {
    preflight

    local apps
    apps=$(dokku_list_apps) || true
    if [[ -z "$apps" ]]; then
        info "No apps found."
        return
    fi

    section_header "Apps"
    echo ""
    printf "    ${C_DIM}%-14s %-30s %-14s %-14s${C_RESET}\n" "NAME" "DOMAIN" "PORTS" "STATUS"
    # Table divider removed for compact/mobile TUI rendering.
    # printf "    ${C_CHROME}%s${C_RESET}\n" "$(_divider_line 70)"
    while IFS= read -r app; do
        local domain ports status status_icon
        domain=$(dokku_app_domains "$app")
        ports=$(dokku_app_ports "$app")
        status=$(app_effective_status "$app" "$domain")
        case "$status" in
            running)        status_icon="${C_SUCCESS}●${C_RESET}" ;;
            unroutable)     status_icon="${C_WARN}○${C_RESET}" ;;
            "not deployed") status_icon="${C_WARN}○${C_RESET}" ;;
            *)              status_icon="${C_ERROR}○${C_RESET}" ;;
        esac
        printf "    %-14s %-30s %-14s " "$app" "$domain" "$ports"
        echo -e "${status_icon} ${status}"
    done <<< "$apps"
    echo ""
}

###############################################################################
# Command: deploy
###############################################################################

cmd_deploy() {
    preflight

    local name="" hostname="" port="" repo="" branch="" app_dir="" no_push=false
    local has_app_source=false port_explicit=false
    local memory=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -H|--hostname) hostname="$2"; shift 2 ;;
            -p|--port)     port="$2"; port_explicit=true; shift 2 ;;
            -m|--memory)   memory="$2"; shift 2 ;;
            -r|--repo)     repo="$2"; shift 2 ;;
            -b|--branch)   branch="$2"; shift 2 ;;
            -d|--dir)      app_dir="$2"; shift 2 ;;
            --no-push)     no_push=true; shift ;;
            -y|--yes)      YES=true; shift ;;
            -*)            error "Unknown flag: $1"; return 1 ;;
            *)             name="$1"; shift ;;
        esac
    done

    if [[ -z "$name" ]] && $YES; then
        error "App name required when using -y/--yes."
        return 1
    fi

    section_header "Deploy Application"
    echo ""

    # App name (prompt if not given)
    if [[ -z "$name" ]]; then
        tui_read name "App name (a-z, 0-9, hyphens)" "" false || {
            case $? in
                2) return 0 ;;
                3) return 3 ;;
                *) return 1 ;;
            esac
        }
    fi

    # Validate name
    if ! [[ "$name" =~ ^[a-z][a-z0-9-]{0,28}[a-z0-9]$ ]]; then
        error "Invalid name '$name'. Use 2-30 chars: lowercase letters, numbers, hyphens. Must start with a letter, cannot end with a hyphen."
        return 1
    fi

    if dokku_app_exists "$name"; then
        error "App '$name' already exists in Dokku."
        return 1
    fi

    if sync_missing_ingress_from_dokku >/dev/null; then
        :
    else
        local restored_rc=$?
        case "$restored_rc" in
            2) return 0 ;;
            3) return 3 ;;
            *) error "Failed to verify existing ingress before deploy."; return 1 ;;
        esac
    fi

    # --- Resolve app source ---
    if [[ -n "$app_dir" ]]; then
        # --dir given: validate
        if [[ ! -d "$app_dir" ]]; then
            error "Directory '$app_dir' does not exist."
            return 1
        fi
        if [[ ! -d "$app_dir/.git" ]]; then
            error "Directory '$app_dir' is not a git repository."
            return 1
        fi
        has_app_source=true
    elif [[ -n "$repo" ]]; then
        # --repo given: will clone to $FERRY_APPS_DIR/<name>
        app_dir="$FERRY_APPS_DIR/$name"
        has_app_source=true
    elif [[ -d "$FERRY_APPS_DIR/$name/.git" ]]; then
        # Auto-detect: existing clone in $FERRY_APPS_DIR/<name>
        app_dir="$FERRY_APPS_DIR/$name"
        has_app_source=true
        info "Found existing app source at $app_dir"
    elif ! $YES; then
        # Interactive: offer to clone
        local clone_choice=0
        if confirm "Clone app from GitHub?"; then
            clone_choice=0
        else
            clone_choice=$?
        fi
        case "$clone_choice" in
            0)
                tui_read repo "GitHub repo (owner/repo)" "" false || {
                    case $? in
                        2) return 0 ;;
                        3) return 3 ;;
                        *) return 1 ;;
                    esac
                }
                if [[ -n "$repo" ]]; then
                    app_dir="$FERRY_APPS_DIR/$name"
                    has_app_source=true
                fi
                ;;
            2) ;;
            3) return 3 ;;
        esac
    fi

    # --- Port auto-detection (only if dir already exists and port not explicit) ---
    local detected_port="" detected_source=""
    if ! $port_explicit && $has_app_source && [[ -d "$app_dir" ]]; then
        local detect_result
        detect_result=$(detect_app_port "$app_dir") || true
        if [[ -n "$detect_result" ]]; then
            detected_port="${detect_result%% *}"
            detected_source="${detect_result#* }"
        fi
    fi

    # --- Hostname ---
    if [[ -z "$hostname" ]]; then
        if [[ -z "$DOKKU_HOSTNAME" ]]; then
            if $YES; then
                DOKKU_HOSTNAME="apps.local"
            else
                box "${C_WARN}DOKKU_HOSTNAME is not set${C_RESET}" \
                    "" \
                    "  Set it in ${C_ACCENT}.env${C_RESET} or enter a default domain now."
                echo ""
                tui_read DOKKU_HOSTNAME "Default domain (e.g. example.com)" "apps.local" false || {
                    case $? in
                        2) return 0 ;;
                        3) return 3 ;;
                        *) return 1 ;;
                    esac
                }
                DOKKU_HOSTNAME="${DOKKU_HOSTNAME:-apps.local}"
            fi
        fi
        local default_host="${name}.${DOKKU_HOSTNAME}"
        if $YES; then
            hostname="$default_host"
        else
            tui_read hostname "Hostname" "$default_host" false || {
                case $? in
                    2) return 0 ;;
                    3) return 3 ;;
                    *) return 1 ;;
                esac
            }
            hostname="${hostname:-$default_host}"
        fi
    fi

    # Check if hostname already in ingress
    local has_ingress
    has_ingress=$(yaml_has_hostname "$hostname")
    if [[ "$has_ingress" == "yes" ]]; then
        error "Hostname '$hostname' already has an ingress rule."
        return 1
    fi

    # --- Port resolution ---
    local port_deferred=false
    if ! $port_explicit; then
        if [[ -n "$detected_port" ]]; then
            # Port was detected from existing directory
            if $YES; then
                port="$detected_port"
                info "Auto-detected port $port ($detected_source)"
            else
                echo -e "  ${C_INFO}·${C_RESET} Detected port ${C_BOLD}${C_WHITE}$detected_port${C_RESET} ($detected_source)"
                local port_choice=0
                if confirm "Use detected port $detected_port?"; then
                    port_choice=0
                else
                    port_choice=$?
                fi
                case "$port_choice" in
                    0)
                        port="$detected_port"
                        ;;
                    2)
                        tui_read port "App port" "5000" false || {
                            case $? in
                                2) return 0 ;;
                                3) return 3 ;;
                                *) return 1 ;;
                            esac
                        }
                        port="${port:-5000}"
                        ;;
                    3) return 3 ;;
                esac
            fi
        elif $has_app_source && [[ ! -d "$app_dir" ]]; then
            # Will clone — defer port detection
            port_deferred=true
        elif $YES; then
            port=5000
        else
            tui_read port "App port" "5000" false || {
                case $? in
                    2) return 0 ;;
                    3) return 3 ;;
                    *) return 1 ;;
                esac
            }
            port="${port:-5000}"
        fi
    fi

    # Validate port (skip if deferred)
    if ! $port_deferred; then
        if ! [[ "$port" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
            error "Invalid port '$port'. Must be between 1 and 65535."
            return 1
        fi
    fi

    # --- Runtime detection (from app_dir if present) ---
    local runtime=""
    if $has_app_source && [[ -d "$app_dir" ]]; then
        runtime=$(ferry_detect_runtime_from_dir "$app_dir")
    fi

    # --- Memory ---
    if [[ -z "$memory" ]]; then
        if $YES; then
            memory=256
        else
            local mem_hint=""
            [[ "$runtime" == "node" ]] && mem_hint=" (512+ recommended for Node)"
            tui_read memory "Container memory limit in MB${mem_hint}" "256" false || {
                case $? in
                    2) return 0 ;;
                    3) return 3 ;;
                    *) return 1 ;;
                esac
            }
            memory="${memory:-256}"
        fi
    fi

    if ! [[ "$memory" =~ ^[0-9]+$ ]] || ((memory < 64)); then
        error "Invalid memory '$memory'. Must be integer ≥ 64."
        return 1
    fi
    # Root domain check
    local is_root=false
    local dot_count
    dot_count=$(echo "$hostname" | tr -cd '.' | wc -c)
    if ((dot_count == 1)); then
        is_root=true
    fi

    # --- Compute adaptive steps ---
    local do_clone=false do_push=false
    if [[ -n "$repo" ]] && [[ ! -d "$app_dir/.git" ]]; then
        do_clone=true
    fi
    if $has_app_source && ! $no_push; then
        do_push=true
    fi

    local total_steps=5  # base: dokku, dns, ingress, cloudflared, verify
    if $do_clone; then ((total_steps++)) || true; fi
    if $do_push; then ((total_steps++)) || true; fi

    local n=1
    local step_clone="" step_dokku="" step_dns="" step_ingress="" step_cf="" step_push="" step_verify=""
    if $do_clone; then step_clone="$n"; ((n++)) || true; fi
    step_dokku="$n"; ((n++)) || true
    step_dns="$n"; ((n++)) || true
    step_ingress="$n"; ((n++)) || true
    step_cf="$n"; ((n++)) || true
    if $do_push; then step_push="$n"; ((n++)) || true; fi
    step_verify="$n"

    # --- Summary ---
    section_header "Deploy Plan"
    echo ""
    kv "App name" "$name"
    kv "Hostname" "$hostname"
    if $port_deferred; then
        kv_color "Port" "(auto-detect after clone)" "$C_DIM"
    else
        kv "Port" "$port"
        kv "Port map" "http:80:$port"
    fi
    kv "Memory" "${memory} MB"
    if [[ -n "$runtime" ]]; then
        kv "Runtime" "$runtime"
    fi
    if [[ -n "$repo" ]]; then
        kv "Repo" "$repo"
    fi
    if [[ -n "$app_dir" ]]; then
        kv "App dir" "$app_dir"
    fi
    if [[ -n "$branch" ]]; then
        kv "Branch" "$branch"
    fi
    if $is_root; then
        echo -e "    ${C_WARN}Root domain detected${C_RESET}"
        if [[ -n "$CF_API_TOKEN" ]]; then
            dim "    Will create www → root redirect"
        else
            dim "    www redirect requires CF_API_TOKEN"
        fi
    fi
    echo ""
    dim "  Steps:"
    if $do_clone; then
        dim "    ${step_clone}. Clone repo from GitHub"
    fi
    dim "    ${step_dokku}. Create Dokku app + configure"
    dim "    ${step_dns}. Create DNS CNAME"
    dim "    ${step_ingress}. Add ingress rule"
    dim "    ${step_cf}. Restart cloudflared"
    if $do_push; then
        dim "    ${step_push}. Push app to Dokku"
    fi
    dim "    ${step_verify}. Verify setup"
    echo ""

    local deploy_choice=0
    if confirm "Proceed with deploy?"; then
        deploy_choice=0
    else
        deploy_choice=$?
    fi
    case "$deploy_choice" in
        0) ;;
        2) info "Cancelled."; return 0 ;;
        3) return 3 ;;
        *) info "Cancelled."; return 0 ;;
    esac

    echo ""
    local failed=0

    # Pre-check: verify DNS method is available
    if [[ -z "$CF_API_TOKEN" ]] || ! cf_token_verify 2>/dev/null; then
        local _cert_result
        _cert_result=$(cert_find_for_hostname "$hostname") || true
        if [[ -n "$_cert_result" ]]; then
            local _cert_zone="${_cert_result#* }"
            warn "No API token — using zone cert fallback (${_cert_zone} subdomains only)"
        else
            # No cert fallback available — require API auth
            if cf_require_auth "Deploying to ${hostname}"; then
                :
            else
                case $? in
                    2) return 0 ;;
                    3) return 3 ;;
                    *) return 1 ;;
                esac
            fi
        fi
    fi

    # === Step: Clone ===
    if $do_clone; then
        step "${step_clone}/${total_steps}" "Cloning $repo..."
        if ! repo_clone "$repo" "$app_dir"; then
            error "Failed to clone repository."
            return 1
        fi
        success "Cloned to $app_dir"
    fi

    # Resolve deferred port after clone
    if $port_deferred; then
        local detect_result
        detect_result=$(detect_app_port "$app_dir") || true
        if [[ -n "$detect_result" ]]; then
            port="${detect_result%% *}"
            detected_source="${detect_result#* }"
            info "Auto-detected port $port ($detected_source)"
        else
            port=5000
            info "Could not detect port, using default: $port"
        fi
    fi

    # Re-detect runtime after clone (may have been empty if clone deferred)
    if [[ -z "$runtime" ]] && $has_app_source && [[ -d "$app_dir" ]]; then
        runtime=$(ferry_detect_runtime_from_dir "$app_dir")
        [[ -n "$runtime" ]] && info "Detected runtime: $runtime"
    fi

    # Warn if no Dockerfile or package.json (buildpack detection may fail)
    if $has_app_source && [[ -d "$app_dir" ]]; then
        if [[ ! -f "$app_dir/Dockerfile" ]] && [[ ! -f "$app_dir/package.json" ]]; then
            warn "No Dockerfile or package.json found — Dokku may not detect a buildpack."
            warn "Consider adding a Dockerfile to $app_dir"
        fi
    fi

    # === Step: Create Dokku app + configure ===
    step "${step_dokku}/${total_steps}" "Creating Dokku app '$name'..."
    local create_output create_exit=0
    create_output=$(dokku_cmd apps:create "$name" 2>&1) || create_exit=$?
    if [[ $create_exit -eq 0 ]] && echo "$create_output" | grep -qi "creating\|created\|already exists"; then
        success "Dokku app '$name' created"
    elif echo "$create_output" | grep -qi "already exists"; then
        success "Dokku app '$name' already exists"
    else
        error "Failed to create Dokku app (exit $create_exit): $create_output"
        return 1
    fi

    info "Configuring Dokku domains + ports..."
    local domain_output domain_exit=0 port_output port_exit=0
    domain_output=$(dokku_cmd domains:set "$name" "$hostname" 2>&1) || domain_exit=$?
    if [[ $domain_exit -eq 0 ]]; then
        success "Domain set to $hostname"
    else
        error "Domain setup failed (exit $domain_exit): $domain_output"
        return 1
    fi

    port_output=$(dokku_cmd ports:set "$name" "http:80:$port" 2>&1) || port_exit=$?
    if [[ $port_exit -eq 0 ]]; then
        success "Ports set to http:80:$port"
    else
        error "Port setup failed (exit $port_exit): $port_output"
        return 1
    fi

    local resource_output resource_exit=0
    resource_output=$(dokku_cmd resource:limit "$name" --memory "$memory" 2>&1) || resource_exit=$?
    if [[ $resource_exit -eq 0 ]]; then
        success "Resource limits set (memory: ${memory} MB)"
    else
        warn "Failed to set resource limits: $resource_output"
    fi

    # Persist Ferry-managed config so `ferry tune` and future deploys can read them.
    # If this is a Node app, seed NODE_OPTIONS with a sensible heap cap below the cgroup
    # so V8 GCs aggressively before hitting the container limit (avoiding SIGABRT/SIGKILL).
    local -a ferry_config=("FERRY_MEMORY=$memory")
    [[ -n "$runtime" ]] && ferry_config+=("FERRY_RUNTIME=$runtime")
    if [[ "$runtime" == "node" ]]; then
        local heap
        heap=$(ferry_calc_node_heap "$memory")
        ferry_config+=("NODE_OPTIONS=--max-old-space-size=${heap}")
    fi

    local fcfg_out fcfg_exit=0
    fcfg_out=$(dokku_cmd config:set --no-restart "$name" "${ferry_config[@]}" 2>&1) || fcfg_exit=$?
    if [[ $fcfg_exit -eq 0 ]]; then
        success "Ferry config set (${#ferry_config[@]} vars)"
    else
        warn "Failed to set ferry config: $fcfg_out"
    fi

    # Ensure the app starts on the webserver network so nginx gets the
    # correct IP. Without this, nginx may grab the bridge network IP
    # which is unreachable from cloudflared/dokku after a restart.
    local net_output net_exit=0
    net_output=$(dokku_cmd network:set "$name" initial-network webserver 2>&1) || net_exit=$?
    if [[ $net_exit -eq 0 ]]; then
        success "Network set to webserver"
    else
        warn "Failed to set initial network: $net_output"
    fi

    # === Step: DNS ===
    step "${step_dns}/${total_steps}" "Creating DNS CNAME for $hostname..."
    local dns_output
    dns_output=$(dns_create_cname "$hostname" 2>&1)
    local dns_exit=$?
    if [[ $dns_exit -eq 0 ]] && echo "$dns_output" | grep -qi "added\|already exists\|via API"; then
        success "DNS CNAME created (or already exists)"
    else
        error "DNS creation failed (exit code $dns_exit): $dns_output"
        local dns_choice=0
        if confirm "Continue deploy anyway?"; then
            dns_choice=0
        else
            dns_choice=$?
        fi
        case "$dns_choice" in
            0) ;;
            2) return 0 ;;
            3) return 3 ;;
            *) return 0 ;;
        esac
    fi

    # === Step: Ingress ===
    step "${step_ingress}/${total_steps}" "Adding ingress rule: $hostname → http://dokku:80"
    local yaml_result
    yaml_result=$(yaml_add_ingress "$hostname" "http://dokku:80" 2>&1)
    if [[ "$yaml_result" == "ok" ]]; then
        success "Ingress rule added to config.yml"
    else
        error "Failed to add ingress rule: $yaml_result"
        error "Stopping — Dokku app was created but ingress was not added."
        warn "Clean up with: ferry remove $name"
        return 1
    fi

    # === Step: Restart cloudflared ===
    step "${step_cf}/${total_steps}" "Restarting cloudflared..."
    if ! cloudflared_restart; then
        error "cloudflared failed to restart!"
        failed=1
    fi

    # === Step: Push to Dokku ===
    if $do_push; then
        step "${step_push}/${total_steps}" "Pushing app to Dokku..."
        local push_exit=0
        dokku_push "$app_dir" "$name" "$branch" || push_exit=$?
        if [[ $push_exit -eq 0 ]]; then
            success "App pushed to Dokku successfully"
        else
            error "Push failed (exit $push_exit)"
            failed=1
            echo ""
            local display_branch
            display_branch=$(git -C "$app_dir" branch --show-current 2>/dev/null) || display_branch="main"
            warn "Retry with: cd $app_dir && git push dokku ${display_branch}:master"
        fi
    fi

    # === Step: Verify ===
    step "${step_verify}/${total_steps}" "Verifying setup..."
    local verify_ok=true

    # Check Dokku app exists
    if dokku_app_exists "$name"; then
        success "Dokku app '$name' exists"
    else
        error "Dokku app '$name' not found"
        verify_ok=false
    fi

    # Check ingress rule
    local verify_ingress
    verify_ingress=$(yaml_has_hostname "$hostname")
    if [[ "$verify_ingress" == "yes" ]]; then
        success "Ingress rule for '$hostname' present"
    else
        error "Ingress rule for '$hostname' missing"
        verify_ok=false
    fi

    # Check DNS (may take time to propagate)
    local verify_dns
    verify_dns=$(dns_check "$hostname" 2>/dev/null || true)
    if [[ -n "$verify_dns" ]]; then
        success "DNS resolves: $hostname → $verify_dns"
    else
        warn "DNS not resolving yet (may take a few minutes to propagate)"
    fi

    # Config validation
    local config_valid
    config_valid=$(yaml_validate 2>&1)
    if [[ "$config_valid" == ok* ]]; then
        success "Config validation passed: $config_valid"
    else
        error "Config validation failed: $config_valid"
        verify_ok=false
    fi

    # Live check (only if we pushed)
    if $do_push && ((failed == 0)); then
        post_deploy_verify "$hostname" "$name" || true
    fi

    # Summary
    echo ""
    if ((failed == 0)) && $verify_ok; then
        box "${C_SUCCESS}✓ Deploy Complete${C_RESET}"
    else
        box "${C_WARN}! Deploy finished with warnings${C_RESET}"
        warn "Review the output above for any issues."
    fi

    echo ""
    if $do_push && ((failed == 0)); then
        echo -e "  ${C_SUCCESS}Your app is live at ${C_BOLD}https://$hostname${C_RESET}"
    elif $has_app_source; then
        local display_branch
        display_branch=$(git -C "$app_dir" branch --show-current 2>/dev/null) || display_branch="main"
        if $no_push; then
            dim "Infrastructure is ready. Push manually:"
        else
            dim "Push manually to complete deployment:"
        fi
        echo ""
        echo -e "    ${C_CHROME}\$${C_RESET} ${C_WHITE}cd $app_dir${C_RESET}"
        echo -e "    ${C_CHROME}\$${C_RESET} ${C_WHITE}git push dokku ${display_branch}:master${C_RESET}"
    else
        dim "Next steps — push your app:"
        echo ""
        echo -e "    ${C_CHROME}\$${C_RESET} ${C_WHITE}git remote add dokku ssh://dokku@localhost:3022/${name}${C_RESET}"
        echo -e "    ${C_CHROME}\$${C_RESET} ${C_WHITE}git push dokku main:master${C_RESET}"
    fi
    echo ""
}

###############################################################################
# Command: remove
###############################################################################

cmd_remove() {
    preflight

    local name=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes) YES=true; shift ;;
            -*)       error "Unknown flag: $1"; return 1 ;;
            *)        name="$1"; shift ;;
        esac
    done

    if [[ -z "$name" ]] && $YES; then
        error "App name required when using -y/--yes."
        return 1
    fi

    section_header "Remove Application"
    echo ""

    if [[ -z "$name" ]]; then
        if tui_select_app "Remove App"; then
            :
        else
            case $? in
                2) info "Cancelled."; return 0 ;;
                3) return 3 ;;
                *) info "Cancelled."; return 0 ;;
            esac
        fi
        name="$_TUI_APP_SELECTED"
    fi

    if [[ -z "$name" ]]; then
        error "No app name provided."
        return 1
    fi

    if ! dokku_app_exists "$name"; then
        error "App '$name' does not exist in Dokku."
        return 1
    fi

    # Get app info
    local domain ports status
    domain=$(dokku_app_domains "$name")
    ports=$(dokku_app_ports "$name")
    status=$(dokku_app_status "$name")

    box "${C_ERROR}${C_BOLD}This will permanently remove:${C_RESET}" \
        "" \
        "  App:      ${name}" \
        "  Domain:   ${domain}" \
        "  Ports:    ${ports}" \
        "  Status:   ${status}"
    echo ""
    dim "  Actions:"
    dim "    1. Destroy Dokku app and all data"
    dim "    2. Remove ingress rule"
    dim "    3. Restart cloudflared"
    if [[ -n "$CF_API_TOKEN" ]]; then
        dim "    4. Delete DNS CNAME record"
    else
        dim "    4. DNS CNAME (manual — no API token)"
    fi
    echo ""

    local confirm_choice=0
    if confirm_name "$name"; then
        confirm_choice=0
    else
        confirm_choice=$?
    fi
    case "$confirm_choice" in
        0) ;;
        2) info "Cancelled."; return 0 ;;
        3) return 3 ;;
        *) info "Cancelled."; return 0 ;;
    esac

    echo ""

    # Step 1: Destroy Dokku app
    step "1/4" "Destroying Dokku app '$name'..."
    local destroy_output
    destroy_output=$(dokku_cmd apps:destroy "$name" --force 2>&1) || true
    if ! dokku_app_exists "$name"; then
        success "Dokku app '$name' destroyed"
    else
        error "Failed to destroy app: $destroy_output"
        warn "Continuing with remaining cleanup..."
    fi

    # Step 2: Remove ingress rule
    step "2/4" "Removing ingress rule for '$domain'..."
    if [[ -n "$domain" ]]; then
        local yaml_result
        yaml_result=$(yaml_remove_ingress "$domain" 2>&1)
        if [[ "$yaml_result" == "ok" ]]; then
            success "Ingress rule removed"
        else
            warn "Ingress removal: $yaml_result"
        fi
    else
        warn "No domain found — skipping ingress removal"
    fi

    # Step 3: Restart cloudflared
    step "3/4" "Restarting cloudflared..."
    cloudflared_restart || warn "cloudflared restart had issues"

    # Step 4: DNS cleanup
    step "4/4" "DNS cleanup..."
    if [[ -n "$domain" ]]; then
        if [[ -n "$CF_API_TOKEN" ]] && cf_token_verify 2>/dev/null; then
            if dns_delete_record "$domain"; then
                success "DNS CNAME for '$domain' deleted"
            else
                warn "Could not delete DNS record automatically"
            fi
        else
            warn "Cannot delete DNS record — no valid API token."
            echo -e "    ${C_WARN}The DNS CNAME for '${domain}' still exists in Cloudflare.${C_RESET}"
            echo -e "    ${C_WARN}Delete it manually: Cloudflare Dashboard → DNS → delete CNAME for '${domain}'${C_RESET}"
            dim "    Or run ${C_ACCENT}ferry login${C_RESET}${C_DIM} and re-run removal."
        fi
    fi

    # Validate config
    local config_valid
    config_valid=$(yaml_validate 2>&1)
    if [[ "$config_valid" == ok* ]]; then
        success "Config validation passed: $config_valid"
    fi

    echo ""
    box "${C_SUCCESS}✓ Removal Complete${C_RESET}" \
        "" \
        "  App '${name}' has been removed."
    echo ""
}

###############################################################################
# Command: prune
###############################################################################

cmd_prune_reconcile() {
    preflight

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes) YES=true; shift ;;
            -*)       error "Unknown flag: $1"; return 1 ;;
            *)        shift ;;
        esac
    done

    if [[ -z "$CF_API_TOKEN" ]]; then
        error "Cloudflare API token required. Run 'ferry login' first."
        return 1
    fi

    if ! cf_token_verify; then
        error "Cloudflare API token is not valid."
        return 1
    fi

    section_header "Prune: Reconcile Ingress"
    echo ""
    dim "Live check: fetching the current Cloudflare Tunnel ingress and Dokku domains."
    echo ""

    local all_domains ingress
    all_domains=$(dokku_list_all_domains) || return 1
    ingress=$(_tunnel_get_ingress) || return 1

    declare -A live_domains=()
    while IFS= read -r domain; do
        [[ -n "$domain" ]] && live_domains["$domain"]=1
    done <<< "$all_domains"

    local -a orphan_rules=()
    local prune_hosts=""
    while IFS=$'\t' read -r hostname service; do
        [[ -z "$hostname" || "$hostname" == "(catch-all)" ]] && continue
        if [[ -z "${live_domains[$hostname]:-}" ]]; then
            orphan_rules+=("$hostname"$'\t'"$service")
            prune_hosts+="${hostname}"$'\n'
        fi
    done < <(printf '%s' "$ingress" | python3 -c "
import json, sys
rules = json.load(sys.stdin)
for r in rules:
    hostname = r.get('hostname') or '(catch-all)'
    service = r.get('service') or '?'
    print(f'{hostname}\t{service}')
")

    if (( ${#orphan_rules[@]} == 0 )); then
        success "No orphan ingress rules found."
        return 0
    fi

    box "${C_WARN}${C_BOLD}Orphan ingress rules found${C_RESET}" \
        "" \
        "  Ferry will remove ingress rules that no longer map to any live Dokku domain." \
        ""
    for rule in "${orphan_rules[@]}"; do
        local rule_host rule_service
        IFS=$'\t' read -r rule_host rule_service <<< "$rule"
        printf '  %s- %s → %s%s\n' "$C_DIM" "$rule_host" "$rule_service" "$C_RESET"
    done
    echo ""

    local confirm_choice=0
    if confirm "Prune these orphan ingress rule(s) now?"; then
        confirm_choice=0
    else
        confirm_choice=$?
    fi
    case "$confirm_choice" in
        0) ;;
        2) info "Cancelled."; return 0 ;;
        3) return 3 ;;
        *) info "Cancelled."; return 0 ;;
    esac

    echo ""
    step "1/2" "Pruning orphan ingress rules..."
    local prune_result
    prune_result=$(yaml_prune_ingress "$prune_hosts" 2>&1) || {
        error "Failed to update tunnel ingress: $prune_result"
        return 1
    }
    success "Removed ${#orphan_rules[@]} orphan ingress rule(s)"

    step "2/2" "Restarting cloudflared..."
    cloudflared_restart || warn "cloudflared restart had issues"

    local config_valid
    config_valid=$(yaml_validate 2>&1)
    if [[ "$config_valid" == ok* ]]; then
        success "Config validation passed: $config_valid"
    fi

    echo ""
    box "${C_SUCCESS}✓ Reconcile Complete${C_RESET}" \
        "" \
        "  Removed ${#orphan_rules[@]} orphan ingress rule(s)."
    echo ""
}

cmd_prune() {
    local subcommand="${1:-reconcile}"
    if [[ $# -gt 0 ]]; then
        shift
    fi

    case "$subcommand" in
        reconcile|"")
            cmd_prune_reconcile "$@"
            ;;
        -h|--help|help)
            echo ""
            section_header "Prune"
            echo ""
            echo -e "    ${C_WHITE}ferry prune reconcile${C_RESET}          ${C_DIM}Remove orphan ingress rules after a live check${C_RESET}"
            echo ""
            ;;
        *)
            error "Usage: ferry prune reconcile"
            return 1
            ;;
    esac
}

###############################################################################
# Command: reload
###############################################################################

cmd_reload() {
    preflight

    section_header "Validate & Reload"
    echo ""

    info "Validating config.yml..."
    local valid
    valid=$(yaml_validate 2>&1)
    if [[ "$valid" == ok* ]]; then
        success "Config valid: $valid"
    else
        error "Config validation failed: $valid"
        error "Fix config.yml before reloading."
        return 1
    fi

    echo ""
    cloudflared_restart
    echo ""
}

###############################################################################
# Command: rebuild
###############################################################################

cmd_rebuild() {
    preflight

    local name=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes) shift ;;
            *) name="$1"; shift ;;
        esac
    done

    if [[ -z "$name" ]]; then
        error "Usage: $0 rebuild <app-name>"
        return 1
    fi

    if ! dokku_app_exists "$name"; then
        error "App '$name' does not exist."
        return 1
    fi

    section_header "Rebuild: $name"
    echo ""
    dokku_cmd ps:rebuild "$name"
    echo ""
    success "Rebuild complete."
}

###############################################################################
# Command: tune — Adjust per-app resource limits (memory + Node heap)
###############################################################################

cmd_tune() {
    preflight

    local name="" memory="" heap="" runtime_flag=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -m|--memory)  memory="$2"; shift 2 ;;
            --heap)       heap="$2"; shift 2 ;;
            --runtime)    runtime_flag="$2"; shift 2 ;;
            -y|--yes)     YES=true; shift ;;
            -*)           error "Unknown flag: $1"; return 1 ;;
            *)            name="$1"; shift ;;
        esac
    done

    # --- Validate app ---
    if [[ -z "$name" ]]; then
        if $YES; then
            error "App name required when using -y/--yes."
            return 1
        fi
        if tui_select_app "Tune App"; then
            [[ -n "$_TUI_APP_SELECTED" ]] || return 0
        else
            case $? in
                2) return 0 ;;
                3) return 3 ;;
                *) return 0 ;;
            esac
        fi
        name="$_TUI_APP_SELECTED"
    fi

    if ! dokku_app_exists "$name"; then
        error "App '$name' does not exist in Dokku."
        return 1
    fi

    section_header "Tune: $name"
    echo ""

    # --- Read current state ---
    local cur_mem cur_runtime cur_node_opts
    cur_mem=$(ferry_app_memory_limit "$name")
    cur_runtime=$(ferry_app_runtime "$name")
    cur_node_opts=$(ferry_app_node_options "$name")

    # Fallback runtime detection from app source dir
    local detected_runtime=""
    if [[ -z "$cur_runtime" && -d "$FERRY_APPS_DIR/$name" ]]; then
        detected_runtime=$(ferry_detect_runtime_from_dir "$FERRY_APPS_DIR/$name")
    fi

    kv "Current memory" "${cur_mem:-unset} MB"
    kv "Current NODE_OPTIONS" "${cur_node_opts:-(not set)}"
    if [[ -n "$cur_runtime" ]]; then
        kv "Runtime (config)" "$cur_runtime"
    elif [[ -n "$detected_runtime" ]]; then
        kv "Runtime (detected)" "$detected_runtime"
    else
        kv "Runtime" "(unknown)"
    fi
    echo ""

    # --- Resolve runtime ---
    local runtime="${runtime_flag:-${cur_runtime:-$detected_runtime}}"
    if [[ -z "$runtime" ]]; then
        if $YES; then
            warn "Runtime unknown — skipping heap auto-tune. Pass --runtime node to enable."
        else
            tui_read runtime "Runtime (node/python/go/ruby/rust/static, blank to skip heap tune)" "" true || {
                case $? in
                    2) return 0 ;;
                    3) return 3 ;;
                    *) return 1 ;;
                esac
            }
        fi
    fi

    # --- Resolve memory ---
    if [[ -z "$memory" ]]; then
        local default_mem="${cur_mem:-256}"
        if $YES; then
            memory="$default_mem"
        else
            local hint=""
            [[ "$runtime" == "node" ]] && hint=" (512+ recommended for Node)"
            tui_read memory "New memory limit in MB${hint}" "$default_mem" false || {
                case $? in
                    2) return 0 ;;
                    3) return 3 ;;
                    *) return 1 ;;
                esac
            }
            memory="${memory:-$default_mem}"
        fi
    fi

    if ! [[ "$memory" =~ ^[0-9]+$ ]] || ((memory < 64)); then
        error "Invalid memory '$memory' — must be integer ≥ 64."
        return 1
    fi

    # --- Resolve heap (Node only) ---
    local computed_heap=""
    if [[ "$runtime" == "node" ]]; then
        if [[ -n "$heap" ]]; then
            if ! [[ "$heap" =~ ^[0-9]+$ ]] || ((heap < 64)) || ((heap >= memory)); then
                error "Invalid heap '$heap' — must be integer, ≥ 64, and < memory ($memory)."
                return 1
            fi
            computed_heap="$heap"
        else
            computed_heap=$(ferry_calc_node_heap "$memory")
        fi
    fi

    # --- Plan ---
    section_header "Plan"
    echo ""
    kv "Memory" "${cur_mem:-unset} → ${memory} MB"
    if [[ -n "$computed_heap" ]]; then
        kv "NODE_OPTIONS" "--max-old-space-size=${computed_heap}"
    fi
    if [[ -n "$runtime" ]]; then
        kv "FERRY_RUNTIME" "$runtime"
    fi
    kv "FERRY_MEMORY" "$memory"
    dim "  App will restart. Container is regenerated from the existing image —"
    dim "  Dokku storage mounts, persistent volumes, and database links are preserved."
    echo ""

    if ! $YES; then
        local apply_choice=0
        if confirm "Apply these changes?"; then
            apply_choice=0
        else
            apply_choice=$?
        fi
        case "$apply_choice" in
            0) ;;
            2) info "Cancelled."; return 0 ;;
            3) return 3 ;;
            *) info "Cancelled."; return 0 ;;
        esac
    fi

    echo ""

    # --- Apply resource limit ---
    local rl_out rl_exit=0
    rl_out=$(dokku_cmd resource:limit "$name" --memory "$memory" 2>&1) || rl_exit=$?
    if ((rl_exit == 0)); then
        success "resource:limit set (memory: ${memory} MB)"
    else
        error "resource:limit failed (exit $rl_exit): $rl_out"
        return 1
    fi

    # --- Apply config (single call = one restart) ---
    local -a config_pairs=()
    config_pairs+=("FERRY_MEMORY=$memory")
    [[ -n "$runtime" ]] && config_pairs+=("FERRY_RUNTIME=$runtime")
    if [[ -n "$computed_heap" ]]; then
        config_pairs+=("NODE_OPTIONS=--max-old-space-size=${computed_heap}")
    fi

    local cfg_out cfg_exit=0
    cfg_out=$(dokku_cmd config:set --no-restart "$name" "${config_pairs[@]}" 2>&1) || cfg_exit=$?
    if ((cfg_exit == 0)); then
        success "config updated (${#config_pairs[@]} vars)"
    else
        error "config:set failed (exit $cfg_exit): $cfg_out"
        return 1
    fi

    # --- Restart (explicit to apply new limit) ---
    info "Restarting app..."
    local rs_out rs_exit=0
    rs_out=$(dokku_cmd ps:restart "$name" 2>&1) || rs_exit=$?
    if ((rs_exit == 0)); then
        success "ps:restart complete"
    else
        warn "ps:restart exited $rs_exit: $rs_out"
        warn "If the app never deployed, try: ferry rebuild $name"
    fi

    # --- Verify ---
    echo ""
    local status
    status=$(dokku_app_status "$name")
    if [[ "$status" == "running" ]]; then
        box "${C_SUCCESS}✓ Tune complete — app is running${C_RESET}"
    else
        box "${C_WARN}! Tune applied — app status: ${status}${C_RESET}"
        dim "  Check logs: ferry logs $name"
    fi
    echo ""
}

###############################################################################
# Command: logs
###############################################################################

cmd_logs() {
    preflight

    local name=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes) shift ;;
            *) name="$1"; shift ;;
        esac
    done

    if [[ -z "$name" ]]; then
        error "Usage: $0 logs <app-name>"
        return 1
    fi

    if ! dokku_app_exists "$name"; then
        error "App '$name' does not exist."
        return 1
    fi

    info "Tailing logs for '$name' (Ctrl+C to stop)..."
    echo ""
    dokku_cmd logs "$name" --tail
}

###############################################################################
# Command: new — Scaffold a new app from a template
###############################################################################

FERRY_APPS_DIR="${FERRY_APPS_DIR:-$SCRIPT_DIR/apps}"
GENERATORS_DIR="$SCRIPT_DIR/generators"

# Discover available generators by scanning generators/*/metadata.sh
# Populates parallel arrays: _GEN_IDS, _GEN_NAMES, _GEN_DESCS, _GEN_CATS, _GEN_PORTS, _GEN_TYPES, _GEN_LANGS
_GEN_IDS=() _GEN_NAMES=() _GEN_DESCS=() _GEN_CATS=() _GEN_PORTS=() _GEN_TYPES=() _GEN_LANGS=()

discover_generators() {
    _GEN_IDS=() _GEN_NAMES=() _GEN_DESCS=() _GEN_CATS=() _GEN_PORTS=() _GEN_TYPES=() _GEN_LANGS=()
    local meta
    for meta in "$GENERATORS_DIR"/*/metadata.sh; do
        [[ -f "$meta" ]] || continue
        [[ "$(basename "$(dirname "$meta")")" == "_shared" ]] && continue
        local GENERATOR_ID="" GENERATOR_NAME="" GENERATOR_DESC="" GENERATOR_CATEGORY=""
        local GENERATOR_PORT="" GENERATOR_TYPE="" GENERATOR_LANG=""
        # shellcheck source=/dev/null
        source "$meta"
        [[ -z "$GENERATOR_ID" ]] && continue
        _GEN_IDS+=("$GENERATOR_ID")
        _GEN_NAMES+=("$GENERATOR_NAME")
        _GEN_DESCS+=("$GENERATOR_DESC")
        _GEN_CATS+=("$GENERATOR_CATEGORY")
        _GEN_PORTS+=("$GENERATOR_PORT")
        _GEN_TYPES+=("$GENERATOR_TYPE")
        _GEN_LANGS+=("$GENERATOR_LANG")
    done
}

# Get index of a generator by ID. Returns 0 on success, 1 if not found. Index in _GEN_IDX.
_GEN_IDX=-1
gen_index_by_id() {
    local id="$1"
    for i in "${!_GEN_IDS[@]}"; do
        if [[ "${_GEN_IDS[$i]}" == "$id" ]]; then
            _GEN_IDX=$i
            return 0
        fi
    done
    return 1
}

# List available templates
cmd_new_list() {
    discover_generators

    if [[ ${#_GEN_IDS[@]} -eq 0 ]]; then
        warn "No generators found in $GENERATORS_DIR"
        return 1
    fi

    section_header "Available Templates"
    echo ""

    local cat label
    for cat in backend frontend fullstack; do
        case "$cat" in
            backend)   label="Backend" ;;
            frontend)  label="Frontend" ;;
            fullstack) label="Fullstack" ;;
        esac

        local has_items=false
        for i in "${!_GEN_IDS[@]}"; do
            [[ "${_GEN_CATS[$i]}" == "$cat" ]] && has_items=true && break
        done
        $has_items || continue

        echo -e "  ${C_BOLD}${C_WHITE}${label}${C_RESET}"
        for i in "${!_GEN_IDS[@]}"; do
            [[ "${_GEN_CATS[$i]}" == "$cat" ]] || continue
            printf "    ${C_ACCENT}%-12s${C_RESET} ${C_DIM}%-38s${C_RESET} ${C_CHROME}:${_GEN_PORTS[$i]}${C_RESET}\n" \
                "${_GEN_IDS[$i]}" "${_GEN_DESCS[$i]}"
        done
        echo ""
    done

    dim "Usage: ferry new <name> -t <template>"
    echo ""
}

# Build TUI options for a given category
_build_category_options() {
    local cat="$1"
    _CAT_OPTIONS=()
    _CAT_INDICES=()
    for i in "${!_GEN_IDS[@]}"; do
        [[ "${_GEN_CATS[$i]}" == "$cat" ]] || continue
        _CAT_OPTIONS+=("$(printf '%-12s %s' "${_GEN_IDS[$i]}" "${_GEN_DESCS[$i]}")")
        _CAT_INDICES+=("$i")
    done
}

cmd_new() {
    # NOTE: No preflight — generating an app is a local filesystem operation

    local name="" template="" output_dir="" port="" do_deploy="" list_mode=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--template)  template="$2"; shift 2 ;;
            -o|--output)    output_dir="$2"; shift 2 ;;
            -p|--port)      port="$2"; shift 2 ;;
            --deploy)       do_deploy=true; shift ;;
            --no-deploy)    do_deploy=false; shift ;;
            -l|--list)      list_mode=true; shift ;;
            -y|--yes)       YES=true; shift ;;
            -*)             error "Unknown flag: $1"; return 1 ;;
            *)              name="$1"; shift ;;
        esac
    done

    discover_generators

    # --list mode
    if $list_mode; then
        cmd_new_list
        return 0
    fi

    # Validate -y requirements
    if $YES && { [[ -z "$name" ]] || [[ -z "$template" ]]; }; then
        error "Both <name> and --template are required with -y/--yes."
        return 1
    fi

    section_header "New Application"
    echo ""

    # --- 1. App name ---
    if [[ -z "$name" ]]; then
        tui_read name "App name (a-z, 0-9, hyphens)" "" false || {
            case $? in
                2) return 0 ;;
                3) return 3 ;;
                *) return 1 ;;
            esac
        }
    fi

    if ! [[ "$name" =~ ^[a-z][a-z0-9-]{0,28}[a-z0-9]$ ]]; then
        error "Invalid name '$name'. Use 2-30 chars: lowercase letters, numbers, hyphens. Must start with a letter, cannot end with a hyphen."
        return 1
    fi

    # --- 2. Template selection ---
    if [[ -z "$template" ]]; then
        if ! $_IS_TTY; then
            error "Template required (--template). Run 'ferry new --list' to see options."
            return 1
        fi

        # Two-step TUI: category, then framework
        local categories=()
        local cat_labels=()
        for cat in backend frontend fullstack; do
            for i in "${!_GEN_IDS[@]}"; do
                if [[ "${_GEN_CATS[$i]}" == "$cat" ]]; then
                    categories+=("$cat")
                    case "$cat" in
                        backend)   cat_labels+=("Backend      API and server frameworks") ;;
                        frontend)  cat_labels+=("Frontend     Client-side applications") ;;
                        fullstack) cat_labels+=("Fullstack    SSR and full-stack frameworks") ;;
                    esac
                    break
                fi
            done
        done

        local selected_cat="" gen_idx=""
        while true; do
            if tui_select "Category" "${cat_labels[@]}"; then
                selected_cat="${categories[$_TUI_SELECTED]}"
            else
                case $? in
                    2) return 0 ;;
                    3) return 3 ;;
                    *) return 1 ;;
                esac
            fi

            while true; do
                _build_category_options "$selected_cat"
                if tui_select "Framework" "${_CAT_OPTIONS[@]}"; then
                    gen_idx="${_CAT_INDICES[$_TUI_SELECTED]}"
                    template="${_GEN_IDS[$gen_idx]}"
                    break 2
                else
                    case $? in
                        2) break ;;
                        3) return 3 ;;
                        *) return 1 ;;
                    esac
                fi
            done
        done
    fi

    # Validate template
    if ! gen_index_by_id "$template"; then
        error "Unknown template '$template'."
        echo ""
        cmd_new_list || true
        return 1
    fi
    local idx=$_GEN_IDX

    # --- 3. Resolve port ---
    if [[ -z "$port" ]]; then
        port="${_GEN_PORTS[$idx]}"
    fi

    # --- 4. Resolve output directory ---
    if [[ -z "$output_dir" ]]; then
        output_dir="$FERRY_APPS_DIR/$name"
    fi

    if [[ -d "$output_dir" ]]; then
        error "Directory '$output_dir' already exists. Choose a different name or remove it first."
        return 1
    fi

    # --- 5. Summary + confirm ---
    if ! $YES; then
        echo ""
        section_header "New App Plan"
        echo ""
        kv "App name" "$name"
        kv "Template" "$template (${_GEN_DESCS[$idx]})"
        kv "Language" "${_GEN_LANGS[$idx]}"
        kv "Output" "$output_dir"
        kv "Port" "$port"
        if [[ "${_GEN_TYPES[$idx]}" == "server" ]]; then
            kv "Endpoints" "/ (HTML)  /json  /xml  /text  /health"
        else
            kv "Type" "Static SPA (client-side info only)"
        fi
        echo ""

        local proceed_choice=0
        if confirm "Proceed?"; then
            proceed_choice=0
        else
            proceed_choice=$?
        fi
        case "$proceed_choice" in
            0) ;;
            2) dim "Cancelled."; return 0 ;;
            3) return 3 ;;
            *) dim "Cancelled."; return 0 ;;
        esac
    fi

    echo ""

    # --- 6. Run generator ---
    local gen_dir="$GENERATORS_DIR/$template"
    local gen_script="$gen_dir/generate.sh"

    if [[ ! -x "$gen_script" ]]; then
        error "Generator script not found or not executable: $gen_script"
        return 1
    fi

    step "1/3" "Generating project from ${C_ACCENT}${template}${C_RESET} template..."
    mkdir -p "$output_dir"

    if ! APP_NAME="$name" APP_PORT="$port" OUTPUT_DIR="$output_dir" \
         SHARED_DIR="$GENERATORS_DIR/_shared" FERRY_VERSION="$FERRY_VERSION" \
         bash "$gen_script"; then
        error "Generator failed."
        return 1
    fi

    local file_count
    file_count=$(find "$output_dir" -type f | wc -l)
    success "Created $file_count files"

    # --- 7. Git init ---
    step "2/3" "Initializing git repository..."
    if command -v git &>/dev/null; then
        git -C "$output_dir" init --quiet 2>/dev/null
        git -C "$output_dir" add -A 2>/dev/null
        # Best effort: local git identity may not be configured yet.
        if git -C "$output_dir" -c commit.gpgsign=false commit --quiet \
            -m "Initial scaffold from ferry new ($template)" >/dev/null 2>&1; then
            success "Created initial commit"
        else
            warn "Git repo initialized, but initial commit was skipped (check git user.name / user.email)"
        fi
    else
        warn "git not found — skipping git init"
    fi

    # --- 8. Validate ---
    step "3/3" "Validating..."
    if [[ -f "$output_dir/Dockerfile" ]]; then
        success "Dockerfile present"
    else
        warn "No Dockerfile found"
    fi

    local detect_result=""
    detect_result=$(detect_app_port "$output_dir") || true
    if [[ -n "$detect_result" ]]; then
        success "Port ${detect_result%% *} detected (${detect_result#* })"
    fi

    # --- 9. Success ---
    echo ""
    box "${C_SUCCESS}App '${name}' created successfully${C_RESET}"
    echo ""
    kv "Output" "$output_dir"
    echo ""

    # --- 10. Deploy chain ---
    if [[ "$do_deploy" == "true" ]]; then
        info "Chaining to deploy..."
        echo ""
        if $YES; then
            if cmd_deploy "$name" -d "$output_dir" -y; then
                :
            else
                local chain_rc=$?
                [[ $chain_rc -eq 3 ]] && return 3
                return 1
            fi
        else
            if cmd_deploy "$name" -d "$output_dir"; then
                :
            else
                local chain_rc=$?
                [[ $chain_rc -eq 3 ]] && return 3
                return 1
            fi
        fi
    elif [[ "$do_deploy" == "false" ]]; then
        dim "Next: ferry deploy $name"
        echo ""
    elif ! $YES && $_IS_TTY; then
        echo ""
        local deploy_now_choice=0
        if confirm "Deploy '$name' now?"; then
            deploy_now_choice=0
        else
            deploy_now_choice=$?
        fi
        case "$deploy_now_choice" in
            0)
            echo ""
            if cmd_deploy "$name" -d "$output_dir"; then
                :
            else
                local deploy_chain_rc=$?
                [[ $deploy_chain_rc -eq 3 ]] && return 3
                return 1
            fi
            ;;
            2)
            echo ""
            dim "Next steps:"
            echo -e "    ${C_CHROME}\$${C_RESET} ${C_WHITE}cd $output_dir${C_RESET}"
            echo -e "    ${C_CHROME}\$${C_RESET} ${C_WHITE}ferry deploy $name${C_RESET}"
            echo ""
            ;;
            3) return 3 ;;
        esac
    else
        echo ""
        dim "Next: ferry deploy $name"
        echo ""
    fi
}

###############################################################################
# Command: help
###############################################################################
cmd_help() {
    echo ""
    echo -e "  ${C_BOLD}${C_WHITE}ferry${C_RESET} ${C_DIM}— Deploy web apps via Dokku + Cloudflare Tunnel${C_RESET}"

    section_header "Usage"
    echo ""
    echo -e "    ${C_WHITE}ferry${C_RESET}                                  ${C_DIM}Interactive menu${C_RESET}"
    echo -e "    ${C_WHITE}ferry new${C_RESET} <name> [-t <tmpl>] [-y]      ${C_DIM}Create app from template${C_RESET}"
    echo -e "    ${C_WHITE}ferry login${C_RESET} [opts]                       ${C_DIM}API token + host tunnel setup${C_RESET}"
    echo -e "    ${C_WHITE}ferry deploy${C_RESET} <name> [opts] [-y]        ${C_DIM}Deploy a new app${C_RESET}"
    echo -e "    ${C_WHITE}ferry remove${C_RESET} <name> [-y]               ${C_DIM}Remove an app${C_RESET}"
    echo -e "    ${C_WHITE}ferry prune reconcile${C_RESET}                  ${C_DIM}Reconcile orphan ingress rules${C_RESET}"
    echo -e "    ${C_WHITE}ferry status${C_RESET}                           ${C_DIM}System dashboard${C_RESET}"
    echo -e "    ${C_WHITE}ferry list${C_RESET}                             ${C_DIM}Quick app list${C_RESET}"
    echo -e "    ${C_WHITE}ferry reload${C_RESET}                           ${C_DIM}Validate + restart cloudflared${C_RESET}"
    echo -e "    ${C_WHITE}ferry rebuild${C_RESET} <name>                   ${C_DIM}Rebuild a Dokku app${C_RESET}"
    echo -e "    ${C_WHITE}ferry tune${C_RESET} <name> [opts]               ${C_DIM}Adjust memory limits + Node heap${C_RESET}"
    echo -e "    ${C_WHITE}ferry logs${C_RESET} <name>                      ${C_DIM}Tail app logs${C_RESET}"
    echo -e "    ${C_WHITE}ferry help${C_RESET}                             ${C_DIM}Show this help${C_RESET}"

    section_header "New Flags"
    echo ""
    kv "-t, --template" "Generator template (express, nextjs, fastapi, etc.)"
    kv "-o, --output" "Output directory (default: \$FERRY_APPS_DIR/<name>)"
    kv "-p, --port" "Override default port"
    kv "--deploy" "Deploy immediately after generation"
    kv "--no-deploy" "Skip deploy prompt"
    kv "-l, --list" "List available templates"

    section_header "Deploy Flags"
    echo ""
    kv "-r, --repo" "GitHub repo to clone (owner/repo or URL)"
    kv "-H, --hostname" "App hostname (default: <name>.\${DOKKU_HOSTNAME})"
    kv "-p, --port" "App port (default: auto-detect, fallback: 5000)"
    kv "-m, --memory" "Container memory limit in MB (default: 256)"
    kv "-b, --branch" "Git branch to push (default: auto-detect)"
    kv "-d, --dir" "Local app directory (skip clone)"
    kv "--no-push" "Infrastructure only, skip git push"
    kv "-y, --yes" "Skip all confirmations"
    kv "-t, --token" "API token for login (skip prompt)"
    kv "--tunnel-name" "Preferred host tunnel name for login create/select (default: ferry)"

    section_header "Tune Flags"
    echo ""
    kv "-m, --memory" "New container memory limit in MB (min 64)"
    kv "--heap" "Override Node --max-old-space-size (default: memory - 48)"
    kv "--runtime" "node|python|go|ruby|rust — enables heap tune for node"

    section_header "Examples"
    echo ""
    echo -e "    ${C_CHROME}\$${C_RESET} ${C_WHITE}ferry new myapp -t express -y${C_RESET}"
    echo -e "    ${C_CHROME}\$${C_RESET} ${C_WHITE}ferry new myapp -t fastapi --deploy -y${C_RESET}"
    echo -e "    ${C_CHROME}\$${C_RESET} ${C_WHITE}ferry new --list${C_RESET}"
    echo -e "    ${C_CHROME}\$${C_RESET} ${C_WHITE}ferry deploy myapp${C_RESET}"
    echo -e "    ${C_CHROME}\$${C_RESET} ${C_WHITE}ferry deploy myapp -r owner/repo -H app.example.com -y${C_RESET}"
    echo -e "    ${C_CHROME}\$${C_RESET} ${C_WHITE}ferry deploy myapp -d ./my-app -m 512 -y${C_RESET}"
    echo -e "    ${C_CHROME}\$${C_RESET} ${C_WHITE}ferry deploy myapp -r owner/repo --no-push -y${C_RESET}"
    echo -e "    ${C_CHROME}\$${C_RESET} ${C_WHITE}ferry prune reconcile${C_RESET}"
    echo -e "    ${C_CHROME}\$${C_RESET} ${C_WHITE}ferry tune myapp -m 512 --runtime node -y${C_RESET}"
    echo -e "    ${C_CHROME}\$${C_RESET} ${C_WHITE}ferry remove myapp -y${C_RESET}"

    section_header "Environment"
    echo ""
    kv "TUNNEL_ID" "(auto) Host tunnel UUID — set via ferry login"
    kv "TUNNEL_TOKEN" "(auto) Connector token for cloudflared — set via ferry login"
    kv "DOKKU_HOSTNAME" "(required) Default domain for app hostnames"
    kv "CF_API_TOKEN" "(auto) Set via ferry login"
    kv "CF_ACCOUNT_ID" "(auto) Auto-discovered"
    echo ""
}

###############################################################################
# Command: login
###############################################################################

cmd_login() {
    local provided_token=""
    local tunnel_name="ferry"
    local tunnel_name_explicit=false
    local keep_existing_token=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--token) provided_token="$2"; shift 2 ;;
            --tunnel-name) tunnel_name="$2"; tunnel_name_explicit=true; shift 2 ;;
            -y|--yes)   YES=true; shift ;;
            -*)         error "Unknown flag: $1"; return 1 ;;
            *)          shift ;;
        esac
    done

    if [[ -z "$tunnel_name" ]]; then
        error "--tunnel-name cannot be empty"
        return 1
    fi

    section_header "Cloudflare API Setup"
    echo ""

    # Step 1: Check current state
    if [[ -n "$CF_API_TOKEN" ]]; then
        info "Existing token found. Checking..."
        if cf_token_verify; then
            success "Current token is valid."

            if [[ -n "$provided_token" ]]; then
                info "Replacing with provided token..."
            elif [[ -z "$provided_token" ]] && $YES; then
                # -y without -t: keep existing valid token, continue to tunnel bootstrap
                info "Keeping current valid token."
                keep_existing_token=true
            else
                local replace_choice=0
                if confirm "Replace existing token?"; then
                    replace_choice=0
                else
                    replace_choice=$?
                fi
                case "$replace_choice" in
                    0) ;;
                    2) info "Keeping current token."; keep_existing_token=true ;;
                    3) return 3 ;;
                    *) info "Keeping current token."; keep_existing_token=true ;;
                esac
            fi
        else
            warn "Current token is ${_cf_token_status}. Let's set up a new one."
            if [[ -z "$provided_token" ]] && ! [[ -t 0 ]]; then
                error "Current token is ${_cf_token_status} and no new token provided (-t)."
                return 1
            fi
        fi
    else
        info "No API token configured yet."
        if [[ -z "$provided_token" ]] && ! [[ -t 0 ]]; then
            error "No token configured and no token provided (-t). Cannot proceed non-interactively."
            return 1
        fi
    fi

    # Step 2: Get / save API token (unless keeping a valid existing one)
    if ! $keep_existing_token; then
        local new_token=""
        if [[ -n "$provided_token" ]]; then
            new_token="$provided_token"
        else
            echo ""
            section_header "Create API Token"
            echo ""
            echo "  You need a Cloudflare API token with these permissions:"
            echo ""
            kv_color "Zone : DNS : Edit" "create/delete DNS records" "$C_SUCCESS"
            kv_color "Zone : Zone : Read" "look up zone IDs" "$C_SUCCESS"
            kv_color "Account : Cloudflare Tunnel : Edit" "create/list tunnels + connector token" "$C_SUCCESS"
            echo ""
            echo "  Steps:"
            echo "    1. Open the URL below in your browser"
            echo "    2. Create a custom token with the permissions above"
            echo "    3. Under 'Zone Resources', select 'All zones'"
            echo "    4. Under 'Account Resources', select your account"
            echo "    5. Click 'Continue to summary' → 'Create Token'"
            echo "    6. Copy the token and paste it here"
            echo ""
            echo -e "  ${C_ACCENT}${CF_TOKEN_URL}${C_RESET}"
            echo ""

            if [[ -t 0 ]]; then
                if command -v xdg-open &>/dev/null; then
                    local browser_choice=0
                    if confirm "Open in browser?"; then
                        browser_choice=0
                    else
                        browser_choice=$?
                    fi
                    case "$browser_choice" in
                        0) xdg-open "$CF_TOKEN_URL" 2>/dev/null & ;;
                        2) ;;
                        3) return 3 ;;
                    esac
                elif command -v open &>/dev/null; then
                    local browser_choice=0
                    if confirm "Open in browser?"; then
                        browser_choice=0
                    else
                        browser_choice=$?
                    fi
                    case "$browser_choice" in
                        0) open "$CF_TOKEN_URL" 2>/dev/null & ;;
                        2) ;;
                        3) return 3 ;;
                    esac
                fi
            fi

            echo ""
            tui_read new_token "API token" "" false || {
                case $? in
                    2) return 0 ;;
                    3) return 3 ;;
                    *) return 1 ;;
                esac
            }
        fi

        if [[ -z "$new_token" ]]; then
            error "No token provided."
            return 1
        fi

        new_token=$(echo "$new_token" | xargs)

        info "Validating token..."
        CF_API_TOKEN="$new_token"
        export CF_API_TOKEN

        if ! cf_token_verify; then
            error "Token validation failed (${_cf_token_status})."
            error "Make sure you copied the full token."
            return 1
        fi
        success "Token is valid!"

        env_set "CF_API_TOKEN" "$new_token"
        success "Token saved to $ENV_FILE"
    fi

    # Step 3: Discover account ID
    echo ""
    info "Discovering account..."
    local account_id
    account_id=$(cf_discover_account_id 2>&1) || true
    if [[ -n "$CF_ACCOUNT_ID" ]]; then
        success "Account ID saved: $CF_ACCOUNT_ID"
    else
        error "Could not discover account ID — tunnel bootstrap requires it."
        return 1
    fi

    # Step 4: Check permissions
    echo ""
    section_header "Permissions"
    if cf_check_permissions; then
        echo ""
        success "All critical permissions verified!"
    else
        echo ""
        warn "Some permissions are missing. The token may need more access."
        dim "Go to: https://dash.cloudflare.com/profile/api-tokens"
        dim "Edit the token and add: Zone DNS Edit, Zone Read, Account Cloudflare Tunnel Edit."
    fi

    # Step 5: Check cert.pem scope
    echo ""
    cert_check_all

    # Step 6: Ensure host tunnel (TUNNEL_ID + TUNNEL_TOKEN)
    echo ""
    section_header "Host Tunnel"
    echo ""
    dim "Ferry uses one shared Cloudflare Tunnel per host (not per app)."
    dim "See docs/tunnel-id.md for the model."
    echo ""
    if ! cf_ensure_tunnel "$tunnel_name" "$tunnel_name_explicit"; then
        local tunnel_rc=$?
        if [[ "$tunnel_rc" == "3" ]]; then
            return 3
        fi
        error "API token is saved, but host tunnel setup failed."
        dim "Fix Tunnel:Edit permission, then re-run: ferry login -y"
        return 1
    fi

    # Step 7: Summary
    echo ""
    echo ""
    box "${C_SUCCESS}✓ Setup Complete${C_RESET}" \
        "" \
        "  ${C_SUCCESS}✓${C_RESET} Cloudflare API access" \
        "  ${C_SUCCESS}✓${C_RESET} Host tunnel (TUNNEL_ID + TUNNEL_TOKEN)" \
        "  ${C_SUCCESS}✓${C_RESET} DNS + ingress ready for ferry deploy"
    echo ""
    if [[ -n "$TUNNEL_ID" ]]; then
        kv "TUNNEL_ID" "$TUNNEL_ID"
    fi
    echo ""
    dim "Next: docker compose up -d   # if the stack is not running yet"
    dim "Then: ferry deploy <app>"
    echo ""
}


###############################################################################
# Interactive Selector
###############################################################################

_TUI_SELECTED=0

tui_select() {
    # Arrow-key interactive selector.
    # Usage: tui_select "title" "opt1|desc1" "opt2|desc2" ...
    # Result stored in _TUI_SELECTED (0-based index). Returns 2 for back, 3 for quit.
    local allow_back=true
    if [[ "${1:-}" == "--no-back" ]]; then
        allow_back=false
        shift
    fi

    local title="$1"
    shift
    local options=("$@")
    local count=${#options[@]}

    # Non-TTY fallback: numbered list
    if ! $_IS_TTY; then
        echo ""
        echo "  $title"
        echo ""
        local i
        for ((i=0; i<count; i++)); do
            echo "  $((i+1))) ${options[$i]}"
        done
        echo ""
        echo -en "  Choice [1-$count]: "
        local choice
        read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= count)); then
            _TUI_SELECTED=$((choice - 1))
            return 0
        fi
        return 2
    fi

    local selected=0

    # Hide cursor
    tput civis 2>/dev/null || true
    trap 'tput cnorm 2>/dev/null || true; trap - RETURN' RETURN

    # Header
    section_header "$title"
    echo ""
    if $allow_back; then
        echo -e "  ${C_DIM}↑/↓ or j/k move · Enter select · ←/Esc/b back · q quit${C_RESET}"
    else
        echo -e "  ${C_DIM}↑/↓ or j/k move · Enter select · q quit${C_RESET}"
    fi
    echo ""

    # Draw function
    _tui_draw() {
        local i
        for ((i=0; i<count; i++)); do
            printf '\033[2K'
            if ((i == selected)); then
                echo -e "  ${C_ACCENT}❯${C_RESET} ${C_BOLD}${C_WHITE}${options[$i]}${C_RESET}"
            else
                echo -e "    ${C_DIM}${options[$i]}${C_RESET}"
            fi
        done
    }

    _tui_draw

    while true; do
        local key
        IFS= read -rsn1 key || {
            tput cnorm 2>/dev/null || true
            echo ""
            return 2
        }

        case "$key" in
            $'\x1b')
                local seq
                IFS= read -rsn2 -t 0.1 seq || true
                case "$seq" in
                    '[A') ((selected > 0)) && ((selected--)) || true ;;
                    '[B') ((selected < count - 1)) && ((selected++)) || true ;;
                    '[D')
                        if $allow_back; then
                            tput cnorm 2>/dev/null || true
                            echo ""
                            return 2
                        fi
                        ;;
                esac
                ;;
            $'\x7f'|b|B)
                if $allow_back; then
                    tput cnorm 2>/dev/null || true
                    echo ""
                    return 2
                fi
                ;;
            k) ((selected > 0)) && ((selected--)) || true ;;
            j) ((selected < count - 1)) && ((selected++)) || true ;;
            '')
                tput cnorm 2>/dev/null || true
                _TUI_SELECTED=$selected
                echo ""
                return 0
                ;;
            q)
                tput cnorm 2>/dev/null || true
                echo ""
                return 3
                ;;
        esac

        printf '\033[%dA' "$count"
        _tui_draw
    done
}

###############################################################################
# TUI: Select App
###############################################################################

# Shows a tui_select menu with all deployed apps + "Enter manually..." option.
# Sets _TUI_APP_SELECTED to the chosen app name, or empty string on cancel.
tui_select_app() {
    local title="${1:-Select App}"
    _TUI_APP_SELECTED=""

    local apps_raw
    apps_raw=$(dokku_list_apps 2>/dev/null) || true

    local apps=()
    if [[ -n "$apps_raw" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && apps+=("$line")
        done <<< "$apps_raw"
    fi

    if [[ ${#apps[@]} -eq 0 ]]; then
        # No apps found — fall back to manual entry
        tui_read _TUI_APP_SELECTED "App name" "" false
        return $?
    fi

    local options=()
    local i
    for i in "${apps[@]}"; do
        options+=("$i")
    done
    options+=("Enter manually...")

    local select_rc=0
    if tui_select "$title" "${options[@]}"; then
        select_rc=0
    else
        select_rc=$?
    fi
    case "$select_rc" in
        0) ;;
        2|3) return "$select_rc" ;;
        *) return 2 ;;
    esac

    if (( _TUI_SELECTED == ${#apps[@]} )); then
        # "Enter manually..." was selected
        tui_read _TUI_APP_SELECTED "App name" "" false
        return $?
    else
        _TUI_APP_SELECTED="${apps[$_TUI_SELECTED]}"
    fi
    return 0
}

###############################################################################
# Interactive Menu
###############################################################################

interactive_menu() {
    while true; do
        local menu_rc=0
        if tui_select --no-back "Ferry" \
            "Status       System dashboard" \
            "List         Quick app list" \
            "New          Create app from template" \
            "Deploy       Deploy a new app" \
            "Remove       Remove an app" \
            "Prune        Reconcile orphan ingress" \
            "Reload       Validate + restart cloudflared" \
            "Rebuild      Rebuild a Dokku app" \
            "Tune         Adjust memory limits + Node heap" \
            "Logs         Tail app logs" \
            "Help         Usage information" \
            "Login        Cloudflare API setup" \
            "Quit"; then
            menu_rc=0
        else
            menu_rc=$?
        fi

        case "$menu_rc" in
            2) continue ;;
            3) echo ""; dim "Bye!"; return 0 ;;
        esac

        case "$_TUI_SELECTED" in
            0)
                if cmd_status; then
                    :
                else
                    case $? in
                        3) return 0 ;;
                        *) warn "Status check failed." ;;
                    esac
                fi
                ;;
            1)
                if cmd_list; then
                    :
                else
                    case $? in
                        3) return 0 ;;
                        *) warn "List failed." ;;
                    esac
                fi
                ;;
            2)
                if cmd_new; then
                    :
                else
                    case $? in
                        3) return 0 ;;
                        *) warn "New app creation failed." ;;
                    esac
                fi
                ;;
            3)
                if cmd_deploy; then
                    :
                else
                    case $? in
                        3) return 0 ;;
                        *) warn "Deploy failed — you can try again." ;;
                    esac
                fi
                ;;
            4)
                if cmd_remove; then
                    :
                else
                    case $? in
                        3) return 0 ;;
                        *) warn "Remove failed — you can try again." ;;
                    esac
                fi
                ;;
            5)
                if cmd_prune; then
                    :
                else
                    case $? in
                        3) return 0 ;;
                        *) warn "Prune failed — you can try again." ;;
                    esac
                fi
                ;;
            6)
                if cmd_reload; then
                    :
                else
                    case $? in
                        3) return 0 ;;
                        *) warn "Reload failed — you can try again." ;;
                    esac
                fi
                ;;
            7)
                if tui_select_app "Rebuild App"; then
                    if [[ -n "$_TUI_APP_SELECTED" ]]; then
                        if cmd_rebuild "$_TUI_APP_SELECTED"; then
                            :
                        else
                            case $? in
                                3) return 0 ;;
                                *) warn "Rebuild failed." ;;
                            esac
                        fi
                    else
                        warn "Rebuild failed."
                    fi
                else
                    case $? in
                        2) continue ;;
                        3) echo ""; dim "Bye!"; return 0 ;;
                    esac
                fi
                ;;
            8)
                if cmd_tune; then
                    :
                else
                    case $? in
                        3) return 0 ;;
                        *) warn "Tune failed — you can try again." ;;
                    esac
                fi
                ;;
            9)
                if tui_select_app "Tail Logs"; then
                    if [[ -n "$_TUI_APP_SELECTED" ]]; then
                        if cmd_logs "$_TUI_APP_SELECTED"; then
                            :
                        else
                            case $? in
                                3) return 0 ;;
                                *) warn "Logs failed." ;;
                            esac
                        fi
                    else
                        warn "Logs failed."
                    fi
                else
                    case $? in
                        2) continue ;;
                        3) echo ""; dim "Bye!"; return 0 ;;
                    esac
                fi
                ;;
            10) if cmd_help; then :; else :; fi ;;
            11)
                if cmd_login; then
                    :
                else
                    case $? in
                        3) return 0 ;;
                        *) warn "Login failed — you can try again." ;;
                    esac
                fi
                ;;
            12) echo ""; dim "Bye!"; return 0 ;;
        esac
    done
}

###############################################################################
# Main
###############################################################################

###############################################################################
# Initialization (called by main, not at source time — enables test sourcing)
###############################################################################

_ferry_init() {
    # Load .env
    if [[ -f "$ENV_FILE" ]]; then
        set -a
        # shellcheck source=/dev/null
        source "$ENV_FILE"
        set +a
    fi

    TUNNEL_ID="${TUNNEL_ID:-}"
    TUNNEL_TOKEN="${TUNNEL_TOKEN:-}"
    CF_API_TOKEN="${CF_API_TOKEN:-}"
    CF_ACCOUNT_ID="${CF_ACCOUNT_ID:-}"
    DOKKU_HOSTNAME="${DOKKU_HOSTNAME:-}"

    # Declare associative array for zone ID caching
    declare -gA _zone_id_cache

    # Set up signal handlers
    trap cleanup INT TERM
}

main() {
    _ferry_init
    ferry_intro

    local command=""
    local args=()
    local rc=0

    # Parse global flags and collect remaining args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes) YES=true; shift ;;
            *)        args+=("$1"); shift ;;
        esac
    done

    command="${args[0]:-}"
    # Remove first element (command) from args
    if [[ ${#args[@]} -gt 0 ]]; then
        args=("${args[@]:1}")
    fi

    case "$command" in
        new)
            if cmd_new "${args[@]+"${args[@]}"}"; then rc=0; else rc=$?; fi
            ;;
        login)
            if cmd_login "${args[@]+"${args[@]}"}"; then rc=0; else rc=$?; fi
            ;;
        deploy)
            if cmd_deploy "${args[@]+"${args[@]}"}"; then rc=0; else rc=$?; fi
            ;;
        remove)
            if cmd_remove "${args[@]+"${args[@]}"}"; then rc=0; else rc=$?; fi
            ;;
        prune)
            if cmd_prune "${args[@]+"${args[@]}"}"; then rc=0; else rc=$?; fi
            ;;
        status)
            if cmd_status; then rc=0; else rc=$?; fi
            ;;
        list)
            if cmd_list; then rc=0; else rc=$?; fi
            ;;
        reload)
            if cmd_reload; then rc=0; else rc=$?; fi
            ;;
        rebuild)
            if cmd_rebuild "${args[@]+"${args[@]}"}"; then rc=0; else rc=$?; fi
            ;;
        tune)
            if cmd_tune "${args[@]+"${args[@]}"}"; then rc=0; else rc=$?; fi
            ;;
        logs)
            if cmd_logs "${args[@]+"${args[@]}"}"; then rc=0; else rc=$?; fi
            ;;
        help|-h|--help)
            if cmd_help; then rc=0; else rc=$?; fi
            ;;
        "")
            if interactive_menu; then rc=0; else rc=$?; fi
            ;;
        *)
            error "Unknown command: $command"
            cmd_help
            rc=1
            ;;
    esac

    if (( rc == 3 )); then
        exit 0
    fi
    return "$rc"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
