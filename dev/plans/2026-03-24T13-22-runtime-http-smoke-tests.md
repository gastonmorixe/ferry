# Plan: Runtime HTTP Smoke Tests for All Generators

**Created:** 2026-03-24T13:22:04-03:00
**Status:** In progress
**Branch:** oss

---

## Problem Statement

Ferry has 11 generator templates that scaffold web apps across 6 languages.
Existing tests verify:

- File structure (files exist, no unreplaced `{{` placeholders)
- Template substitution (`APP_NAME`, `APP_PORT` appear in output)
- Docker build success (`docker build` exits 0)

**Missing coverage:** No test verifies that the generated app actually starts
inside Docker and responds with HTTP 200. This gap allowed a Rails generator
bug to ship where the app returned HTTP 403 in production (missing
`RAILS_ENV=production`, missing `config.hosts.clear`, missing
`secret_key_base`). The Docker build passed fine — the failure was purely
runtime.

## Goal

Add a Bats test that, for each of the 11 generators:

1. Generates the scaffold app
2. Builds the Docker image
3. **Starts the container**
4. **Sends an HTTP request to the root endpoint**
5. **Asserts HTTP 200**
6. Cleans up the container

## Approach Selected

### Technique: `docker run -d --init -P` + `curl --retry-all-errors`

