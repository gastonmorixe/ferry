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

@test "Ferry release version is 0.12.4" {
    assert_equal "$FERRY_VERSION" "0.12.4"
}
