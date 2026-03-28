#!/usr/bin/env bats
# test/generators/all_generators.bats — Tests for all 11 Ferry generators

setup() {
    load '../test_helper/generators_common'
}

# ── express ──────────────────────────────────────────────────────────────────

@test "express generator creates valid project" {
    run_generator "express" "test-app" "5000"

    assert_file_exists "$_GEN_OUT/Dockerfile"
    assert_file_exists "$_GEN_OUT/.gitignore"
    assert_file_exists "$_GEN_OUT/.dockerignore"
    assert_file_exists "$_GEN_OUT/package.json"
    assert_file_exists "$_GEN_OUT/tsconfig.json"

    run grep -r '{{' "$_GEN_OUT"
    assert_failure

    run grep 'EXPOSE' "$_GEN_OUT/Dockerfile"
    assert_success
    assert_output --partial "5000"
}

@test "express generator produces valid JSON files" {
    run_generator "express" "test-app" "5000"

    run bash -c "jq . '$_GEN_OUT/package.json' > /dev/null"
    assert_success

    run bash -c "jq . '$_GEN_OUT/tsconfig.json' > /dev/null"
    assert_success
}

# ── fastapi ───────────────────────────────────────────────────────────────────

@test "fastapi generator creates valid project" {
    run_generator "fastapi" "test-app" "8000"

    assert_file_exists "$_GEN_OUT/Dockerfile"
    assert_file_exists "$_GEN_OUT/.gitignore"
    assert_file_exists "$_GEN_OUT/.dockerignore"

    run grep -r '{{' "$_GEN_OUT"
    assert_failure

    run grep 'EXPOSE' "$_GEN_OUT/Dockerfile"
    assert_success
    assert_output --partial "8000"
}

# ── nextjs ────────────────────────────────────────────────────────────────────

@test "nextjs generator creates valid project" {
    run_generator "nextjs" "test-app" "3000"

    assert_file_exists "$_GEN_OUT/Dockerfile"
    assert_file_exists "$_GEN_OUT/.gitignore"
    assert_file_exists "$_GEN_OUT/.dockerignore"
    assert_file_exists "$_GEN_OUT/package.json"
    assert_file_exists "$_GEN_OUT/tsconfig.json"

    run grep -r '{{' "$_GEN_OUT"
    assert_failure

    run grep 'EXPOSE' "$_GEN_OUT/Dockerfile"
    assert_success
    assert_output --partial "3000"
}

@test "nextjs generator produces valid JSON files" {
    run_generator "nextjs" "test-app" "3000"

    run bash -c "jq . '$_GEN_OUT/package.json' > /dev/null"
    assert_success

    run bash -c "jq . '$_GEN_OUT/tsconfig.json' > /dev/null"
    assert_success
}

# ── nestjs ────────────────────────────────────────────────────────────────────

@test "nestjs generator creates valid project" {
    run_generator "nestjs" "test-app" "3000"

    assert_file_exists "$_GEN_OUT/Dockerfile"
    assert_file_exists "$_GEN_OUT/.gitignore"
    assert_file_exists "$_GEN_OUT/.dockerignore"
    assert_file_exists "$_GEN_OUT/package.json"
    assert_file_exists "$_GEN_OUT/tsconfig.json"

    run grep -r '{{' "$_GEN_OUT"
    assert_failure

    run grep 'EXPOSE' "$_GEN_OUT/Dockerfile"
    assert_success
    assert_output --partial "3000"
}

@test "nestjs generator produces valid JSON files" {
    run_generator "nestjs" "test-app" "3000"

    run bash -c "jq . '$_GEN_OUT/package.json' > /dev/null"
    assert_success

    run bash -c "jq . '$_GEN_OUT/tsconfig.json' > /dev/null"
    assert_success

    run bash -c "jq . '$_GEN_OUT/tsconfig.build.json' > /dev/null"
    assert_success
}

# ── react ─────────────────────────────────────────────────────────────────────

@test "react generator creates valid project" {
    run_generator "react" "test-app" "80"

    assert_file_exists "$_GEN_OUT/Dockerfile"
    assert_file_exists "$_GEN_OUT/.gitignore"
    assert_file_exists "$_GEN_OUT/.dockerignore"
    assert_file_exists "$_GEN_OUT/package.json"
    assert_file_exists "$_GEN_OUT/tsconfig.json"
    assert_file_exists "$_GEN_OUT/tsconfig.app.json"
    assert_file_exists "$_GEN_OUT/tsconfig.node.json"

    run grep -r '{{' "$_GEN_OUT"
    assert_failure

    run grep 'EXPOSE' "$_GEN_OUT/Dockerfile"
    assert_success
    assert_output --partial "80"
}

