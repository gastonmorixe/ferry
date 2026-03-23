#!/usr/bin/env bats

setup() {
    load '../test_helper/common'
    # Each test gets a clean ENV_FILE in BATS_TEST_TMPDIR
    export ENV_FILE="$BATS_TEST_TMPDIR/.env"
    rm -f "$ENV_FILE"
}

# ---------------------------------------------------------------------------
# env_set
# ---------------------------------------------------------------------------

@test "env_set creates new key in empty file" {
    env_set "MY_KEY" "hello"
    run grep "^MY_KEY=" "$ENV_FILE"
    assert_success
    assert_output "MY_KEY=hello"
}

@test "env_set creates new key in file with existing content" {
    echo "EXISTING=value" > "$ENV_FILE"
    env_set "NEW_KEY" "world"
    run grep "^NEW_KEY=" "$ENV_FILE"
    assert_success
    assert_output "NEW_KEY=world"
}

@test "env_set updates existing key" {
    echo "MY_KEY=old" > "$ENV_FILE"
    env_set "MY_KEY" "new"
    run grep "^MY_KEY=" "$ENV_FILE"
    assert_success
    assert_output "MY_KEY=new"
}

@test "env_set preserves other lines when updating" {
    printf "FIRST=one\nMY_KEY=old\nLAST=three\n" > "$ENV_FILE"
    env_set "MY_KEY" "updated"
    run grep "^FIRST=" "$ENV_FILE"
    assert_success
    assert_output "FIRST=one"
    run grep "^LAST=" "$ENV_FILE"
    assert_success
    assert_output "LAST=three"
    run grep "^MY_KEY=" "$ENV_FILE"
    assert_success
    assert_output "MY_KEY=updated"
}

@test "env_set updates value containing pipe character" {
    echo "MY_KEY=old" > "$ENV_FILE"
    env_set "MY_KEY" "a|b|c"
    run grep "^MY_KEY=" "$ENV_FILE"
    assert_success
    assert_output "MY_KEY=a|b|c"
}

@test "env_set creates value containing equals sign" {
    env_set "TOKEN" "base64string=="
    run grep "^TOKEN=" "$ENV_FILE"
    assert_success
    assert_output "TOKEN=base64string=="
}

@test "env_set updates value containing equals sign" {
    echo "TOKEN=old" > "$ENV_FILE"
    env_set "TOKEN" "new==value"
    run grep "^TOKEN=" "$ENV_FILE"
    assert_success
    assert_output "TOKEN=new==value"
}

@test "env_set handles value with spaces" {
    env_set "DESC" "hello world"
    run grep "^DESC=" "$ENV_FILE"
    assert_success
    assert_output "DESC=hello world"
}

@test "env_set handles empty value" {
    env_set "EMPTY" ""
    run grep "^EMPTY=" "$ENV_FILE"
    assert_success
    assert_output "EMPTY="
}

@test "env_set does not match key that is prefix of another" {
    printf "MY_KEY_LONG=keep\n" > "$ENV_FILE"
    env_set "MY_KEY" "new"
    run grep "^MY_KEY_LONG=" "$ENV_FILE"
    assert_success
    assert_output "MY_KEY_LONG=keep"
    run grep "^MY_KEY=" "$ENV_FILE"
    assert_success
    assert_output "MY_KEY=new"
}

@test "env_set creates file if missing" {
    rm -f "$ENV_FILE"
    env_set "BRAND_NEW" "created"
    assert_file_exists "$ENV_FILE"
    run grep "^BRAND_NEW=" "$ENV_FILE"
    assert_success
    assert_output "BRAND_NEW=created"
}
