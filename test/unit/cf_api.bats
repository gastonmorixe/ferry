#!/usr/bin/env bats

setup() {
    load '../test_helper/common'
}

# ---------------------------------------------------------------------------
# cf_api_ok
# ---------------------------------------------------------------------------

@test "cf_api_ok returns 0 for success response" {
    local json='{"success":true,"errors":[],"result":{}}'
    run cf_api_ok "$json"
    assert_success
}

@test "cf_api_ok returns 1 for failure response" {
    local json='{"success":false,"errors":[{"message":"Invalid token"}]}'
    run cf_api_ok "$json"
    assert_failure
}

@test "cf_api_ok returns 1 for malformed JSON" {
    run cf_api_ok "not-json-at-all"
    assert_failure
}

@test "cf_api_ok returns 1 for empty string" {
    run cf_api_ok ""
    assert_failure
}

# ---------------------------------------------------------------------------
# cf_api_error
# ---------------------------------------------------------------------------

@test "cf_api_error extracts error message" {
    local json='{"success":false,"errors":[{"message":"Authentication error"}]}'
    run cf_api_error "$json"
    assert_success
    assert_output "Authentication error"
}

@test "cf_api_error returns unknown for missing errors key" {
    local json='{"success":false}'
    run cf_api_error "$json"
    assert_success
    assert_output "unknown error"
}

@test "cf_api_error returns unknown for empty errors array" {
    local json='{"success":false,"errors":[]}'
    run cf_api_error "$json"
    assert_success
    assert_output "unknown error"
}