@test "react generator produces valid JSON files" {
    run_generator "react" "test-app" "80"

    run bash -c "jq . '$_GEN_OUT/package.json' > /dev/null"
    assert_success

    run bash -c "jq . '$_GEN_OUT/tsconfig.json' > /dev/null"
    assert_success

    run bash -c "jq . '$_GEN_OUT/tsconfig.app.json' > /dev/null"
    assert_success

    run bash -c "jq . '$_GEN_OUT/tsconfig.node.json' > /dev/null"
    assert_success
}

@test "node generators use a first-build-safe npm install strategy" {
    local generators=(express nextjs nestjs react)
    local -A ports=(
        [express]=5000
        [nextjs]=3000
        [nestjs]=3000
        [react]=80
    )

    for gen in "${generators[@]}"; do
        run_generator "$gen" "test-${gen}" "${ports[$gen]}"

        assert_file_not_exists "$_GEN_OUT/package-lock.json"

        run grep -n "npm ci" "$_GEN_OUT/Dockerfile"
        assert_failure

        run grep -n "npm install" "$_GEN_OUT/Dockerfile"
        assert_success
    done
}

# ── django ────────────────────────────────────────────────────────────────────

@test "django generator creates valid project" {
    run_generator "django" "test-app" "8000"

    assert_file_exists "$_GEN_OUT/Dockerfile"
    assert_file_exists "$_GEN_OUT/.gitignore"
    assert_file_exists "$_GEN_OUT/.dockerignore"

    run grep -r '{{' "$_GEN_OUT"
    assert_failure

    run grep 'EXPOSE' "$_GEN_OUT/Dockerfile"
    assert_success
    assert_output --partial "8000"
}

# ── rails ─────────────────────────────────────────────────────────────────────

@test "rails generator creates valid project" {
    run_generator "rails" "test-app" "3000"

    assert_file_exists "$_GEN_OUT/Dockerfile"
    assert_file_exists "$_GEN_OUT/.gitignore"
    assert_file_exists "$_GEN_OUT/.dockerignore"
    assert_file_exists "$_GEN_OUT/Gemfile"

    run grep -r '{{' "$_GEN_OUT"
    assert_failure

    run grep 'EXPOSE' "$_GEN_OUT/Dockerfile"
    assert_success
    assert_output --partial "3000"
}

@test "rails generator creates Gemfile.lock required by Dockerfile" {
    run_generator "rails" "test-app" "3000"

    assert_file_exists "$_GEN_OUT/Gemfile.lock"
}

# ── go-net ────────────────────────────────────────────────────────────────────

@test "go-net generator creates valid project" {
    run_generator "go-net" "test-app" "8080"

    assert_file_exists "$_GEN_OUT/Dockerfile"
    assert_file_exists "$_GEN_OUT/.gitignore"
    assert_file_exists "$_GEN_OUT/.dockerignore"
    assert_file_exists "$_GEN_OUT/go.mod"

    # Exclude .go files — Go's html/template uses {{ }} syntax legitimately
    run grep -r --include='*.mod' --include='Dockerfile' --include='*.css' '{{' "$_GEN_OUT"
    assert_failure

    run grep 'EXPOSE' "$_GEN_OUT/Dockerfile"
    assert_success
    assert_output --partial "8080"
}

@test "go-net generator go.mod contains module directive" {
    run_generator "go-net" "test-app" "8080"

    run grep 'module' "$_GEN_OUT/go.mod"
    assert_success
}

# ── go-fiber ──────────────────────────────────────────────────────────────────

@test "go-fiber generator creates valid project" {
    run_generator "go-fiber" "test-app" "3000"

    assert_file_exists "$_GEN_OUT/Dockerfile"
    assert_file_exists "$_GEN_OUT/.gitignore"
    assert_file_exists "$_GEN_OUT/.dockerignore"
    assert_file_exists "$_GEN_OUT/go.mod"

    run grep -r '{{' "$_GEN_OUT"
    assert_failure

    run grep 'EXPOSE' "$_GEN_OUT/Dockerfile"
    assert_success
    assert_output --partial "3000"
}

