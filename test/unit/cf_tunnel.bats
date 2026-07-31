#!/usr/bin/env bats

setup() {
    load '../test_helper/common'
    CF_ACCOUNT_ID="acct-test"
    export CF_ACCOUNT_ID
}

# ---------------------------------------------------------------------------
# cf_tunnel_get_token
# ---------------------------------------------------------------------------

@test "cf_tunnel_get_token parses string result" {
    cf_api() {
        echo '{"success":true,"errors":[],"result":"eyJtoken"}'
    }
    run cf_tunnel_get_token "tid-1"
    assert_success
    assert_output "eyJtoken"
}

@test "cf_tunnel_get_token parses object token result" {
    cf_api() {
        echo '{"success":true,"errors":[],"result":{"token":"eyJobj"}}'
    }
    run cf_tunnel_get_token "tid-2"
    assert_success
    assert_output "eyJobj"
}

@test "cf_tunnel_get_token fails on API error" {
    cf_api() {
        echo '{"success":false,"errors":[{"message":"denied"}]}'
    }
    run cf_tunnel_get_token "tid-3"
    assert_failure
}

# ---------------------------------------------------------------------------
# cf_tunnel_create
# ---------------------------------------------------------------------------

@test "cf_tunnel_create returns id name token from create response" {
    cf_api() {
        echo '{"success":true,"errors":[],"result":{"id":"abc","name":"ferry","token":"tok123"}}'
    }
    run cf_tunnel_create "ferry"
    assert_success
    assert_output $'abc\tferry\ttok123'
}

@test "cf_ensure_tunnel keeps valid existing TUNNEL_ID and TUNNEL_TOKEN" {
    TUNNEL_ID="existing-id"
    TUNNEL_TOKEN="existing-token"
    export TUNNEL_ID TUNNEL_TOKEN
    cf_api() {
        case "$2" in
            */cfd_tunnel/existing-id)
                echo '{"success":true,"errors":[],"result":{"id":"existing-id","name":"ferry","deleted_at":null}}'
                ;;
            *)
                echo '{"success":false,"errors":[{"message":"unexpected"}]}'
                ;;
        esac
    }
    _cf_maybe_restart_cloudflared() { return 0; }
    run cf_ensure_tunnel "ferry"
    assert_success
    [[ "$output" == *"Host tunnel ready"* ]]
}

@test "cf_ensure_tunnel fetches missing TUNNEL_TOKEN for existing TUNNEL_ID" {
    TUNNEL_ID="only-id"
    TUNNEL_TOKEN=""
    export TUNNEL_ID TUNNEL_TOKEN
    ENV_FILE="$BATS_TEST_TMPDIR/.env"
    : > "$ENV_FILE"
    cf_api() {
        case "$2" in
            */token)
                echo '{"success":true,"errors":[],"result":"fetched-token"}'
                ;;
            *)
                echo '{"success":false,"errors":[{"message":"unexpected '"$2"'"}]}'
                ;;
        esac
    }
    _cf_maybe_restart_cloudflared() { return 0; }
    run cf_ensure_tunnel "ferry"
    assert_success
    grep -q '^TUNNEL_TOKEN=fetched-token$' "$ENV_FILE"
}
