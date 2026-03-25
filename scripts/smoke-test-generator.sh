#!/usr/bin/env bash
# scripts/smoke-test-generator.sh — Build and HTTP-test a single generator
# Usage: ./scripts/smoke-test-generator.sh <generator-id> <port>
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

GEN_ID="$1"
PORT="$2"
OUTDIR=$(mktemp -d)
IMAGE_TAG="ferry-smoke-${GEN_ID}-$$"

cleanup() {
    docker stop "$CONTAINER_ID" >/dev/null 2>&1 || true
    docker rm -f "$CONTAINER_ID" >/dev/null 2>&1 || true
    docker image rm -f "$IMAGE_TAG" >/dev/null 2>&1 || true
    rm -rf "$OUTDIR"
}
trap cleanup EXIT

# Generate
APP_NAME="smoke-${GEN_ID}" APP_PORT="$PORT" OUTPUT_DIR="$OUTDIR" \
    SHARED_DIR="$ROOT_DIR/generators/_shared" FERRY_VERSION="ci-test" \
    bash "$ROOT_DIR/generators/$GEN_ID/generate.sh"

# Build
printf '==> Building %s ...\n' "$GEN_ID"
docker build -t "$IMAGE_TAG" "$OUTDIR"

# Run
printf '==> Starting %s ...\n' "$GEN_ID"
CONTAINER_ID=$(docker run -d --init -P "$IMAGE_TAG")

HOST_PORT=$(docker port "$CONTAINER_ID" "$PORT" | head -1 | sed 's/.*://')

# Probe
printf '==> Waiting for HTTP 200 on port %s ...\n' "$HOST_PORT"
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
    --retry 20 --retry-all-errors --retry-delay 2 \
    --retry-max-time 60 --max-time 5 \
    "http://localhost:${HOST_PORT}/")

if [[ "$HTTP_CODE" == "200" ]]; then
    printf '✓ %s → HTTP %s\n' "$GEN_ID" "$HTTP_CODE"
else
    printf '✗ %s → HTTP %s (expected 200)\n' "$GEN_ID" "$HTTP_CODE" >&2
    docker logs --tail 30 "$CONTAINER_ID" >&2 || true
    exit 1
fi
