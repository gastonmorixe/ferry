#!/usr/bin/env bats
# shellcheck disable=SC2034

setup() {
    load '../test_helper/common'
}

@test "compose tracks Dokku current stable and documents the later digest gate" {
    run grep -F 'image: dokku/dokku:latest' "$COMPOSE_FILE"
    assert_success

    run grep -F 'immutable digest in the target BOM immediately before any VM compose apply' "$COMPOSE_FILE"
    assert_success
}

@test "compose healthcheck is domain-free (nginx :80 + /_dokku/health)" {
    run grep -F '_dokku/health' "$COMPOSE_FILE"
    assert_success

    run grep -E 'ss -ltn' "$COMPOSE_FILE"
    assert_success

    run grep -F 'FERRY_HEALTHCHECK_HOST' "$COMPOSE_FILE"
    assert_failure

    run grep -E 'Host: \$FERRY_HEALTHCHECK_HOST|Host: localhost' "$COMPOSE_FILE"
    assert_failure
}

@test "compose does not pin a global DOKKU_HOSTNAME" {
    run grep -E '^\s+hostname:' "$COMPOSE_FILE"
    assert_failure

    run grep -E 'DOKKU_HOSTNAME:' "$COMPOSE_FILE"
    assert_failure
}

@test "Ferry release version is 0.12.5" {
    assert_equal "$FERRY_VERSION" "0.12.5"
}
