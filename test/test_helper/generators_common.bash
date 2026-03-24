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

require_docker_for_smoke_tests() {
    if ! command -v docker >/dev/null 2>&1; then
        skip "docker is required for generator smoke tests"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "docker daemon is not available for generator smoke tests"
    fi
}

docker_build_generated_app() {
    local generator_id="$1"
    local image_tag="ferry-test-${generator_id}-${RANDOM}"
    local log_file="$BATS_TEST_TMPDIR/${generator_id}-docker-build.log"

    if ! docker build -t "$image_tag" "$_GEN_OUT" >"$log_file" 2>&1; then
        printf 'docker build failed for %s\n' "$generator_id" >&3
        tail -n 80 "$log_file" >&3
        return 1
    fi

    docker image rm -f "$image_tag" >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# Runtime HTTP smoke test helpers
# ---------------------------------------------------------------------------

# Globals for tracking containers/images to clean up
_TEST_CONTAINERS=()
_TEST_IMAGES=()

# Build + start a generated app in Docker, exporting container ID and host port.
# Sets: _CONTAINER_ID, _CONTAINER_PORT
# Usage: docker_run_generated_app <generator_id> <container_port>
docker_run_generated_app() {
    local generator_id="$1"
    local container_port="$2"
    local image_tag="ferry-test-${generator_id}-$$"
    local log_file="$BATS_TEST_TMPDIR/${generator_id}-build.log"

    # Build image
    if ! docker build -t "$image_tag" "$_GEN_OUT" >"$log_file" 2>&1; then
        printf 'docker build failed for %s\n' "$generator_id" >&3
        tail -n 80 "$log_file" >&3
        return 1
    fi
    _TEST_IMAGES+=("$image_tag")

    # Start container with: detach, PID 1 init, random host port
    local container_id
    container_id=$(docker run -d --init -P "$image_tag") || return 1
    _TEST_CONTAINERS+=("$container_id")

    # Get the mapped host port
    local host_port
    host_port=$(docker port "$container_id" "$container_port" 2>/dev/null | head -1 | sed 's/.*://') || return 1

    if [[ -z "$host_port" ]]; then
        printf 'no mapped port for %s (container port %s)\n' "$generator_id" "$container_port" >&3
        return 1
    fi

    _CONTAINER_ID="$container_id"
    _CONTAINER_PORT="$host_port"
}

# Probe a URL with retries until it responds. Returns the HTTP status code.
# Usage: wait_for_http_200 <url> [max_attempts] [delay_seconds]
wait_for_http_200() {
    local url="$1"
    local max_attempts="${2:-20}"
    local delay="${3:-2}"

    curl -s -o /dev/null -w '%{http_code}' \
        --retry "$max_attempts" \
        --retry-all-errors \
        --retry-delay "$delay" \
        --retry-max-time 60 \
        --max-time 5 \
        "$url"
}

# Stop and remove all tracked containers and images.
# Safe to call multiple times.
cleanup_test_containers() {
    local cid img
    for cid in "${_TEST_CONTAINERS[@]}"; do
        docker stop "$cid" >/dev/null 2>&1 || true
        docker rm -f "$cid" >/dev/null 2>&1 || true
    done
    for img in "${_TEST_IMAGES[@]}"; do
        docker image rm -f "$img" >/dev/null 2>&1 || true
    done
    _TEST_CONTAINERS=()
    _TEST_IMAGES=()
}
