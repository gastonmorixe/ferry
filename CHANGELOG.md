# Changelog

All notable changes to Ferry are documented here.

## [0.7.1] - 2026-03-28

### Changed
- **CLAUDE.md and /ship skill updated** with production branch-safety rules. Documents that branch switches destroy gitignored runtime config on this Dokku production machine and must never be done unprompted.
- Version bumped to 0.7.1

## [0.7.0] - 2026-03-27

### Added
- **Dokku app.json healthchecks for all 11 generators.** Every generated app now includes an `app.json` with a startup HTTP healthcheck that hits `/health` (or `/` for React/nginx). Dokku actively verifies the app responds before switching traffic during zero-downtime deploys, replacing the default 10-second blind wait. The healthcheck port is set explicitly to match `APP_PORT` (Dokku defaults to 5000 which would be wrong for most generators).
- **Docker HEALTHCHECK in all 11 generator Dockerfiles.** Runtime health monitoring using the best tool available per base image: `wget --spider` for Alpine (Express, Next.js, NestJS, React, Go, Fiber), `python -c urllib` for Python slim (FastAPI, Django), `ruby -e net/http` for Ruby slim (Rails), and `wget` (installed) for Debian slim (Actix, Axum). Start periods tuned per framework: 5s for Go/Rust/nginx, 10s for Node/Python, 15s for Django/Next.js, 20s for Rails.
- **Shared `app.json` template** in `generators/_shared/app.json.template` with `shared_app_json` helper in `helpers.sh`.
- **4 new Bats tests** for healthcheck coverage: app.json presence + valid JSON + correct port in all generators, HEALTHCHECK in all Dockerfiles, correct health path (`/health` vs `/` for React).
- **`network:set initial-network webserver`** during `ferry deploy` — ensures app containers start on the correct Docker network so nginx gets a routable upstream IP. Prevents 504 timeouts after reboots.

### Changed
- Rust generator runtime images (Actix, Axum) now install `wget` in the runtime stage for HEALTHCHECK support (~1 MB)
- Version bumped to 0.7.0

## [0.6.6] - 2026-03-27

### Fixed
- **Deploy sets `initial-network webserver` on every app.** Without this, Dokku app containers start on Docker's default bridge network, and nginx grabs the bridge IP (`172.17.0.x`) which is unreachable from cloudflared. After a reboot or restart, all apps would hang with 504/timeout because nginx upstream pointed to the wrong network. Now `ferry deploy` explicitly sets `network:set initial-network webserver` during app creation so the container starts on the correct network from the beginning.

## [0.6.5] - 2026-03-25

### Fixed
- **Handle empty config.yml gracefully.** Preflight now detects a 0-byte config.yml and regenerates it from Dokku state (previously only handled missing files, not empty ones). All Python YAML snippets guard against `yaml.safe_load` returning `None` — read-only functions default to empty dict, mutating functions error with a clear message instead of a Python traceback.

## [0.6.4] - 2026-03-25

### Changed
- **TUI app selector for remove, rebuild, and logs.** Instead of a bare text prompt ("App name to remove:"), these commands now show an arrow-key TUI menu listing all deployed Dokku apps, plus an "Enter manually..." option. Matches the select UI used everywhere else in Ferry.
- New reusable `tui_select_app` helper builds on `tui_select` — queries `dokku_list_apps`, falls back to manual entry when no apps exist.

## [0.6.3] - 2026-03-25

### Changed
- **Unified Ferry attribution across all 11 generators.** All response formats (HTML, JSON, XML, text) now display `Built with ⛵ Ferry v{version}` with a link to the GitHub repo. Previously the branding was inconsistent ("Deployed with Ferry" in some, missing version in others, boolean `true` in JSON/XML instead of version string).
  - **HTML**: Subtitle and footer now read "Built with ⛵ Ferry" with GitHub link
  - **JSON**: `"ferry"` field changed from `true` (boolean) to `"⛵ Ferry v{version}"` (string with version)
  - **XML**: `<ferry>` element changed from `true` to `⛵ Ferry v{version}`
  - **Text/Markdown**: Footer changed from "Deployed with Ferry" to `Built with ⛵ Ferry v{version}` with repo URL
- **New tests** for Ferry attribution: all generators checked for "Built with" text, ⛵ emoji, GitHub repo link, and version string (not boolean) in ferry field
- Test suite expanded from 32 to 34 tests
- Version bumped to 0.6.3

