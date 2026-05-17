#!/usr/bin/env bats
# Unit tests for ferry TUI helper functions
# shellcheck disable=SC2329,SC2034

setup() {
    load '../test_helper/common'
}

make_line() {
    local width="$1" line=""
    while (( width > 0 )); do
        line+="─"
        ((width--))
    done
    printf '%s' "$line"
}

@test "_divider_line caps divider width at 40 columns" {
    run _divider_line 85
    assert_success
    assert_output "$(make_line 40)"
}

@test "section_header caps divider width in wide terminals" {
    _term_width() { echo 120; }

    run section_header "Apps"
    assert_success
    assert_output $'\n  Apps '"$(make_line 35)"
}

@test "tui_select returns back on left arrow" {
    _IS_TTY=true

    run tui_select "Menu" "One" "Two" <<< $'\e[D'
    [ "$status" -eq 2 ]
}

@test "tui_select --no-back ignores left arrow" {
    _IS_TTY=true

    run tui_select --no-back "Menu" "One" "Two" <<< $'\e[D\n'
    assert_success
}

@test "confirm returns cancel on No selection" {
    _IS_TTY=true

    run confirm "Proceed?" <<< $'\e[B\n'
    [ "$status" -eq 2 ]
}

@test "cmd_list omits table divider lines" {
    preflight() { :; }
    dokku_list_apps() { echo "app1"; }
    dokku_app_domains() { echo "app1.example.com"; }
    dokku_app_ports() { echo "http:80:5000"; }
    app_effective_status() { echo "running"; }

    run cmd_list
    assert_success
    [[ "$output" != *"$(make_line 70)"* ]]
}

@test "cmd_status omits table divider lines" {
    preflight() { :; }
    CF_API_TOKEN=""
    docker() {
        case "$*" in
            *"ps --format"*cloudflared*) echo "cloudflared:running" ;;
            *"ps --format"*dokku*) echo "dokku:running" ;;
            *"logs --tail=100 cloudflared"*) echo "Registered tunnel connection" ;;
            *) return 0 ;;
        esac
    }
    dig() { echo "1.1.1.1"; }
    dokku_list_apps() { echo "app1"; }
    dokku_app_domains() { echo "app1.example.com"; }
    dokku_app_ports() { echo "http:80:5000"; }
    dokku_app_status() { echo "running"; }
    app_effective_status() { echo "running"; }
    yaml_has_hostname() { echo "yes"; }
    yaml_list_ingress() { printf '%s\t%s\n' "app1.example.com" "http://dokku:80"; }
    dns_check() { echo "1.1.1.1"; }
    _detect_host_resolvers() { echo "192.168.1.1"; }
    _probe_resolver() { return 0; }
    _probe_container_dns() { return 0; }

    run cmd_status
    assert_success
    [[ "$output" != *"$(make_line 85)"* ]]
}
