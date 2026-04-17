#!/usr/bin/env bats
# test/integration/cli_help.bats — Tests for ferry help / usage output

setup() {
    load '../test_helper/common'
    FERRY="$FERRY_ROOT/ferry.sh"
}

# ── Exit codes ────────────────────────────────────────────────────────────────

@test "ferry help exits 0" {
    run "$FERRY" help
    assert_success
}

@test "ferry --help exits 0" {
    run "$FERRY" --help
    assert_success
}

@test "ferry -h exits 0" {
    run "$FERRY" -h
    assert_success
}

@test "ferry unknown-command exits 1" {
    run "$FERRY" unknown-command
    assert_failure
    assert_output --partial "Unknown command"
}

# ── Output contains "ferry" ───────────────────────────────────────────────────

@test "ferry help output contains 'ferry'" {
    run "$FERRY" help
    assert_success
    assert_output --partial "ferry"
}

# ── Key commands present in help output ───────────────────────────────────────

@test "ferry help output contains 'new'" {
    run "$FERRY" help
    assert_success
    assert_output --partial "new"
}

@test "ferry help output contains 'deploy'" {
    run "$FERRY" help
    assert_success
    assert_output --partial "deploy"
}

@test "ferry help output contains 'remove'" {
    run "$FERRY" help
    assert_success
    assert_output --partial "remove"
}

@test "ferry help output contains 'status'" {
    run "$FERRY" help
    assert_success
    assert_output --partial "status"
}

@test "ferry help output contains 'list'" {
    run "$FERRY" help
    assert_success
    assert_output --partial "list"
}

@test "ferry help output contains 'tune'" {
    run "$FERRY" help
    assert_success
    assert_output --partial "tune"
}

@test "ferry help output contains '--memory' flag" {
    run "$FERRY" help
    assert_success
    assert_output --partial "--memory"
}

@test "ferry help output contains '--runtime' flag" {
    run "$FERRY" help
    assert_success
    assert_output --partial "--runtime"
}
