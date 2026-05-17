#!/usr/bin/env bats
# shellcheck disable=SC2329,SC2034
bats_require_minimum_version 1.5.0
# Unit tests for ferry prune/reconcile flow

setup() {
    load '../test_helper/common'
    export CF_API_TOKEN="test-token"
}

@test "dokku_list_all_domains returns unique live domains across apps" {
    dokku_list_apps() {
        printf 'app1\napp2\n'
    }

    dokku_app_domains_all() {
        case "$1" in
            app1) printf 'app1.example.com\nshared.example.com\n' ;;
            app2) printf 'app2.example.com\nshared.example.com\n' ;;
            *) return 1 ;;
        esac
    }

    run dokku_list_all_domains
    assert_success
    assert_output $'app1.example.com\nshared.example.com\napp2.example.com'
}

@test "cmd_prune reconcile removes only orphan ingress rules after confirmation" {
    preflight() { :; }
    cf_token_verify() { return 0; }
    cloudflared_restart() { echo "cloudflared restarted"; }

    dokku_list_apps() {
        printf 'app1\napp2\n'
    }

    dokku_app_domains_all() {
        case "$1" in
            app1) printf 'app1.example.com\nwww.app1.example.com\n' ;;
            app2) printf 'app2.example.com\n' ;;
            *) return 1 ;;
        esac
    }

    _MOCK_INGRESS="$BATS_TEST_TMPDIR/ingress.json"
    cat > "$_MOCK_INGRESS" <<'EOF'
[
  {"hostname":"app1.example.com","service":"http://dokku:80"},
  {"hostname":"orphan.example.com","service":"http://dokku:80"},
  {"hostname":"www.app1.example.com","service":"http://dokku:80"},
  {"hostname":"app2.example.com","service":"http://dokku:80"},
  {"service":"http_status:404"}
]
EOF

    _tunnel_get_ingress() {
        cat "$_MOCK_INGRESS"
    }

    _tunnel_put_ingress() {
        printf '%s' "$1" > "$_MOCK_INGRESS"
        echo '{"success":true}'
    }

    confirm() {
        echo "PROMPT: $1" >&2
        return 0
    }

    run --separate-stderr cmd_prune reconcile
    assert_success
    [[ "$output" == *"Live check: fetching the current Cloudflare Tunnel ingress and Dokku domains."* ]]
    [[ "$output" == *"Removed 1 orphan ingress rule(s)"* ]]
    [[ "$stderr" == *"PROMPT: Prune these orphan ingress rule(s) now?"* ]]

    run jq -r '.[] | .hostname // "(catch-all)"' "$_MOCK_INGRESS"
    assert_success
    assert_line "app1.example.com"
    assert_line "www.app1.example.com"
    assert_line "app2.example.com"
    assert_line "(catch-all)"
    [[ "$output" != *"orphan.example.com"* ]]
}

@test "cmd_prune reconcile cancels cleanly when confirmation is declined" {
    preflight() { :; }
    cf_token_verify() { return 0; }

    dokku_list_apps() {
        printf 'app1\n'
    }

    dokku_app_domains_all() {
        printf 'app1.example.com\n'
    }

    _MOCK_INGRESS="$BATS_TEST_TMPDIR/ingress.json"
    cat > "$_MOCK_INGRESS" <<'EOF'
[
  {"hostname":"orphan.example.com","service":"http://dokku:80"},
  {"service":"http_status:404"}
]
EOF

    _tunnel_get_ingress() {
        cat "$_MOCK_INGRESS"
    }

    _PUT_FLAG="$BATS_TEST_TMPDIR/put.flag"
    _tunnel_put_ingress() {
        printf '%s' "$1" > "$_PUT_FLAG"
        echo '{"success":true}'
    }

    _RESTART_FLAG="$BATS_TEST_TMPDIR/restart.flag"
    cloudflared_restart() {
        printf 'called' > "$_RESTART_FLAG"
    }

    confirm() {
        echo "PROMPT: $1" >&2
        return 2
    }

    run --separate-stderr cmd_prune reconcile
    assert_success
    [[ "$output" == *"Cancelled."* ]]
    [[ "$stderr" == *"PROMPT: Prune these orphan ingress rule(s) now?"* ]]
    [[ ! -e "$_PUT_FLAG" ]]
    [[ ! -e "$_RESTART_FLAG" ]]
}