## [0.6.2] - 2026-03-25

### Changed
- **CI parallelized into 14 concurrent jobs.** Lint, unit tests, and generator structure tests each run in their own job. Docker smoke tests (build + HTTP 200) use a GHA matrix to run all 11 generators in parallel. Lint/unit failures now surface in ~30s instead of waiting 9+ min for Docker builds to complete.
- **Rust generators bumped to 1.87.** `unicode-segmentation` 1.13+ requires `is_multiple_of()` stabilized in Rust 1.87.
- **GHA actions updated to Node.js 24-compatible versions** (checkout v5, setup-python v6).
- **ShellCheck SC2015 excluded** in lint config (deliberate `set -e` guard pattern in TUI selector).
- Version bumped to 0.6.2

### Added
- `scripts/smoke-test-generator.sh` — standalone script to build and HTTP-test a single generator, used by CI matrix jobs.
- Bats `docker` test tags on Docker-heavy tests for filtered runs.

## [0.6.1] - 2026-03-24

### Fixed
- **Rails generator: HTTP 403 on deploy.** Generated Rails apps ran in `development` mode, where Rails 8's `HostAuthorization` middleware blocks unknown hostnames with 403. Fixed by adding `ENV RAILS_ENV=production` to the Dockerfile template, clearing `config.hosts` (Dokku/nginx handles host filtering), and generating `secret_key_base` at boot when not provided via environment.

### Added
- **Runtime HTTP smoke tests.** New Bats test verifies all 11 generators respond with HTTP 200 when started in Docker — not just that they build. Uses `docker run -d --init -P` with ephemeral ports and `curl --retry-all-errors` for reliable probing. Zero new dependencies.
- **Rails production-readiness tests.** Three targeted assertions: `RAILS_ENV=production` in Dockerfile, `config.hosts.clear` present, `secret_key_base` configured.
- **Docker runtime test helpers** in `generators_common.bash`: `docker_run_generated_app`, `wait_for_http_200`, `cleanup_test_containers`.
- **Work plan spec** at `dev/plans/2026-03-24T13-22-runtime-http-smoke-tests.md` documenting the approach selection (24 alternatives evaluated), technical design, and acceptance criteria.

### Changed
- Test suite expanded from 28 to 32 tests (3 Rails checks + 1 runtime HTTP test covering all 11 generators)
- Version bumped to 0.6.1

## [0.6.0] - 2026-03-23

### Added
- **`ferry new` command.** Scaffold new apps from 11 built-in templates. Two-step interactive TUI (category → framework) or fully scriptable with `ferry new myapp -t express -y`
- **11 app generators** across 5 languages, each producing a Dokku-ready project with Dockerfile, health endpoint, and request-info pages in HTML/JSON/XML/Text:
  - **TypeScript:** Express, NestJS, Next.js (SSR), React (Vite SPA)
  - **Python:** FastAPI, Django
  - **Ruby:** Rails
  - **Go:** net/http (standard library), Fiber
  - **Rust:** Axum, Actix-web
- **Generator infrastructure:** `generators/_shared/` with shared CSS (dark theme), response schema, .gitignore/.dockerignore templates per language, and `helpers.sh` (template copy, variable substitution, shared asset utilities)
- **Dynamic generator discovery:** Drop a `metadata.sh` + `generate.sh` in `generators/<id>/` and it appears in `ferry new --list` automatically
- **`ferry new` flags:** `--template/-t`, `--output/-o`, `--port/-p`, `--deploy`, `--no-deploy`, `--list/-l`, `--yes/-y`
- **Deploy chain:** `ferry new myapp -t express --deploy -y` scaffolds and deploys in one command
- **`FERRY_APPS_DIR` env var:** Configurable app storage directory (default: `$SCRIPT_DIR/apps`)
- **Test suite:** 118 bats-core tests across 9 test files (unit, generator validation, CLI integration)
  - Unit tests for: `cf_api_ok`, `cf_api_error`, `detect_app_port`, `cert_find_for_hostname`, `cert_list_zones`, `env_set`, `yaml_list_ingress`, `yaml_has_hostname`, `yaml_add_ingress`, `yaml_remove_ingress`, `yaml_validate`, `discover_generators`, `gen_index_by_id`
  - Generator tests: all 11 generators validated for file structure, placeholder substitution, Dockerfile EXPOSE, JSON validity, entry point presence, style.css presence
  - Integration tests: `ferry help`, `ferry new --list`, `ferry new` with all flags, name validation, custom output, existing-dir rejection
