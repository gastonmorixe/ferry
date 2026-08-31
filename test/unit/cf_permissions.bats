#!/usr/bin/env bats

setup() {
    load '../test_helper/common'
    CF_ACCOUNT_ID="acct-test"
    TUNNEL_ID=""
    export CF_ACCOUNT_ID TUNNEL_ID
}

@test "cf_check_permissions passes when list and config probes succeed" {
    cf_api() {
        case "$2" in
            /zones*)
                echo '{"success":true,"result":[{"id":"z1","name":"example.com","status":"active"}],"result_info":{"total_count":1}}'
                ;;
            /zones/z1/dns_records*)
                echo '{"success":true,"result":[]}'
                ;;
            /accounts/acct-test/cfd_tunnel?per_page*)
                echo '{"success":true,"result":[{"id":"tid-1","name":"ferry"}]}'
                ;;
            /accounts/acct-test/cfd_tunnel/tid-1/configurations)
                echo '{"success":true,"result":{"config":{"ingress":[{"service":"http_status:404"}]}}}'
                ;;
            *)
                echo '{"success":false,"errors":[{"message":"unexpected '"$2"'"}]}'
                ;;
        esac
    }
    run cf_check_permissions
    assert_success
    [[ "$output" == *"Tunnel:Read"* ]]
    [[ "$output" == *"Tunnel:Edit"* ]]
}

@test "cf_check_permissions fails edit when list succeeds but config is denied" {
    TUNNEL_ID="tid-1"
    export TUNNEL_ID
    cf_api() {
        case "$2" in
            /zones*)
                echo '{"success":true,"result":[{"id":"z1","name":"example.com","status":"active"}],"result_info":{"total_count":1}}'
                ;;
            /zones/z1/dns_records*)
                echo '{"success":true,"result":[]}'
                ;;
            /accounts/acct-test/cfd_tunnel?per_page*)
                echo '{"success":true,"result":[]}'
                ;;
            /accounts/acct-test/cfd_tunnel/tid-1/configurations)
                echo '{"success":false,"errors":[{"code":1001,"message":"Not authorized"}]}'
                ;;
            *)
                echo '{"success":false,"errors":[{"message":"unexpected '"$2"'"}]}'
                ;;
        esac
    }
    run cf_check_permissions
    assert_failure
    [[ "$output" == *"Tunnel:Read"* ]]
    [[ "$output" == *"Tunnel:Edit"* ]]
    [[ "$output" == *"cannot read tunnel config"* ]]
}

@test "tunnel_ingress_fetch caches a single API response" {
    CF_ACCOUNT_ID="acct-test"
    TUNNEL_ID="tid-1"
    export CF_ACCOUNT_ID TUNNEL_ID
    CF_CALLS="$BATS_TEST_TMPDIR/cf-calls"
    : > "$CF_CALLS"
    cf_api() {
        printf '%s %s\n' "$1" "$2" >> "$CF_CALLS"
        echo '{"success":true,"result":{"config":{"ingress":[{"hostname":"app.example.com","service":"http://dokku:80"},{"service":"http_status:404"}]}}}'
    }
    tunnel_ingress_reset_cache
    tunnel_ingress_fetch
    tunnel_ingress_fetch
    assert_equal "$(wc -l < "$CF_CALLS" | tr -d ' ')" "1"
}

@test "yaml_has_hostname returns unknown when ingress fetch fails" {
    CF_ACCOUNT_ID="acct-test"
    TUNNEL_ID="tid-1"
    export CF_ACCOUNT_ID TUNNEL_ID
    cf_api() {
        echo '{"success":false,"errors":[{"code":1001,"message":"Not authorized"}]}'
    }
    tunnel_ingress_reset_cache
    run yaml_has_hostname "app.example.com"
    assert_failure
    assert_output "unknown"
}