@test "go-fiber generator go.mod contains module directive" {
    run_generator "go-fiber" "test-app" "3000"

    run grep 'module' "$_GEN_OUT/go.mod"
    assert_success
}

# ── axum ──────────────────────────────────────────────────────────────────────

@test "axum generator creates valid project" {
    run_generator "axum" "test-app" "3000"

    assert_file_exists "$_GEN_OUT/Dockerfile"
    assert_file_exists "$_GEN_OUT/.gitignore"
    assert_file_exists "$_GEN_OUT/.dockerignore"
    assert_file_exists "$_GEN_OUT/Cargo.toml"

    run grep -r '{{' "$_GEN_OUT"
    assert_failure

    run grep 'EXPOSE' "$_GEN_OUT/Dockerfile"
    assert_success
    assert_output --partial "3000"
}

@test "axum generator Cargo.toml contains [package]" {
    run_generator "axum" "test-app" "3000"

    run grep '\[package\]' "$_GEN_OUT/Cargo.toml"
    assert_success
}

# ── actix ─────────────────────────────────────────────────────────────────────

@test "actix generator creates valid project" {
    run_generator "actix" "test-app" "8080"

    assert_file_exists "$_GEN_OUT/Dockerfile"
    assert_file_exists "$_GEN_OUT/.gitignore"
    assert_file_exists "$_GEN_OUT/.dockerignore"
    assert_file_exists "$_GEN_OUT/Cargo.toml"

    run grep -r '{{' "$_GEN_OUT"
    assert_failure

    run grep 'EXPOSE' "$_GEN_OUT/Dockerfile"
    assert_success
    assert_output --partial "8080"
}

@test "actix generator Cargo.toml contains [package]" {
    run_generator "actix" "test-app" "8080"

    run grep '\[package\]' "$_GEN_OUT/Cargo.toml"
    assert_success
}

# ── Entry point files ────────────────────────────────────────────────────────

@test "all generators create their main entry point file" {
    local -A entry_points=(
        [express]="app.ts"
        [fastapi]="main.py"
        [nextjs]="src/app/page.tsx"
        [nestjs]="src/main.ts"
        [react]="src/main.tsx"
        [django]="manage.py"
        [rails]="config/routes.rb"
        [go-net]="main.go"
        [go-fiber]="main.go"
        [axum]="src/main.rs"
        [actix]="src/main.rs"
    )
    local -A ports=(
        [express]=5000 [fastapi]=8000 [nextjs]=3000 [nestjs]=3000
        [react]=80 [django]=8000 [rails]=3000 [go-net]=8080
        [go-fiber]=3000 [axum]=3000 [actix]=8080
    )
    for gen in "${!entry_points[@]}"; do
        run_generator "$gen" "test-${gen}" "${ports[$gen]}"
        assert_file_exists "$_GEN_OUT/${entry_points[$gen]}"
    done
}

# ── style.css presence ───────────────────────────────────────────────────────

@test "all generators include style.css" {
    local -A css_paths=(
        [express]="style.css"
        [fastapi]="static/style.css"
        [nextjs]="public/style.css"
        [nestjs]="public/style.css"
        [react]="public/style.css"
        [django]="static/style.css"
        [rails]="public/style.css"
        [go-net]="style.css"
        [go-fiber]="style.css"
        [axum]="style.css"
        [actix]="style.css"
    )
    local -A ports=(
        [express]=5000 [fastapi]=8000 [nextjs]=3000 [nestjs]=3000
        [react]=80 [django]=8000 [rails]=3000 [go-net]=8080
        [go-fiber]=3000 [axum]=3000 [actix]=8080
    )
    for gen in "${!css_paths[@]}"; do
        run_generator "$gen" "test-${gen}" "${ports[$gen]}"
        assert_file_exists "$_GEN_OUT/${css_paths[$gen]}"
    done
}

# ── Rails production readiness ──────────────────────────────────────────────

@test "rails generator sets RAILS_ENV=production in Dockerfile" {
    run_generator "rails" "test-app" "3000"

    run grep 'RAILS_ENV=production' "$_GEN_OUT/Dockerfile"
    assert_success
}

@test "rails generator clears config.hosts for Dokku proxy" {
    run_generator "rails" "test-app" "3000"

    run grep 'config.hosts.clear' "$_GEN_OUT/config/application.rb"
    assert_success
}

@test "rails generator sets secret_key_base for production" {
    run_generator "rails" "test-app" "3000"

    run grep 'secret_key_base' "$_GEN_OUT/config/application.rb"
    assert_success
}

