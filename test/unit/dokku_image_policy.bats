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

@test "Ferry release version is 0.12.6" {
    assert_equal "$FERRY_VERSION" "0.12.6"
}

@test "ferry clears Dokku global VHOST during health wait" {
    run grep -F 'dokku_ensure_no_global_vhost' "$FERRY_ROOT/ferry.sh"
    assert_success

    run grep -F 'domains:clear-global' "$FERRY_ROOT/ferry.sh"
    assert_success
}

@test "ferry deploy removes A/AAAA before tunnel CNAME" {
    run grep -F 'cf_dns_delete_records_by_type' "$FERRY_ROOT/ferry.sh"
    assert_success

    run grep -F 'cf_dns_delete_records_by_type "$hostname" "A"' "$FERRY_ROOT/ferry.sh"
    assert_success
}