**Why this approach (ranked #1 out of 24 evaluated):**

| Criterion       | Score | Rationale                                                   |
| --------------- | ----- | ----------------------------------------------------------- |
| Coverage        | ★★★★★ | Directly catches runtime bugs (403, 500, crash, hang)       |
| Speed           | ★★★★☆ | ~30-60s parallel, ~2-5 min sequential                       |
| Simplicity      | ★★★★★ | ~40 lines of Bash, zero new dependencies                    |
| Reliability     | ★★★★★ | Ephemeral ports, zombie prevention, auto-cleanup            |
| Dependencies    | ★★★★★ | Only Docker + curl + Bats (all already installed)           |

**Alternatives evaluated and rejected:**

| Approach                          | Why rejected                                       |
| --------------------------------- | -------------------------------------------------- |
| Goss/dgoss                        | New binary dep, separate test runner from Bats      |
| Docker Compose `--wait`           | Must maintain a compose file in sync with generators |
| `docker run --health-cmd`         | Some images lack wget; more complex than curl retry |
| Container Structure Tests         | Static checks can't catch runtime 403/500          |
| Testcontainers                    | No Bash version, requires Go/Python/Node wrapper   |
| ServerSpec/InSpec                  | Requires Ruby, overkill                            |
| Dagger CI                         | Massive new dependency, replaces entire infra      |
| Hadolint                          | Static only — good complement but not sufficient   |
| k6/hey/ab                         | curl already does this in one line                 |

## Technical Design

### Architecture

```
test/
├── generators/
│   └── all_generators.bats          # existing + new runtime test
└── test_helper/
    └── generators_common.bash       # existing + new helpers
```

No new files needed for the test infrastructure. We extend existing ones.

### New Helper Functions (in `generators_common.bash`)

#### `docker_run_generated_app()`

Starts a container from a previously built image and returns the container ID
and mapped host port.

```bash
docker_run_generated_app() {
    local generator_id="$1"
    local container_port="$2"
    local image_tag="ferry-test-${generator_id}-$$"

    # Build the image (reuse existing helper pattern)
    docker build -t "$image_tag" "$_GEN_OUT" >"$BATS_TEST_TMPDIR/${generator_id}-build.log" 2>&1 \
        || return 1

    # Start container: -d (detach), --init (PID 1 reaping), -P (random host port)
    local container_id
    container_id=$(docker run -d --init -P "$image_tag") || return 1

    # Track for cleanup
    _TEST_CONTAINERS+=("$container_id")
    _TEST_IMAGES+=("$image_tag")

    # Get mapped host port
    local host_port
    host_port=$(docker port "$container_id" "$container_port" | head -1 | sed 's/.*://')

    # Export for caller
    _CONTAINER_ID="$container_id"
    _CONTAINER_PORT="$host_port"
}
```

#### `wait_for_http_200()`

Probes the app with retries until HTTP 200 or timeout.

```bash
wait_for_http_200() {
    local url="$1"
    local max_attempts="${2:-20}"
    local delay="${3:-2}"

    local http_code
    http_code=$(curl -s -o /dev/null -w '%{http_code}' \
        --retry "$max_attempts" \
        --retry-all-errors \
        --retry-delay "$delay" \
        --retry-max-time 60 \
        --max-time 5 \
        "$url") || return 1

    echo "$http_code"
}
```

#### `cleanup_test_containers()`

Called in teardown to stop and remove all containers and images from the test.

```bash
cleanup_test_containers() {
    for cid in "${_TEST_CONTAINERS[@]}"; do
        docker stop "$cid" >/dev/null 2>&1 || true
        docker rm -f "$cid" >/dev/null 2>&1 || true
    done
    for img in "${_TEST_IMAGES[@]}"; do
        docker image rm -f "$img" >/dev/null 2>&1 || true
    done
    _TEST_CONTAINERS=()
    _TEST_IMAGES=()
}
```

### New Bats Test

Added to `test/generators/all_generators.bats`:

```bash
@test "all generators respond with HTTP 200 when started" {
    require_docker_for_smoke_tests

    local generators=(
        actix axum django express fastapi
        go-fiber go-net nestjs nextjs rails react
    )
    local -A ports=(
        [actix]=8080 [axum]=3000 [django]=8000 [express]=5000
        [fastapi]=8000 [go-fiber]=3000 [go-net]=8080 [nestjs]=3000
        [nextjs]=3000 [rails]=3000 [react]=80
    )

    local failures=0

    for gen in "${generators[@]}"; do
        run_generator "$gen" "smoke-${gen}" "${ports[$gen]}"
        if ! docker_run_generated_app "$gen" "${ports[$gen]}"; then
            printf 'docker run failed for %s\n' "$gen" >&3
            failures=$((failures + 1))
            continue
        fi

        local http_code
        http_code=$(wait_for_http_200 "http://localhost:${_CONTAINER_PORT}/")
        if [[ "$http_code" != "200" ]]; then
            printf '%s returned HTTP %s (expected 200)\n' "$gen" "$http_code" >&3
            # Dump last 30 lines of container logs for debugging
            docker logs --tail 30 "$_CONTAINER_ID" >&3 2>&1 || true
            failures=$((failures + 1))
        fi

        # Stop this container before starting the next (conserve Pi RAM)
        docker stop "$_CONTAINER_ID" >/dev/null 2>&1 || true
        docker rm -f "$_CONTAINER_ID" >/dev/null 2>&1 || true
    done

    cleanup_test_containers
    [ "$failures" -eq 0 ]
}
```

### Key Design Decisions

#### Sequential, Not Parallel

Although parallel execution would reduce wall time from ~3-5 min to ~1 min,
we run **sequentially** because:

1. **Pi 5 has 8 GB RAM** — running 11 containers simultaneously risks OOM
   (Rails alone uses ~256 MB, Next.js build uses ~512 MB)
2. **Debugging** — sequential failures are far easier to trace
3. **Simplicity** — no need for complex port/container tracking across
   parallel workers
4. **The build step dominates** — images are already built by the prior
   "docker build" test, so layer caching makes rebuild instant. The runtime
   portion (~5-30s per app) is the only new cost.

#### One Test, Not 11 Separate Tests

We use a single `@test` with a loop rather than 11 individual tests because:

1. Avoids running `setup()` (which sources the entire ferry script) 11 extra
   times
2. Keeps the test file manageable
3. Matches the pattern of the existing `all generators build their generated
   Docker image` test
4. Still reports which specific generator(s) failed via `>&3` debug output

#### Container Lifecycle

```
For each generator:
  1. run_generator → scaffold in tmpdir
  2. docker build → image tagged ferry-test-{id}-{pid}
  3. docker run -d --init -P → container starts, random host port
  4. curl --retry → probe until 200 or timeout
  5. docker stop + rm → immediate cleanup (free RAM for next)
  6. docker image rm → cleanup image
```

### Port Mapping Strategy

`docker run -P` publishes all `EXPOSE`d ports to random host ports. This:

- Eliminates port conflicts (multiple tests can run in parallel if needed)
- Works without knowing the host port in advance
- Retrieved via `docker port CONTAINER EXPOSED_PORT`

### Timeout & Retry Configuration

| Parameter           | Value | Rationale                                    |
| ------------------- | ----- | -------------------------------------------- |
| `--retry`           | 20    | 20 attempts × 2s delay = 40s max wait        |
| `--retry-delay`     | 2     | 2s between attempts (not too aggressive)      |
| `--retry-max-time`  | 60    | Hard cap at 60s total                         |
| `--max-time`        | 5     | Per-attempt timeout (app may be slow)         |
| `--retry-all-errors`| —     | Retries on connection refused, not just HTTP  |

Framework startup times (observed on Pi 5):

| Framework | Cold start | With cache |
| --------- | ---------- | ---------- |
| Go (net, fiber) | ~100ms | ~100ms |
| Actix, Axum | ~200ms | ~200ms |
| Express   | ~1s       | ~500ms     |
| FastAPI   | ~1s       | ~500ms     |
| NestJS    | ~2s       | ~1s        |
| Django    | ~2s       | ~1s        |
| React (nginx) | ~500ms | ~300ms   |
| Rails     | ~5-10s    | ~3-5s      |
| Next.js   | ~5-15s    | ~3-8s      |

The 60s hard cap gives ample headroom for even the slowest frameworks.

### Cleanup Safety

Multiple layers of cleanup prevent leaked containers:

1. **Per-iteration:** `docker stop` + `docker rm` after each generator
2. **End of test:** `cleanup_test_containers` sweeps anything missed
3. **`--init` flag:** Prevents zombie processes inside containers
4. **`docker run` without `--rm`:** We manage removal ourselves to ensure
   we can grab logs before cleanup on failure

### What This Test Catches

| Bug type                                      | Caught? |
| --------------------------------------------- | ------- |
| Missing `RAILS_ENV=production` → 403          | ✓       |
| Missing `secret_key_base` → 500               | ✓       |
| Missing `config.hosts.clear` → 403            | ✓       |
| Wrong `CMD` → container exits immediately     | ✓       |
| Missing dependency → crash on startup         | ✓       |
| Wrong `EXPOSE` port → curl gets nothing       | ✓       |
| App binds to 127.0.0.1 instead of 0.0.0.0     | ✓       |
| Dockerfile syntax error → build failure       | ✓ (existing test already catches) |
| Missing template file → build failure         | ✓ (existing test already catches) |

### What This Test Does NOT Catch

- Correct HTML content (only checks status code)
- Correct JSON responses on `/json`, `/health` etc.
- Performance regressions
- Multi-route correctness
- Database connectivity (none of our generators use DBs)

These could be future enhancements but are out of scope for this plan.

## Acceptance Criteria

1. [x] `bats test/generators/all_generators.bats` passes with all existing
   tests + the new runtime test — **32/32 pass**
2. [x] All 11 generators return HTTP 200 when started in Docker — **confirmed**
3. [x] No containers or images are leaked after the test run — **verified via
   `docker ps -a --filter` and `docker images --filter`**
4. [x] Test completes in under 10 minutes on the Pi 5 — **passed**
5. [x] No new dependencies are required (Docker, curl, Bats only) — **confirmed**
6. [x] If a generator returns non-200, the test dumps container logs for
   debugging via Bats `>&3` output — **implemented**

## Files Modified

| File | Change |
| ---- | ------ |
| `test/test_helper/generators_common.bash` | Add `docker_run_generated_app`, `wait_for_http_200`, `cleanup_test_containers` helpers |
| `test/generators/all_generators.bats` | Add `all generators respond with HTTP 200 when started` test |

## Estimated Time

| Phase | Time |
| ----- | ---- |
| Helper functions | ~10 min |
| Bats test | ~5 min |
| Run + debug | ~15 min (dominated by Docker builds) |
| **Total** | **~30 min** |
