#!/usr/bin/env bats

setup() {
    load '../test_helper/common'
    # Each test gets its own isolated app directory inside BATS_TEST_TMPDIR
    APP_DIR="$BATS_TEST_TMPDIR/app"
    mkdir -p "$APP_DIR"
}

# ---------------------------------------------------------------------------
# Dockerfile EXPOSE
# ---------------------------------------------------------------------------

@test "detect_app_port detects port from Dockerfile EXPOSE" {
    echo "FROM node:18" > "$APP_DIR/Dockerfile"
    echo "EXPOSE 3000" >> "$APP_DIR/Dockerfile"
    run detect_app_port "$APP_DIR"
    assert_success
    assert_output "3000 Dockerfile EXPOSE"
}

@test "detect_app_port strips /tcp suffix from Dockerfile EXPOSE" {
    echo "FROM node:18" > "$APP_DIR/Dockerfile"
    echo "EXPOSE 8080/tcp" >> "$APP_DIR/Dockerfile"
    run detect_app_port "$APP_DIR"
    assert_success
    assert_output "8080 Dockerfile EXPOSE"
}

# ---------------------------------------------------------------------------
# package.json — framework detection
# ---------------------------------------------------------------------------

@test "detect_app_port detects port 3000 for next dependency" {
    cat > "$APP_DIR/package.json" <<'EOF'
{
  "dependencies": {
    "next": "^14.0.0",
    "react": "^18.0.0"
  }
}
EOF
    run detect_app_port "$APP_DIR"
    assert_success
    assert_output "3000 next (package.json)"
}

@test "detect_app_port detects port 3000 for express dependency" {
    cat > "$APP_DIR/package.json" <<'EOF'
{
  "dependencies": {
    "express": "^4.18.0"
  }
}
EOF
    run detect_app_port "$APP_DIR"
    assert_success
    assert_output "3000 express (package.json)"
}

# ---------------------------------------------------------------------------
# package.json scripts.start — port flag
# ---------------------------------------------------------------------------

@test "detect_app_port detects port from scripts.start --port flag" {
    cat > "$APP_DIR/package.json" <<'EOF'
{
  "scripts": {
    "start": "node server.js --port 4000"
  }
}
EOF
    run detect_app_port "$APP_DIR"
    assert_success
    assert_output "4000 start script (--port)"
}

# ---------------------------------------------------------------------------
# Procfile — port flag
# ---------------------------------------------------------------------------

@test "detect_app_port detects port from Procfile --port flag" {
    echo "web: node server.js --port 7000" > "$APP_DIR/Procfile"
    run detect_app_port "$APP_DIR"
    assert_success
    assert_output "7000 Procfile (--port)"
}

# ---------------------------------------------------------------------------
# No detection
# ---------------------------------------------------------------------------

@test "detect_app_port returns failure for empty directory" {
    run detect_app_port "$APP_DIR"
    assert_failure
}

@test "detect_app_port uses first EXPOSE when multiple exist" {
    printf "FROM node\nEXPOSE 3000\nEXPOSE 8080\n" > "$APP_DIR/Dockerfile"
    run detect_app_port "$APP_DIR"
    assert_success
    assert_output "3000 Dockerfile EXPOSE"
}

@test "detect_app_port Dockerfile with no EXPOSE falls through to package.json" {
    echo "FROM node:22" > "$APP_DIR/Dockerfile"
    cat > "$APP_DIR/package.json" <<'EOF'
{
  "dependencies": { "express": "^5.0.0" }
}
EOF
    run detect_app_port "$APP_DIR"
    assert_success
    assert_output "3000 express (package.json)"
}

@test "detect_app_port detects PORT= in scripts.start" {
    cat > "$APP_DIR/package.json" <<'EOF'
{
  "scripts": { "start": "PORT=6000 node server.js" }
}
EOF
    run detect_app_port "$APP_DIR"
    assert_success
    assert_output --partial "6000"
}
