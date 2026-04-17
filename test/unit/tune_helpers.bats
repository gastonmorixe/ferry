#!/usr/bin/env bats
# Unit tests for ferry tune helper functions

setup() {
    load '../test_helper/common'
    APP_DIR="$BATS_TEST_TMPDIR/app"
    mkdir -p "$APP_DIR"
}

# ---------------------------------------------------------------------------
# ferry_calc_node_heap — memory → --max-old-space-size
# ---------------------------------------------------------------------------

@test "calc_node_heap: 256 → 208 (mem - 48)" {
    run ferry_calc_node_heap 256
    assert_success
    assert_output "208"
}

@test "calc_node_heap: 512 → 464" {
    run ferry_calc_node_heap 512
    assert_success
    assert_output "464"
}

@test "calc_node_heap: 1024 → 976" {
    run ferry_calc_node_heap 1024
    assert_success
    assert_output "976"
}

@test "calc_node_heap: 128 → 80" {
    run ferry_calc_node_heap 128
    assert_success
    assert_output "80"
}

@test "calc_node_heap: 96 floors to 64" {
    run ferry_calc_node_heap 96
    assert_success
    assert_output "64"
}

@test "calc_node_heap: 64 floors to 64" {
    run ferry_calc_node_heap 64
    assert_success
    assert_output "64"
}

@test "calc_node_heap: 0 floors to 64" {
    run ferry_calc_node_heap 0
    assert_success
    assert_output "64"
}

# ---------------------------------------------------------------------------
# ferry_detect_runtime_from_dir
# ---------------------------------------------------------------------------

@test "detect_runtime: node (package.json)" {
    echo '{}' > "$APP_DIR/package.json"
    run ferry_detect_runtime_from_dir "$APP_DIR"
    assert_success
    assert_output "node"
}

@test "detect_runtime: python (pyproject.toml)" {
    touch "$APP_DIR/pyproject.toml"
    run ferry_detect_runtime_from_dir "$APP_DIR"
    assert_success
    assert_output "python"
}

@test "detect_runtime: python (requirements.txt)" {
    touch "$APP_DIR/requirements.txt"
    run ferry_detect_runtime_from_dir "$APP_DIR"
    assert_success
    assert_output "python"
}

@test "detect_runtime: python (Pipfile)" {
    touch "$APP_DIR/Pipfile"
    run ferry_detect_runtime_from_dir "$APP_DIR"
    assert_success
    assert_output "python"
}

@test "detect_runtime: go (go.mod)" {
    touch "$APP_DIR/go.mod"
    run ferry_detect_runtime_from_dir "$APP_DIR"
    assert_success
    assert_output "go"
}

@test "detect_runtime: rust (Cargo.toml)" {
    touch "$APP_DIR/Cargo.toml"
    run ferry_detect_runtime_from_dir "$APP_DIR"
    assert_success
    assert_output "rust"
}

@test "detect_runtime: ruby (Gemfile)" {
    touch "$APP_DIR/Gemfile"
    run ferry_detect_runtime_from_dir "$APP_DIR"
    assert_success
    assert_output "ruby"
}

@test "detect_runtime: empty dir → empty string" {
    run ferry_detect_runtime_from_dir "$APP_DIR"
    assert_success
    assert_output ""
}

@test "detect_runtime: nonexistent dir → empty string" {
    run ferry_detect_runtime_from_dir "$BATS_TEST_TMPDIR/does-not-exist"
    assert_success
    assert_output ""
}

@test "detect_runtime: node wins over python when both present" {
    echo '{}' > "$APP_DIR/package.json"
    touch "$APP_DIR/requirements.txt"
    run ferry_detect_runtime_from_dir "$APP_DIR"
    assert_success
    assert_output "node"
}
