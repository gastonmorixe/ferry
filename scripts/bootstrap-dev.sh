#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

info() { printf '==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
error() { printf 'ERROR: %s\n' "$*" >&2; }

missing=0

check_cmd() {
    local cmd="$1" hint="$2"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        error "Missing required command: $cmd"
        printf '      %s\n' "$hint" >&2
        missing=1
    fi
}

check_optional_cmd() {
    local cmd="$1" note="$2"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        warn "Optional command missing: $cmd ($note)"
    fi
}

info "Initializing git submodules"
git -C "$ROOT_DIR" submodule update --init --recursive

info "Checking required development tools"
check_cmd git "Install git from your package manager."
check_cmd make "Install GNU make from your package manager."
check_cmd jq "Install jq from your package manager."
check_cmd python3 "Install Python 3 from your package manager."
check_cmd bats "Install bats-core from your package manager or https://github.com/bats-core/bats-core."
check_cmd shellcheck "Install ShellCheck from your package manager or https://www.shellcheck.net."

if ! python3 -c 'import yaml' >/dev/null 2>&1; then
    if python3 -m pip --version >/dev/null 2>&1; then
        info "Installing Python development dependencies"
        python3 -m pip install -r "$ROOT_DIR/requirements-dev.txt"
    else
        error "PyYAML is missing and python3 -m pip is unavailable"
        error "Install pip for Python 3, then run: python3 -m pip install -r requirements-dev.txt"
        missing=1
    fi
fi

check_optional_cmd docker "required for deploy/status/reload/remove flows"
check_optional_cmd gh "required for ferry deploy --repo clone flows"

if ((missing)); then
    error "Development environment check failed"
    exit 1
fi

info "Development environment is ready"
