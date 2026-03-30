#!/usr/bin/env bats

# Tests for tunnel ingress operations (API-based, mocked).
# The yaml_* function names are retained for backward compatibility.

setup() {
    load '../test_helper/common'

    # Mock API state — stored as a JSON file in tmpdir
    _MOCK_INGRESS="$BATS_TEST_TMPDIR/ingress.json"
}

# Load a fixture ingress state
_use_fixture() {
    local name="$1"
    case "$name" in
        config-valid.yml)
            cat > "$_MOCK_INGRESS" <<'EOF'
[{"hostname":"app1.example.com","service":"http://dokku:80"},{"hostname":"app2.example.com","service":"http://dokku:80"},{"service":"http_status:404"}]
EOF
            ;;
        config-empty.yml)
            cat > "$_MOCK_INGRESS" <<'EOF'
[{"service":"http_status:404"}]
EOF
            ;;
        config-invalid.yml)
            cat > "$_MOCK_INGRESS" <<'EOF'
[{"hostname":"app1.example.com","service":"http://dokku:80"}]
EOF
            ;;
    esac

    # Override API functions to use local mock
    _tunnel_get_ingress() {
        cat "$_MOCK_INGRESS"
    }

    _tunnel_put_ingress() {
        local ingress_json="$1"
        printf '%s' "$ingress_json" > "$_MOCK_INGRESS"
        echo '{"success":true}'
    }
}

# ---------------------------------------------------------------------------
# yaml_list_ingress
# ---------------------------------------------------------------------------

@test "yaml_list_ingress lists hostnames from valid config" {
    _use_fixture "config-valid.yml"
    run yaml_list_ingress
    assert_success
    assert_line --partial "app1.example.com"
    assert_line --partial "app2.example.com"
}

@test "yaml_list_ingress returns only catch-all for empty config" {
    _use_fixture "config-empty.yml"
    run yaml_list_ingress
    assert_success
    assert_line --partial "(catch-all)"
}

# ---------------------------------------------------------------------------
# yaml_has_hostname
# ---------------------------------------------------------------------------

@test "yaml_has_hostname outputs yes for existing hostname" {
    _use_fixture "config-valid.yml"
    run yaml_has_hostname "app1.example.com"
    assert_success
    assert_output "yes"
}

@test "yaml_has_hostname outputs no for missing hostname" {
    _use_fixture "config-valid.yml"
    run yaml_has_hostname "nothere.example.com"
    assert_success
    assert_output "no"
}

# ---------------------------------------------------------------------------
# yaml_add_ingress
# ---------------------------------------------------------------------------

@test "yaml_add_ingress adds a new hostname" {
    _use_fixture "config-valid.yml"
    run yaml_add_ingress "new.example.com" "http://dokku:80"
    assert_success
    assert_output "ok"
    run yaml_has_hostname "new.example.com"
    assert_output "yes"
}

@test "yaml_add_ingress fails for duplicate hostname" {
    _use_fixture "config-valid.yml"
    run yaml_add_ingress "app1.example.com" "http://dokku:80"
    assert_failure
}

# ---------------------------------------------------------------------------
# yaml_remove_ingress
# ---------------------------------------------------------------------------

@test "yaml_remove_ingress removes an existing hostname" {
    _use_fixture "config-valid.yml"
    run yaml_remove_ingress "app1.example.com"
    assert_success
    assert_output "ok"
    run yaml_has_hostname "app1.example.com"
    assert_output "no"
}

# ---------------------------------------------------------------------------
# yaml_validate
# ---------------------------------------------------------------------------

@test "yaml_validate passes for valid config" {
    _use_fixture "config-valid.yml"
    run yaml_validate
    assert_success
    assert_output --partial "ok"
}

@test "yaml_validate fails for config missing catch-all" {
    _use_fixture "config-invalid.yml"
    run yaml_validate
    assert_failure
}