- **Source guard on `main()`** for testability — `source ./ferry` no longer triggers execution
- **`_ferry_init()` function** wrapping .env loading, trap setup, and cache initialization — keeps test environment clean

### Fixed
- **`cert_find_for_hostname` failed for 2-label hostnames** (e.g., `example.com`). The function stripped a label before checking, so `example.com` was never matched even when `example.com.cert` existed. Now checks the full hostname first.
- **`env_set` broke when values contained `|`** (sed delimiter collision). Replaced sed with awk for the update path. Also safe for `&`, `\`, `=`, and spaces in values.
- **Deploy chain always passed `-y`** regardless of user intent. `${YES:+"-y"}` expanded for `YES="false"` (non-empty string). Fixed to `$( $YES && echo "-y" )`.
- **App name regex allowed trailing hyphens** (`test-`), which are invalid in DNS. Regex now requires alphanumeric last character.
- **`SCRIPT_DIR` broke when invoked via symlink.** Added `readlink -f` to resolve the real script location.
- **`cmd_deploy` ignored `FERRY_APPS_DIR`.** Auto-detection used hardcoded `$SCRIPT_DIR/apps/` instead of the configurable variable. Now consistent with `cmd_new`.
- **Express Dockerfile didn't copy `style.css` to `dist/`** — returned 404 at runtime. Added explicit COPY in multi-stage build.
- **NestJS had no static file serving** — `style.css` returned 404. Added `app.useStaticAssets()` to `main.ts`.
- **React Dockerfile hardcoded port 80**, ignoring `--port` override. Now uses `{{APP_PORT}}` in both Dockerfile and nginx.conf.
- **Fresh scaffold deploys failed for multiple generators.** Node templates no longer assume a pre-generated `package-lock.json`; Rust templates now copy compile-time assets into the build stage and match Rust 2024 rules; Go Fiber now resolves/builds modules from a fresh scaffold; Rails installs the system package needed for `psych`; React now emits the TypeScript project files referenced by its root config.
- **Missing tunnel config could silently diverge from Dokku state.** Ferry now rebuilds `config.yml` from existing Dokku app domains when possible, restores missing ingress before deploy, and reports running apps without ingress as `unroutable` instead of fully healthy.

### Changed
- `ferry new` added to interactive menu (between List and Deploy)
- Help output updated with New Flags section and `ferry new` examples
- Version bumped to 0.6.0
- Generator coverage now includes real `docker build` smoke tests for every scaffolded app, plus dedicated recovery tests for Dokku-driven ingress rebuild behavior

## [0.5.1] - 2026-03-20

### Changed
- **Dokku bumped to 0.37.7**
- **Memory limits:** 256 MB `mem_limit` on cloudflared and dokku containers; `resource:limit --memory 256` applied per-app during deploy
- **Hardened .gitignore:** covers `.env.*`, `*.pem`, `*.key`, `*.crt`, `*.ovpn`, `*.kubeconfig`, `*.secret(s)`, `secrets/`
- **Docs updated:** fixed project name (`personal-webserver` to `ferry`), updated Docker/Dokku version references, added `mem_limit` to architecture docs

## [0.5.0] - 2026-03-06

### Changed
- **Renamed to Ferry.** `manage.sh` is now `ferry` with intro header, version display
- **DOKKU_HOSTNAME variable.** `docker-compose.yml` and deploy defaults use `${DOKKU_HOSTNAME}` instead of hardcoded domain
- **Credentials mount refactor.** credentials.json now mounted directly from `~/.cloudflared/` instead of copied into project
- **Config.yml management.** Gitignored with `.example` template; auto-generated from TUNNEL_ID if missing
- **Zone cert system.** `cert.pem` replaced by `tunnels/providers/cloudflare/<zone>.cert` files with hostname walk-up lookup
- **Removed all hardcoded domains.** Personal domains, tunnel IDs, account IDs stripped from code and docs
- **Added `.env.example`.** Documented template for all environment variables
- **Open-source ready.** Docs scrubbed of personal data, generic examples throughout

### Added
- `ferry_intro()`: tiered intro header with version and timestamp
- `cert_find_for_hostname()`: walks up hostname labels to find matching zone cert
- `cert_list_zones()` / `cert_check_all()`: zone cert discovery and reporting
- `_generate_default_config()`: auto-generates minimal `cloudflared/config.yml`
- DOKKU_HOSTNAME guard in deploy flow with interactive prompt when unset

### Removed
- Hardcoded domain from docker-compose.yml
- `cert.pem` from project root (replaced by zone cert directory)
- `cloudflared/credentials.json` from project (mounted from host)
- `cf_check_cert_pem()` (replaced by `cert_check_all()`)

## [0.4.0] - 2026-03-05

### Added
- **Modern TUI redesign.** Muted 256-color palette with 16-color and no-color fallbacks
- Arrow-key interactive menu selector (`tui_select`) with pointer, j/k vim keys,
  non-TTY numbered-list fallback
- New display primitives: `section_header()` (trailing line), `kv()`/`kv_color()`
  (aligned key-value pairs), `box()` (rounded corners), `prompt()` (input),
  `dim()` (secondary text), `spinner_start()`/`spinner_stop()` (braille dot animation)
- Tiered terminal capability detection (`_COLOR_TIER`, `_IS_TTY`, `_term_width`)
- Status icons in app tables: running, pending/stopped

### Changed
- Color palette: sage green (success), muted red (error), warm amber (warn),
  steel blue (info), soft purple (accent), dark gray (chrome/borders)
- All commands restyled with `section_header`, `kv`, `box`, `prompt` primitives
- Interactive menu uses arrow-key selector instead of numbered list
- Auth warning banners use `box()` with rounded corners
- Deploy/remove completion blocks use `box()` for emphasis
- Confirm prompts use pointer with bold Y / plain N
- Help output organized into sections with command chrome ($ prefix)
- Removed old ANSI color constants (RED/GREEN/YELLOW/BLUE/CYAN)

## [0.3.0] - 2026-03-05

### Added
- **Full auto-deploy from GitHub.** Single command goes from repo to live site
  - `./manage.sh deploy myapp -r owner/repo -H app.example.com -y`
- New deploy flags: `-r/--repo`, `-b/--branch`, `-d/--dir`, `--no-push`
- `detect_app_port()`: auto-detects port from Dockerfile EXPOSE, package.json
  frameworks (next/nuxt/remix/fastify/express at 3000), scripts.start, or Procfile
- `repo_clone()`: clones via `gh`, normalizes URLs, validates owner/repo format
- `dokku_push()`: auto-detects branch, manages dokku remote, pushes to Dokku
- `post_deploy_verify()`: retries HTTP check (5x3s) after push, warns on timeout
- Adaptive step numbering (5 to 7 steps depending on clone/push)
- Deferred port detection when cloning (detects after clone, before Dokku create)
- Buildpack warning when no Dockerfile or package.json found
- Live HTTP verification after successful push
- Deploy guide documentation (`docs/deploy-guide-github-to-live.md`)

### Changed
- Deploy completion message adapts: "live at" / "push manually" / "next steps"
- Help output updated with new flags and examples
- Port default described as "auto-detect, fallback: 5000" instead of just "5000"

## [0.2.0] - 2026-03-03

### Added
- Non-interactive mode with `-y/--yes` flag
- CLI flags for deploy: `-H/--hostname`, `-p/--port`
- CLI flag for login: `-t/--token`
- Pipe-safe output (colors auto-disabled when stdout is not a TTY)
- TTY detection in `confirm()` and `confirm_name()`

### Changed
- Polish pass on UX messaging and error output

## [0.1.0] - 2026-03-02

### Added
- Cloudflare API layer (`cf_api`, `cf_resolve_zone_id`, DNS CRUD operations)
- API token authentication with multi-method verify (user/account/zone fallback)
- Account ID auto-discovery and caching
- Auth system: startup banner + hard gates for DNS operations
- `login` command with guided token setup, permission check, cert.pem audit
- DNS creation via API first, cert.pem fallback for zone-scoped domains

### Changed
- Refactored auth from single cert.pem to API-first approach

## [0.0.1] - 2026-03-02

### Added
- Initial release
- Docker Compose stack (cloudflared + Dokku)
- `manage.sh` with interactive menu
- Commands: deploy, remove, status, list, reload, rebuild, logs, help
- YAML operations via Python3/PyYAML with backup and catch-all validation
- Cloudflared restart with tunnel connection polling
- Cross-validation warnings in status dashboard