# ── Healthcheck coverage ────────────────────────────────────────────────────

@test "all generators include app.json with healthcheck" {
    local -A ports=(
        [express]=5000 [fastapi]=8000 [nextjs]=3000 [nestjs]=3000
        [react]=80 [django]=8000 [rails]=3000 [go-net]=8080
        [go-fiber]=3000 [axum]=3000 [actix]=8080
    )
    for gen in "${!ports[@]}"; do
        run_generator "$gen" "test-${gen}" "${ports[$gen]}"
        assert_file_exists "$_GEN_OUT/app.json"

        run bash -c "jq . '$_GEN_OUT/app.json' > /dev/null"
        assert_success

        run grep '"port"' "$_GEN_OUT/app.json"
        assert_success
        assert_output --partial "${ports[$gen]}"
    done
}

@test "all generators include HEALTHCHECK in Dockerfile" {
    local -A ports=(
        [express]=5000 [fastapi]=8000 [nextjs]=3000 [nestjs]=3000
        [react]=80 [django]=8000 [rails]=3000 [go-net]=8080
        [go-fiber]=3000 [axum]=3000 [actix]=8080
    )
    for gen in "${!ports[@]}"; do
        run_generator "$gen" "test-${gen}" "${ports[$gen]}"

        run grep 'HEALTHCHECK' "$_GEN_OUT/Dockerfile"
        assert_success
    done
}

@test "react app.json healthcheck uses root path" {
    run_generator "react" "test-app" "80"

    run bash -c "jq -r '.healthchecks.web[0].path' '$_GEN_OUT/app.json'"
    assert_success
    assert_output "/"
}

@test "server generators app.json healthcheck uses /health path" {
    local -A ports=(
        [express]=5000 [fastapi]=8000 [nextjs]=3000 [nestjs]=3000
        [django]=8000 [rails]=3000 [go-net]=8080
        [go-fiber]=3000 [axum]=3000 [actix]=8080
    )
    for gen in "${!ports[@]}"; do
        run_generator "$gen" "test-${gen}" "${ports[$gen]}"

        run bash -c "jq -r '.healthchecks.web[0].path' '$_GEN_OUT/app.json'"
        assert_success
        assert_output "/health"
    done
}

# ── Ferry attribution branding ──────────────────────────────────────────────

@test "all generators include Ferry attribution in generated output" {
    local -A ports=(
        [express]=5000 [fastapi]=8000 [nextjs]=3000 [nestjs]=3000
        [react]=80 [django]=8000 [rails]=3000 [go-net]=8080
        [go-fiber]=3000 [axum]=3000 [actix]=8080
    )

    local failures=0

    for gen in "${!ports[@]}"; do
        run_generator "$gen" "branding-${gen}" "${ports[$gen]}"

        # Check for "Built with" in generated source files
        if ! grep -rq 'Built with' "$_GEN_OUT" --include='*.ts' --include='*.tsx' --include='*.py' --include='*.rb' --include='*.erb' --include='*.go' --include='*.rs'; then
            printf 'FAIL: %s missing "Built with" in source\n' "$gen" >&3
            failures=$((failures + 1))
        fi

        # Check for Ferry emoji branding (⛵) in generated source files
        if ! grep -rq '⛵' "$_GEN_OUT" --include='*.ts' --include='*.tsx' --include='*.py' --include='*.rb' --include='*.erb' --include='*.go' --include='*.rs'; then
            printf 'FAIL: %s missing ⛵ emoji in source\n' "$gen" >&3
            failures=$((failures + 1))
        fi

        # Check for GitHub repo link
        if ! grep -rq 'github.com/gastonmorixe/ferry' "$_GEN_OUT" --include='*.ts' --include='*.tsx' --include='*.py' --include='*.rb' --include='*.erb' --include='*.go' --include='*.rs'; then
            printf 'FAIL: %s missing GitHub repo link\n' "$gen" >&3
            failures=$((failures + 1))
        fi
    done

    [ "$failures" -eq 0 ]
}

@test "all server generators include Ferry version in JSON response field" {
    local -A ports=(
        [express]=5000 [fastapi]=8000 [nextjs]=3000 [nestjs]=3000
        [django]=8000 [rails]=3000 [go-net]=8080
        [go-fiber]=3000 [axum]=3000 [actix]=8080
    )

    local failures=0

    for gen in "${!ports[@]}"; do
        run_generator "$gen" "json-${gen}" "${ports[$gen]}"

        # The ferry field should contain version string, not boolean true
        if grep -rq '"ferry".*:.*true\b' "$_GEN_OUT" --include='*.ts' --include='*.py' --include='*.rb' --include='*.go' --include='*.rs'; then
            printf 'FAIL: %s still has ferry: true (should be version string)\n' "$gen" >&3
            failures=$((failures + 1))
        fi
    done

    [ "$failures" -eq 0 ]
}

