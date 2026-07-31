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

# ---------------------------------------------------------------------------
# Explicit noninteractive tunnel selection
# ---------------------------------------------------------------------------

@test "explicit name creates instead of binding a sole mismatched tunnel under -y" {
    YES=true
    TUNNEL_ID=""
    TUNNEL_TOKEN=""
    ENV_FILE="$BATS_TEST_TMPDIR/.env"
    CF_CALL_LOG="$BATS_TEST_TMPDIR/cf-calls"
    : > "$ENV_FILE"
    : > "$CF_CALL_LOG"
    cf_api() {
        printf '%s %s\n' "$1" "$2" >> "$CF_CALL_LOG"
        if [[ "$1" == "GET" && "$2" == *'?is_deleted=false&per_page=50' ]]; then
            echo '{"success":true,"errors":[],"result":[{"id":"other-id","name":"rpi5","deleted_at":null}]}'
        elif [[ "$1" == "POST" && "$2" == "/accounts/acct-test/cfd_tunnel" ]]; then
            echo '{"success":true,"errors":[],"result":{"id":"preferred-id","name":"beta","token":"created-token"}}'
        else
            echo '{"success":false,"errors":[{"message":"unexpected"}]}'
        fi
    }
    _cf_maybe_restart_cloudflared() { return 0; }

    run cf_ensure_tunnel "beta" true

    assert_success
    grep -q '^TUNNEL_ID=preferred-id$' "$ENV_FILE"
    grep -q '^TUNNEL_TOKEN=created-token$' "$ENV_FILE"
    grep -q '^POST /accounts/acct-test/cfd_tunnel$' "$CF_CALL_LOG"
    ! grep -q '/cfd_tunnel/other-id/token$' "$CF_CALL_LOG"
}

@test "explicit name creates instead of choosing among multiple mismatched tunnels under -y" {
    YES=true
    TUNNEL_ID=""
    TUNNEL_TOKEN=""
    ENV_FILE="$BATS_TEST_TMPDIR/.env"
    CF_CALL_LOG="$BATS_TEST_TMPDIR/cf-calls"
    : > "$ENV_FILE"
    : > "$CF_CALL_LOG"
    cf_api() {
        printf '%s %s\n' "$1" "$2" >> "$CF_CALL_LOG"
        if [[ "$1" == "GET" && "$2" == *'?is_deleted=false&per_page=50' ]]; then
            echo '{"success":true,"errors":[],"result":[{"id":"first-id","name":"rpi5","deleted_at":null},{"id":"second-id","name":"other","deleted_at":null}]}'
        elif [[ "$1" == "POST" && "$2" == "/accounts/acct-test/cfd_tunnel" ]]; then
            echo '{"success":true,"errors":[],"result":{"id":"preferred-id","name":"beta","token":"created-token"}}'
        else
            echo '{"success":false,"errors":[{"message":"unexpected"}]}'
        fi
    }
    _cf_maybe_restart_cloudflared() { return 0; }

    run cf_ensure_tunnel "beta" true

    assert_success
    grep -q '^TUNNEL_ID=preferred-id$' "$ENV_FILE"
    grep -q '^POST /accounts/acct-test/cfd_tunnel$' "$CF_CALL_LOG"
    ! grep -q '/cfd_tunnel/first-id/token$' "$CF_CALL_LOG"
    ! grep -q '/cfd_tunnel/second-id/token$' "$CF_CALL_LOG"
}

@test "explicit name binds its exact active tunnel under -y" {
    YES=true
    TUNNEL_ID=""
    TUNNEL_TOKEN=""
    ENV_FILE="$BATS_TEST_TMPDIR/.env"
    CF_CALL_LOG="$BATS_TEST_TMPDIR/cf-calls"
    : > "$ENV_FILE"
    : > "$CF_CALL_LOG"
    cf_api() {
        printf '%s %s\n' "$1" "$2" >> "$CF_CALL_LOG"
        if [[ "$1" == "GET" && "$2" == *'?is_deleted=false&per_page=50' ]]; then
            echo '{"success":true,"errors":[],"result":[{"id":"other-id","name":"rpi5","deleted_at":null},{"id":"preferred-id","name":"beta","deleted_at":null}]}'
        elif [[ "$1" == "GET" && "$2" == "/accounts/acct-test/cfd_tunnel/preferred-id/token" ]]; then
            echo '{"success":true,"errors":[],"result":"matched-token"}'
        elif [[ "$1" == "POST" && "$2" == "/accounts/acct-test/cfd_tunnel" ]]; then
            echo '{"success":false,"errors":[{"message":"must not create"}]}'
        else
            echo '{"success":false,"errors":[{"message":"unexpected"}]}'
        fi
    }
    _cf_maybe_restart_cloudflared() { return 0; }

    run cf_ensure_tunnel "beta" true

    assert_success
    grep -q '^TUNNEL_ID=preferred-id$' "$ENV_FILE"
    grep -q '^TUNNEL_TOKEN=matched-token$' "$ENV_FILE"
    ! grep -q '^POST ' "$CF_CALL_LOG"
}

@test "explicit name reconfigures a configured foreign tunnel ID" {
    YES=true
    TUNNEL_ID="foreign-id"
    TUNNEL_TOKEN="foreign-token"
    export TUNNEL_ID TUNNEL_TOKEN
    ENV_FILE="$BATS_TEST_TMPDIR/.env"
    CF_CALL_LOG="$BATS_TEST_TMPDIR/cf-calls"
    : > "$ENV_FILE"
    : > "$CF_CALL_LOG"
    cf_api() {
        printf '%s %s\n' "$1" "$2" >> "$CF_CALL_LOG"
        if [[ "$1" == "GET" && "$2" == "/accounts/acct-test/cfd_tunnel/foreign-id" ]]; then
            echo '{"success":true,"errors":[],"result":{"id":"foreign-id","name":"rpi5","deleted_at":null}}'
        elif [[ "$1" == "GET" && "$2" == *'?is_deleted=false&per_page=50' ]]; then
            echo '{"success":true,"errors":[],"result":[]}'
        elif [[ "$1" == "POST" && "$2" == "/accounts/acct-test/cfd_tunnel" ]]; then
            echo '{"success":true,"errors":[],"result":{"id":"preferred-id","name":"beta","token":"created-token"}}'
        else
            echo '{"success":false,"errors":[{"message":"unexpected"}]}'
        fi
    }
    _cf_maybe_restart_cloudflared() { return 0; }

    run cf_ensure_tunnel "beta" true

    assert_success
    grep -q '^TUNNEL_ID=preferred-id$' "$ENV_FILE"
    grep -q '^TUNNEL_TOKEN=created-token$' "$ENV_FILE"
    grep -q '^GET /accounts/acct-test/cfd_tunnel/foreign-id$' "$CF_CALL_LOG"
    grep -q '^POST /accounts/acct-test/cfd_tunnel$' "$CF_CALL_LOG"
}
