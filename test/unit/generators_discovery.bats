#!/usr/bin/env bats

# discover_generators and gen_index_by_id populate and query the
# _GEN_IDS / _GEN_CATS / _GEN_IDX globals directly — no `run` needed
# for those; use `run` only when checking printed output.

setup() {
    load '../test_helper/common'
    discover_generators
}

# ---------------------------------------------------------------------------
# discover_generators — array contents
# ---------------------------------------------------------------------------

@test "discovers all 11 generators" {
    [[ "${#_GEN_IDS[@]}" -eq 11 ]]
}

@test "_GEN_IDS contains express" {
    local found=0
    for id in "${_GEN_IDS[@]}"; do
        [[ "$id" == "express" ]] && found=1 && break
    done
    [[ "$found" -eq 1 ]]
}

@test "_GEN_CATS contains backend" {
    local found=0
    for cat in "${_GEN_CATS[@]}"; do
        [[ "$cat" == "backend" ]] && found=1 && break
    done
    [[ "$found" -eq 1 ]]
}

@test "_GEN_CATS contains frontend" {
    local found=0
    for cat in "${_GEN_CATS[@]}"; do
        [[ "$cat" == "frontend" ]] && found=1 && break
    done
    [[ "$found" -eq 1 ]]
}

@test "_GEN_CATS contains fullstack" {
    local found=0
    for cat in "${_GEN_CATS[@]}"; do
        [[ "$cat" == "fullstack" ]] && found=1 && break
    done
    [[ "$found" -eq 1 ]]
}

@test "discover_generators skips _shared directory" {
    local found=0
    for id in "${_GEN_IDS[@]}"; do
        [[ "$id" == "_shared" ]] && found=1 && break
    done
    [[ "$found" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# gen_index_by_id
# ---------------------------------------------------------------------------

@test "gen_index_by_id finds express and returns 0" {
    gen_index_by_id "express"
    [[ $? -eq 0 ]]
}

@test "gen_index_by_id sets _GEN_IDX to a valid index for express" {
    gen_index_by_id "express"
    [[ "$_GEN_IDX" -ge 0 ]]
    [[ "${_GEN_IDS[$_GEN_IDX]}" == "express" ]]
}

@test "gen_index_by_id returns 1 for nonexistent generator" {
    run gen_index_by_id "nonexistent"
    assert_failure
}
