#!/usr/bin/env bats

setup() {
    load '../test_helper/common'
    export TUNNEL_ID="test-tunnel-id"
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

@test "_generate_config_from_dokku rebuilds ingress for every Dokku hostname" {
    export CONFIG_FILE="$BATS_TEST_TMPDIR/config.yml"

    dokku_list_apps() {
        printf 'demo\n'
    }

    dokku_app_domains_all() {
        printf 'app.example.com\nalt.example.com\n'
    }

    run _generate_config_from_dokku
    assert_success
    assert_output --partial "ok: 2 app rule(s)"

    run yaml_has_hostname "app.example.com"
    assert_success
    assert_output "yes"

    run yaml_has_hostname "alt.example.com"
    assert_success
    assert_output "yes"
}

@test "sync_missing_ingress_from_dokku restores every missing Dokku hostname" {
    cp "$FERRY_ROOT/test/fixtures/config-empty.yml" "$BATS_TEST_TMPDIR/config.yml"
    export CONFIG_FILE="$BATS_TEST_TMPDIR/config.yml"

    dokku_list_apps() {
        printf 'demo\n'
    }

    dokku_app_domains_all() {
        printf 'app.example.com\nalt.example.com\n'
    }

    run sync_missing_ingress_from_dokku
    assert_success
    assert_output "2"

    run yaml_has_hostname "app.example.com"
    assert_success
    assert_output "yes"

    run yaml_has_hostname "alt.example.com"
    assert_success
    assert_output "yes"
}

@test "preflight fails and does not generate blank config when Dokku app listing fails" {
    export CONFIG_FILE="$BATS_TEST_TMPDIR/missing-config.yml"
    rm -f "$CONFIG_FILE"

    dokku_list_apps() {
        return 1
    }

    run preflight
    assert_failure
    assert_output --partial "Failed to list Dokku apps while recovering missing config.yml"
    assert_file_not_exist "$CONFIG_FILE"
}
