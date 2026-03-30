#!/usr/bin/env bats

setup() {
    load '../test_helper/common'
    export TUNNEL_ID="test-tunnel-id"
    export CF_ACCOUNT_ID="test-account-id"
    export CF_API_TOKEN="test-token"

    # Mock ingress state
    _MOCK_INGRESS="$BATS_TEST_TMPDIR/ingress.json"
    echo '[{"service":"http_status:404"}]' > "$_MOCK_INGRESS"
}

docker() {
    if [[ "$1" == "info" ]]; then
        return 0
    fi

    if [[ "$1" == "compose" ]]; then
        printf 'cloudflared:running\ndokku:running\n'
        return 0
    fi

    return 1
}

cf_auth_check() {
    return 0
}

@test "dokku_app_domains_all returns every app and global hostname without duplicates" {
    dokku_cmd() {
        cat <<'EOF'
=====> demo domains information
       Domains app enabled:           true
       Domains app vhosts:            app.example.com, alt.example.com
       Domains global enabled:        true
       Domains global vhosts:         alt.example.com www.example.com
EOF
    }

    run dokku_app_domains_all "demo"
    assert_success
    assert_output $'app.example.com\nalt.example.com\nwww.example.com'
}

@test "sync_missing_ingress_from_dokku restores every missing Dokku hostname via API" {
    _tunnel_get_ingress() {
        cat "$_MOCK_INGRESS"
    }
    _tunnel_put_ingress() {
        printf '%s' "$1" > "$_MOCK_INGRESS"
        echo '{"success":true}'
    }

    dokku_list_apps() {
        printf 'demo\n'
    }

    dokku_app_domains_all() {
        printf 'app.example.com\nalt.example.com\n'
    }

    run sync_missing_ingress_from_dokku
    assert_success
    assert_output "2"

    _tunnel_get_ingress() {
        cat "$_MOCK_INGRESS"
    }

    run yaml_has_hostname "app.example.com"
    assert_success
    assert_output "yes"

    run yaml_has_hostname "alt.example.com"
    assert_success
    assert_output "yes"
}
