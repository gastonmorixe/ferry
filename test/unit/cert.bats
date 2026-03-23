#!/usr/bin/env bats

setup() {
    load '../test_helper/common'
    # common.bash sets CERT_DIR="$BATS_TEST_TMPDIR/certs" and mkdir -p's it,
    # but BATS_TEST_TMPDIR is shared across tests within this file.
    # Wipe and recreate so every test starts with an empty cert directory.
    rm -rf "$CERT_DIR"
    mkdir -p "$CERT_DIR"
}

# ---------------------------------------------------------------------------
# cert_find_for_hostname
# ---------------------------------------------------------------------------

@test "cert_find_for_hostname finds cert for exact TLD+1 match" {
    # cert_find_for_hostname strips labels from the left until it finds a match.
    # For a 2-label hostname like "example.com" the only candidate stripped to
    # is "com" — so we use a 3-label hostname to get "example.com" as a candidate.
    touch "$CERT_DIR/example.com.cert"
    run cert_find_for_hostname "app.example.com"
    assert_success
    assert_output "${CERT_DIR}/example.com.cert example.com"
}

@test "cert_find_for_hostname walks up one level for subdomain" {
    touch "$CERT_DIR/example.com.cert"
    run cert_find_for_hostname "shop.example.com"
    assert_success
    assert_output "${CERT_DIR}/example.com.cert example.com"
}

@test "cert_find_for_hostname walks up multiple levels for deep subdomain" {
    touch "$CERT_DIR/example.com.cert"
    run cert_find_for_hostname "sub.app.example.com"
    assert_success
    assert_output "${CERT_DIR}/example.com.cert example.com"
}

@test "cert_find_for_hostname finds cert for 2-label hostname (example.com)" {
    touch "$CERT_DIR/example.com.cert"
    run cert_find_for_hostname "example.com"
    assert_success
    assert_output "${CERT_DIR}/example.com.cert example.com"
}

@test "cert_find_for_hostname returns failure when no cert matches" {
    run cert_find_for_hostname "unknown.org"
    assert_failure
}

@test "cert_find_for_hostname returns failure and no output when no cert matches" {
    run cert_find_for_hostname "deep.sub.unknown.org"
    assert_failure
    assert_output ""
}

# ---------------------------------------------------------------------------
# cert_list_zones
# ---------------------------------------------------------------------------

@test "cert_list_zones lists zone names from cert files" {
    touch "$CERT_DIR/example.com.cert"
    touch "$CERT_DIR/another.io.cert"
    run cert_list_zones
    assert_success
    # Output lines may arrive in any filesystem order — assert each is present
    assert_line "example.com"
    assert_line "another.io"
}

@test "cert_list_zones produces no output for empty cert directory" {
    run cert_list_zones
    # The for-loop [[ -f ]] guard short-circuits on the glob non-match,
    # so the function exits 0 and prints nothing.
    assert_output ""
}