# ── go-net Ferry placeholder check ──────────────────────────────────────────

@test "go-net generator has no unreplaced Ferry placeholders in .go files" {
    run_generator "go-net" "test-app" "8080"

    # Go's html/template uses {{.Foo}} — that's fine.
    # But Ferry's {{APP_NAME}}, {{APP_PORT}}, {{FERRY_VERSION}}, {{YEAR}} must be substituted.
    run grep -E '\{\{(APP_NAME|APP_PORT|FERRY_VERSION|YEAR)\}\}' "$_GEN_OUT/main.go"
    assert_failure
}

# ── APP_NAME substitution ────────────────────────────────────────────────────

@test "express generator substitutes APP_NAME in source" {
    run_generator "express" "my-cool-app" "5000"
    run grep "my-cool-app" "$_GEN_OUT/package.json"
    assert_success
}

@test "fastapi generator substitutes APP_NAME in source" {
    run_generator "fastapi" "my-cool-app" "8000"
    run grep "my-cool-app" "$_GEN_OUT/main.py"
    assert_success
}

@test "go-net generator substitutes APP_NAME in go.mod" {
    run_generator "go-net" "my-cool-app" "8080"
    run grep "my-cool-app" "$_GEN_OUT/go.mod"
    assert_success
}

# bats test_tags=docker
@test "all generators build their generated Docker image" {
    require_docker_for_smoke_tests

    local generators=(
        actix
        axum
        django
        express
        fastapi
        go-fiber
        go-net
        nestjs
        nextjs
        rails
        react
    )
    local -A ports=(
        [actix]=8080
        [axum]=3000
        [django]=8000
        [express]=5000
        [fastapi]=8000
        [go-fiber]=3000
        [go-net]=8080
        [nestjs]=3000
        [nextjs]=3000
        [rails]=3000
        [react]=80
    )

    local failures=0

    for gen in "${generators[@]}"; do
        run_generator "$gen" "smoke-${gen}" "${ports[$gen]}"
        if ! docker_build_generated_app "$gen"; then
            failures=$((failures + 1))
        fi
    done

    [ "$failures" -eq 0 ]
}

# ── Runtime HTTP smoke tests ────────────────────────────────────────────────

# bats test_tags=docker
@test "all generators respond with HTTP 200 when started in Docker" {
    require_docker_for_smoke_tests

    local generators=(
        actix
        axum
        django
        express
        fastapi
        go-fiber
        go-net
        nestjs
        nextjs
        rails
        react
    )
    local -A ports=(
        [actix]=8080
        [axum]=3000
        [django]=8000
        [express]=5000
        [fastapi]=8000
        [go-fiber]=3000
        [go-net]=8080
        [nestjs]=3000
        [nextjs]=3000
        [rails]=3000
        [react]=80
    )

    local failures=0

    for gen in "${generators[@]}"; do
        printf 'testing %s ...\n' "$gen" >&3

        run_generator "$gen" "http-${gen}" "${ports[$gen]}"

        if ! docker_run_generated_app "$gen" "${ports[$gen]}"; then
            printf 'FAIL: docker run failed for %s\n' "$gen" >&3
            failures=$((failures + 1))
            continue
        fi

        local http_code
        http_code=$(wait_for_http_200 "http://localhost:${_CONTAINER_PORT}/") || true

        if [[ "$http_code" != "200" ]]; then
            printf 'FAIL: %s returned HTTP %s (expected 200)\n' "$gen" "$http_code" >&3
            docker logs --tail 30 "$_CONTAINER_ID" >&3 2>&1 || true
            failures=$((failures + 1))
        else
            printf 'OK: %s → HTTP %s\n' "$gen" "$http_code" >&3
        fi

        # Stop container before starting the next (conserve Pi RAM)
        docker stop "$_CONTAINER_ID" >/dev/null 2>&1 || true
        docker rm -f "$_CONTAINER_ID" >/dev/null 2>&1 || true
    done

    cleanup_test_containers
    [ "$failures" -eq 0 ]
}
