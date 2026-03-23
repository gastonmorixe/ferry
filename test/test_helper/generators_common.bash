#!/usr/bin/env bash
# test/test_helper/generators_common.bash — Shared setup for generator tests

FERRY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Load bats libraries
load "${FERRY_ROOT}/test/test_helper/bats-support/load"
load "${FERRY_ROOT}/test/test_helper/bats-assert/load"
load "${FERRY_ROOT}/test/test_helper/bats-file/load"

export SCRIPT_DIR="$FERRY_ROOT"
export GENERATORS_DIR="$FERRY_ROOT/generators"
export SHARED_DIR="$FERRY_ROOT/generators/_shared"
export FERRY_VERSION="0.5.1-test"
export _COLOR_TIER=0

# Source helpers for detect_app_port
export ENV_FILE="$BATS_TEST_TMPDIR/.env"
export CERT_DIR="$BATS_TEST_TMPDIR/certs"
export CONFIG_FILE="$BATS_TEST_TMPDIR/config.yml"
mkdir -p "$CERT_DIR"
source "$FERRY_ROOT/ferry"

# Run a generator and return the output dir path via $_GEN_OUT
# Usage: run_generator <id> <name> <port>
run_generator() {
    local id="$1" name="$2" port="$3"
    _GEN_OUT="$BATS_TEST_TMPDIR/$name"
    mkdir -p "$_GEN_OUT"
    APP_NAME="$name" APP_PORT="$port" OUTPUT_DIR="$_GEN_OUT" \
        SHARED_DIR="$SHARED_DIR" FERRY_VERSION="$FERRY_VERSION" \
        bash "$GENERATORS_DIR/$id/generate.sh"
}
