#!/usr/bin/env bats
# test/integration/cli_new.bats — Tests for the ferry new command

setup() {
    load '../test_helper/common'
    FERRY="$FERRY_ROOT/ferry"
    export FERRY_APPS_DIR="$BATS_TEST_TMPDIR/apps"
    mkdir -p "$FERRY_APPS_DIR"
}

# ── Listing templates ─────────────────────────────────────────────────────────

@test "ferry new --list exits 0" {
    run "$FERRY" new --list
    assert_success
}

@test "ferry new --list contains 'express'" {
    run "$FERRY" new --list
    assert_success
    assert_output --partial "express"
}

@test "ferry new --list contains 'fastapi'" {
    run "$FERRY" new --list
    assert_success
    assert_output --partial "fastapi"
}

@test "ferry new --list contains 'axum'" {
    run "$FERRY" new --list
    assert_success
    assert_output --partial "axum"
}

# ── Successful project creation ───────────────────────────────────────────────

@test "ferry new creates express app directory" {
    run "$FERRY" new myapp -t express -y --no-deploy
    assert_success
    assert_dir_exists "$FERRY_APPS_DIR/myapp"
}

@test "ferry new creates fastapi app with Dockerfile" {
    run "$FERRY" new myapp -t fastapi -y --no-deploy
    assert_success
    assert_file_exists "$FERRY_APPS_DIR/myapp/Dockerfile"
}

# ── Custom port ───────────────────────────────────────────────────────────────

@test "ferry new with custom port uses that port in Dockerfile" {
    run "$FERRY" new myapp -t express -p 9000 -y --no-deploy
    assert_success
    run grep 'EXPOSE' "$FERRY_APPS_DIR/myapp/Dockerfile"
    assert_success
    assert_output --partial "9000"
}

# ── Validation: missing required arguments ────────────────────────────────────

@test "ferry new -y without name exits 1" {
    run "$FERRY" new -y -t express --no-deploy
    assert_failure
}

@test "ferry new myapp -y without -t exits 1" {
    run "$FERRY" new myapp -y --no-deploy
    assert_failure
}

# ── Validation: bad template ──────────────────────────────────────────────────

@test "ferry new with invalid template exits 1" {
    run "$FERRY" new myapp -t INVALID -y --no-deploy
    assert_failure
}

# ── Validation: bad app name ──────────────────────────────────────────────────

@test "ferry new with name starting with number exits 1" {
    run "$FERRY" new 123invalid -t express -y --no-deploy
    assert_failure
}

@test "ferry new with uppercase name exits 1" {
    run "$FERRY" new MyApp -t express -y --no-deploy
    assert_failure
}

@test "ferry new with single character name exits 1" {
    run "$FERRY" new a -t express -y --no-deploy
    assert_failure
}

@test "ferry new with trailing hyphen exits 1" {
    run "$FERRY" new test- -t express -y --no-deploy
    assert_failure
}

# ── Custom output directory ──────────────────────────────────────────────────

@test "ferry new with --output creates app in custom dir" {
    local custom_dir="$BATS_TEST_TMPDIR/custom-out"
    run "$FERRY" new myapp -t express -y --no-deploy -o "$custom_dir"
    assert_success
    assert_dir_exists "$custom_dir"
    assert_file_exists "$custom_dir/Dockerfile"
}

# ── Existing directory rejection ─────────────────────────────────────────────

@test "ferry new fails if output directory already exists" {
    mkdir -p "$FERRY_APPS_DIR/existing-app"
    run "$FERRY" new existing-app -t express -y --no-deploy
    assert_failure
    assert_output --partial "already exists"
}

# ── --no-deploy hint ─────────────────────────────────────────────────────────

@test "ferry new --no-deploy shows next steps hint" {
    run "$FERRY" new myapp -t express -y --no-deploy
    assert_success
    assert_output --partial "ferry deploy myapp"
}

# ── Git initialization ───────────────────────────────────────────────────────

@test "ferry new initializes git repository" {
    run "$FERRY" new myapp -t express -y --no-deploy
    assert_success
    assert_dir_exists "$FERRY_APPS_DIR/myapp/.git"
}
