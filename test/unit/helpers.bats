#!/usr/bin/env bats
# test/unit/helpers.bats — Shared generator helper behavior

setup() {
    load '../test_helper/common'
    SHARED_DIR="$FERRY_ROOT/generators/_shared"
    # shellcheck source=../../generators/_shared/helpers.sh
    source "$SHARED_DIR/helpers.sh"
}

@test "template_sub replaces placeholders in a file" {
    local dir="$BATS_TEST_TMPDIR/out"
    mkdir -p "$dir"
    printf '{{APP_NAME}} on {{APP_PORT}} (v{{FERRY_VERSION}})\n' >"$dir/sample.txt"

    APP_NAME="demo-app" APP_PORT="4242" FERRY_VERSION="9.9.9-test" \
        template_sub "$dir/sample.txt"

    run cat "$dir/sample.txt"
    assert_success
    assert_output --partial "demo-app on 4242"
    assert_output --partial "9.9.9-test"
}

@test "shared_app_json substitutes healthcheck path" {
    local dir="$BATS_TEST_TMPDIR/app-json"
    mkdir -p "$dir"

    shared_app_json "$dir" "/"

    run grep '"path": "/"' "$dir/app.json"
    assert_success
    refute_output --partial '{{HEALTHCHECK_PATH}}'
}
