#!/usr/bin/env bats
# shellcheck disable=SC2329,SC2034
bats_require_minimum_version 1.5.0

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

@test "dokku_list_apps returns empty when Dokku has no apps deployed" {
    dokku_cmd() {
        # Exact output of `dokku apps:list` on a fresh Dokku install.
        cat <<'EOF'
=====> My Apps
 !     You haven't deployed any applications yet
EOF
    }

    run dokku_list_apps
    assert_success
    assert_output ""
}

@test "dokku_list_apps returns app names one per line, skipping banner" {
    dokku_cmd() {
        cat <<'EOF'
=====> My Apps
demo
another-app
EOF
    }

    run dokku_list_apps
    assert_success
    assert_output $'demo\nanother-app'
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

    confirm() {
        echo "PROMPT: $1" >&2
        return 0
    }

    run --separate-stderr sync_missing_ingress_from_dokku
    assert_success
    [[ "$output" == "2" ]]
    [[ "$stderr" == *"Ingress recovery needed"* ]]
    [[ "$stderr" == *"Dokku already knows about these app domains"* ]]
    [[ "$stderr" == *"app.example.com → http://dokku:80 (Dokku app demo)"* ]]
    [[ "$stderr" == *"alt.example.com → http://dokku:80 (Dokku app demo)"* ]]
    [[ "$stderr" == *"PROMPT: Restore these ingress rule(s) now?"* ]]
    [[ "$stderr" == *"Restored 2 missing ingress rule(s) from Dokku before deploy"* ]]

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

@test "sync_missing_ingress_from_dokku skips repair when declined" {
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
        printf 'app.example.com\n'
    }

    confirm() {
        echo "PROMPT: $1" >&2
        return 2
    }

    run --separate-stderr sync_missing_ingress_from_dokku
    assert_success
    [[ "$output" == "0" ]]
    [[ "$stderr" == *"PROMPT: Restore these ingress rule(s) now?"* ]]
    [[ "$stderr" == *"Skipped ingress recovery."* ]]

    _tunnel_get_ingress() {
        cat "$_MOCK_INGRESS"
    }

    run yaml_has_hostname "app.example.com"
    assert_success
    assert_output "no"
}
