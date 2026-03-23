#!/usr/bin/env bash
# test/test_helper/common.bash — Shared setup for all ferry bats tests

FERRY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Load bats libraries
load "${FERRY_ROOT}/test/test_helper/bats-support/load"
load "${FERRY_ROOT}/test/test_helper/bats-assert/load"
load "${FERRY_ROOT}/test/test_helper/bats-file/load"

# Disable colors and interactive features for testing
export _COLOR_TIER=0
export _IS_TTY=false
export YES=false

# Override paths to avoid touching real config
export SCRIPT_DIR="$FERRY_ROOT"
export ENV_FILE="$BATS_TEST_TMPDIR/.env"
export CERT_DIR="$BATS_TEST_TMPDIR/certs"
export CONFIG_FILE="$BATS_TEST_TMPDIR/config.yml"
export COMPOSE_FILE="$FERRY_ROOT/docker-compose.yml"
export GENERATORS_DIR="$FERRY_ROOT/generators"

# Create temp dirs
mkdir -p "$CERT_DIR"

# Source ferry (safe — source guard prevents main() from running)
source "$FERRY_ROOT/ferry"
