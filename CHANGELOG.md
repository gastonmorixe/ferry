# Changelog

All notable changes to Ferry are documented here.

## [Unreleased]

### Fixed
- **`ferry login` permission probe:** Split tunnel checks into **Tunnel:Read** (list) and **Tunnel:Edit** (read tunnel configuration). Zone-scoped tokens that could list an empty tunnel set no longer pass as fully authorized.
- **`ferry status` ingress errors:** Tunnel config API failures show one actionable warning instead of repeated raw `ERROR: [{'code':…}]` lines. Ingress is fetched once per status run and cached for app routing checks.
- **macOS generator templates:** `sed -i` in shared helpers now uses a portable `sed_inplace` wrapper (BSD sed requires `-i ''`), fixing `ferry new` on macOS.

### Changed
- **Least-privilege Dokku compose:** Removed default `pid: host` from `docker-compose.yml`. Generated apps already use HTTP path healthchecks in `app.json`; Dokku's default listening probe may warn without host PID namespace or `CAP_SYS_ADMIN`, but that warning is non-fatal when the HTTP check passes.

### Docs
- Clarified HTTP vs listening healthchecks in deploy guide, troubleshooting, and deploying-apps.

### Tests
- Added `test/unit/cf_permissions.bats` for permission probing and ingress cache behavior.

## [0.12.2] - 2026-07-31

### Fixed
- **Explicit noninteractive tunnel names now select safely.** `ferry login -y --tunnel-name <name>` binds only an exact active name match. If no matching tunnel exists, it creates the requested remotely managed tunnel rather than adopting the sole available tunnel or arbitrarily choosing from multiple tunnels.
- **Explicit names protect configured tunnel IDs.** When `--tunnel-name` is supplied, a configured `TUNNEL_ID` whose verified name differs is cleared in memory and re-resolved by exact name/create. Stale or deleted configured IDs take the same safe fallback. Login without an explicit tunnel name retains its prior selection behavior.

### Tests
- Added mocked regression coverage for sole-mismatch create, multi-mismatch create, exact-name bind, and configured foreign-ID reconfiguration. No Cloudflare API, DNS, login, VM, or deployment action was performed for this release.

## [0.12.1] - 2026-07-31

### Changed
- **Dokku now tracks current stable by Ferry policy.** The compose default is `dokku/dokku:latest`, replacing the stale `0.37.7` image reference. This is a maintenance-selection policy, not a reproducible target-VM apply pin.
- **Target apply remains digest-gated.** Before any target VM `docker compose up`, resolve and record `dokku/dokku:latest@sha256:…` in the approved BOM/rehearsal evidence and review that immutable result. This release does not perform a VM apply or claim the BOM/version-freeze gate is closed.
- **Cloudflared remains separately deferred.** `cloudflare/cloudflared:latest` is unchanged; its immutable digest must be resolved and recorded at the same target BOM/apply gate. No Cloudflare API, DNS, Tunnel, login, deployment, VM, or R2 action is part of this release.

## [0.12.0] - 2026-07-31

### Added
- **`ferry login` host-tunnel bootstrap:** After saving the API token and discovering `CF_ACCOUNT_ID`, login ensures a remotely-managed Cloudflare Tunnel (`config_src: cloudflare`) via the API. It keeps a valid `TUNNEL_ID` + `TUNNEL_TOKEN` pair, fetches a missing connector token when only the ID is set, or lists/picks/creates a named tunnel (default name `ferry`). Values are written to `.env`. If `cloudflared` is already running, it is restarted so the new token applies.
- **`ferry login --tunnel-name <name>`** — preferred tunnel name for create/select (default: `ferry`).

### Changed
- API token for login must include **Account → Cloudflare Tunnel → Edit** (no longer optional Tunnel:Read-only). Zone DNS Edit + Zone Read remain required for deploy DNS.
- Compose connector auth is **`TUNNEL_TOKEN`** (`tunnel run`). Credentials live in Ferry `.env`, not a mounted `~/.cloudflared/<id>.json` or root-owned secret file.
- Host `cloudflared` CLI is not required for tunnel bootstrap.

### Docs
- Rewrote [docs/tunnel-id.md](docs/tunnel-id.md) to lead with `ferry login` and remove the old "product gap" that claimed login did not set `TUNNEL_ID`.
- Updated [docs/initial-setup.md](docs/initial-setup.md), [README.md](README.md), and [docs/deploying-apps.md](docs/deploying-apps.md) for the login → tunnel → deploy flow.

## [0.11.0] - 2026-05-17

### Fixed
- **Privacy detection no longer treats every tunneled request as WARP/proxy:** The previous code interpreted Cloudflare's `cf-warp-tag-id` header as evidence the client was on WARP and therefore proxied. That header is actually a Cloudflare-Tunnel correlation ID injected by `cloudflared` on **every** request reaching the origin (verified with two real-world samples sharing the same UUID), so the check fired 100% of the time and `cloudflare.warp` was always `true`. The misinterpretation also drove `client.privacy.proxy` to `true` for residential and mobile users, since the fallback hop-count check (`x-forwarded-for > 1`) never fires through a Tunnel either.
- **Country detection now prefers `cf-ipcountry` over the local CSV:** Some mobile carriers operate the same ASN across multiple neighboring countries; `sapics/ip-location-db` inherits the ASN's PeeringDB "home" country, which over-flags a sizeable slice of the carrier's subscribers as being in the wrong country. Cloudflare's `cf-ipcountry` is realtime and authoritative at the routing layer, so it now wins over the snapshot CSV. The CSV remains as a fallback for requests without a Cloudflare hop.

### Changed (breaking — schema)
- **`client.privacy` is now a structured classification, not three booleans:** New shape:
  ```json
  {
    "tor": false, "vpn": false, "hosting": false,
    "mobile": false, "residential": false, "forwarded": false,
    "confidence": "low | medium | high",
    "sources": ["x4bnet-datacenter", "peeringdb:NSP", "rdns:carrier", "..."]
  }
  ```
  Each boolean is derived from a named, auditable signal source. `confidence` is `high` when a hard list lookup hits (Tor / X4BNet CIDR), `medium` when only ASN-level (PeeringDB) or rDNS heuristics fire, `low` when nothing matched.
- **`cloudflare.warp` removed from response:** It was never a real WARP signal. Apps that need WARP detection should look at `request.cf.asOrganization === 'Cloudflare'` from a Worker context — not available to Tunnel origins.
- **`generators/_shared/schema/response-schema.json`** updated to the new privacy shape. Only the Next.js generator emits the new schema in v0.11.0; the other 10 generators continue to emit the legacy `{proxy, hosting, mobile}` shape and will be brought to parity in subsequent releases.

### Added
- **Four new vendored data sources** under `generators/_shared/assets/ipdb/`:
  - `x4bnet-vpn-ipv4.txt` — 10,734 commercial-VPN CIDRs from [X4BNet/lists_vpn](https://github.com/X4BNet/lists_vpn) (CC0, daily-updated)
  - `x4bnet-datacenter-ipv4.txt` — 41,981 datacenter/hosting CIDRs from the same project
  - `tor-exits.txt` — 1,270 active Tor exit IPs from [`check.torproject.org/torbulkexitlist`](https://check.torproject.org/torbulkexitlist) (official)
  - `peeringdb-asn-types.json` — 24,601 ASN→`info_type` mappings from [PeeringDB](https://www.peeringdb.com/api/net) (`Cable/DSL/ISP`, `NSP`, `Content`, `Enterprise`, etc.)
- `scripts/update-ipdb-assets.sh` refreshes all four sources atomically, tracks per-source SHAs and `fetchedAt` timestamps in `ipdb-source.json`, and short-circuits when both upstream commit SHAs match the vendored copy.
- **rDNS pattern matching** as a medium-confidence signal: strict mobile indicators (`.mobile.`, `-lte-`, `.5g.`), generic telco hostname patterns, and residential broadband markers (`.dyn.`, `.cable.`, `.fios.`). Mobile carriers that also serve fixed-line require a mobile UA to flip the `mobile` bit.
- **Runtime auto-refresh** in the Next.js template fetches updated datasets independently per source (sapics: daily, X4BNet: daily, Tor: hourly, PeeringDB: weekly) with atomic file replacement and in-memory cache invalidation.

### Honest limits (documented in the rendered UI)
- Residential proxies (Bright Data, Oxylabs, IPRoyal) cannot be detected from HTTP signals alone — they egress from real consumer ISPs and need active TCP/TLS fingerprinting that Cloudflare strips at the edge. The Privacy section in the rendered HTML calls this out so users aren't misled by a green `residential: true` badge on a residential-proxy connection.

### Verified across the four classification paths
- **Commercial VPN exit on a hosting ASN** → `hosting: true, confidence: high, sources: [x4bnet-datacenter, peeringdb:NSP]` ✓
- **Mobile carrier on a Cable/DSL/ISP ASN with carrier rDNS + mobile UA** → `mobile: true, sources: [peeringdb:Cable/DSL/ISP, rdns:carrier]` ✓ (country now derived from `cf-ipcountry` rather than the ASN's CSV home country)
- **Tor exit node** → `tor: true, vpn: true, confidence: high, sources: [tor-exits, peeringdb:Educational/Research]` ✓
- **Residential broadband ISP** → `residential: true, confidence: medium, sources: [peeringdb:Cable/DSL/ISP]` ✓

## [0.10.0] - 2026-05-17

### Changed
- **DNS is now inherited from the host instead of hardcoded.** Removed `dns: [172.17.0.1]` from both `cloudflared` and `dokku` services in `docker-compose.yml`. Containers now inherit `/etc/resolv.conf` via Docker's embedded resolver (`127.0.0.11`), so Ferry works with any host DNS setup — router DHCP, systemd-resolved, NextDNS, Pi-hole, corporate — without any compose tweak. The `172.17.0.1` value pinned to a NextDNS listener that, once removed from the host, caused cloudflared to crash-loop (`lookup ... on 127.0.0.11:53: server misbehaving`) and take all tunneled apps offline.
- **`ferry status` DNS section is adaptive, not hardcoded.** Replaced the `NextDNS` row that probed `127.0.0.1` and `172.17.0.1` with two new rows:
  - `Host DNS` — discovers active nameservers via systemd-resolved's authoritative surface (`resolvectl dns`) and probes each with `dig +short`. Avoids parsing `/etc/resolv.conf`, which on many distros is only a compatibility stub written by NetworkManager (the `resolv.conf mode: foreign` case). Falls back to `/run/systemd/resolve/resolv.conf` and then `/etc/resolv.conf` only on hosts without systemd-resolved.
  - `Container DNS` — spins up an ephemeral `busybox` container on the `webserver` network and resolves `argotunnel.com` (the exact name cloudflared depends on). Catches the precise failure mode that takes the tunnel offline, regardless of which resolver is in use.

### Added
- `_detect_host_resolvers`, `_probe_resolver`, `_probe_container_dns` helpers in `ferry.sh`.
- Docs: `docs/troubleshooting.md → Custom DNS upstream (optional)` documents the per-service `dns:` override for the rare case where the host resolver lives on `127.0.0.1` and can't be moved.

### Removed
- All hardcoded `172.17.0.1` and NextDNS-specific instructions from `docs/troubleshooting.md`, `docs/initial-setup.md`, `docs/architecture.md`, and `docs/deploy-guide-github-to-live.md`. The NextDNS-on-Docker-bridge setup is no longer the canonical path; it's mentioned only as one possible cause when the host resolver is unreachable from containers.

## [0.9.1] - 2026-04-21

### Fixed
- **`ferry new <name>` → deploy on a fresh Dokku no longer aborts with `Failed to verify existing ingress before deploy`.** When Dokku had zero apps, `dokku apps:list` emitted a warning line (` !     You haven't deployed any applications yet`) that `dokku_list_apps` returned verbatim as a fake app name. Downstream, `sync_missing_ingress_from_dokku` then called `dokku domains:report` against that non-existent app and failed the deploy preflight. The same bug also caused `ferry status` and `ferry list` to render a phantom row containing the warning text.
- `dokku_list_apps` now filters Dokku's banner prefixes (`=====>`, `----->`, ` !`). Dokku app names can never start with these characters, so the filter is safe for populated installs.

### Added
- Regression tests in `test/unit/dokku_recovery.bats` covering both the empty-Dokku path and the populated-list path for `dokku_list_apps`.
- Troubleshooting entry in `docs/troubleshooting.md` for the `Failed to verify existing ingress before deploy` symptom.

## [0.9.0] - 2026-04-17

### Added
- **`ferry tune <app>` command** — adjust per-app memory limits and Node.js V8 heap without redeploying. Flags: `-m/--memory N` (container memory MB), `--heap N` (override V8 `--max-old-space-size`), `--runtime node|python|go|ruby|rust` (enables heap auto-tune for Node). Interactive by default; non-interactive with `-y`. No image rebuild, no cleanup — Dokku storage mounts, persistent volumes, and database links are preserved across the `ps:restart`.
- **`ferry deploy -m/--memory N` flag** — set the container memory limit at deploy time (default 256 MB, prompted interactively with a 512+ recommendation when a Node runtime is detected).
- **Runtime persistence via Dokku config.** Deploy now sets `FERRY_RUNTIME`, `FERRY_MEMORY`, and (for Node apps) `NODE_OPTIONS=--max-old-space-size=<mem-48>` so V8 garbage-collects aggressively before hitting the cgroup wall instead of aborting with SIGABRT / being SIGKILLed by the kernel OOM-killer.
- **`ferry_calc_node_heap()`** helper — computes V8 heap cap as `memory - 48` MB with a 64 MB floor.
- **`ferry_detect_runtime_from_dir()`** helper — maps project files to runtime tag (`package.json`→node, `pyproject.toml`/`requirements.txt`/`Pipfile`→python, `go.mod`→go, `Cargo.toml`→rust, `Gemfile`→ruby).

### Fixed
- **Node apps no longer crash with `FATAL ERROR: Reached heap limit Allocation failed — JavaScript heap out of memory`** under the default 256 MB container limit. New deploys of Node apps automatically receive `NODE_OPTIONS=--max-old-space-size=208`, leaving ~48 MB for V8 internals, code, and native allocations. Existing apps can migrate with `ferry tune <app> -m 512 --runtime node -y`.

### Changed
- Interactive menu gains a **Tune** entry (between Rebuild and Logs).
- `cmd_help` documents the tune command, tune flags, and the `-m/--memory` deploy flag with a new example line.

## [0.8.0] - 2026-03-29

### Changed
- **Tunnel ingress is now managed via the Cloudflare API instead of a local config.yml file.** This eliminates the entire class of bugs that plagued Ferry for months — file corruption, Docker directory placeholders, config.yml disappearing on reboot, and ~50 lines of preflight recovery code. cloudflared now runs as a remotely-managed tunnel using `TUNNEL_TOKEN`, with zero local volume mounts for configuration.
- **docker-compose.yml simplified.** cloudflared no longer mounts config.yml or credentials.json volumes. Uses `TUNNEL_TOKEN` environment variable and `tunnel run` command. No bind mounts means no file-level mount bugs.
- **`yaml_*` functions now call the Cloudflare API** (`GET`/`PUT /accounts/{id}/cfd_tunnel/{id}/configurations`) instead of reading/writing a local YAML file. Function names retained for backward compatibility. No more Python/PyYAML dependency for config operations.
- **Preflight simplified.** Removed ~50 lines of config.yml recovery code (directory placeholder detection, empty file detection, rebuild-from-Dokku logic). Ingress state lives on Cloudflare's servers now.

### Removed
- `_generate_default_config()` — no longer needed (no local config file)
- `_generate_config_from_dokku()` — no longer needed (ingress managed via API)
- `CONFIG_FILE` variable — no longer used
- config.yml volume mount from docker-compose.yml
- credentials.json volume mount from docker-compose.yml

### Added
- `_tunnel_get_ingress()` — reads tunnel ingress from Cloudflare API
- `_tunnel_put_ingress()` — writes tunnel ingress to Cloudflare API
- `TUNNEL_TOKEN` in `.env` for remotely-managed tunnel authentication

## [0.7.2] - 2026-03-28

### Fixed
- **cloudflared dies on every reboot — for real this time.** This bug has persisted for months across multiple "fix" attempts. Every single reboot left all deployed apps unreachable because cloudflared failed to start. Here is the full technical postmortem:

  **The symptom:** After any Pi reboot, `cloudflared` container exits with code 127. The error: `error mounting "/home/pi/ferry/tunnels/providers/cloudflare/config.yml" to rootfs at "/etc/cloudflared/config.yml": not a directory`. All apps served through the tunnel go down and stay down until someone manually runs `ferry`.

  **The root cause — a Docker bind-mount design flaw:** The `docker-compose.yml` mounted a single **file** (`config.yml:/etc/cloudflared/config.yml:ro`). Docker has a well-known behavior: when the daemon restarts and tries to restore a container, if the bind-mount source file is momentarily unavailable (race condition during boot — filesystem not fully ready, inode timing, etc.), Docker silently creates a **directory** at that path instead of a file. Once `config.yml` becomes a directory, the mount fails with "not a directory" and the container cannot be created at all. The `restart: unless-stopped` policy is useless here because container **creation** itself fails — Docker never gets to the runtime phase where restart policies apply.

  **Why previous fixes didn't work:** Ferry already had code to detect when `config.yml` was a directory and fix it (preflight checks since v0.6.5). But this only runs when a user interactively launches `ferry`. The problem happens at boot time, before anyone runs Ferry. The detection code was treating the symptom (directory placeholder), not the cause (file-level bind mount). Additionally, `cloudflared_restart()` used `docker compose restart` which cannot recover a container that failed at the OCI create stage — it only works on containers that are already running or cleanly stopped.

  **The actual fix — two changes:**

  1. **Mount the directory, not the file.** Changed docker-compose.yml from mounting `config.yml` (a file) to mounting the parent directory `tunnels/providers/cloudflare/` → `/etc/cloudflared/tunnel/` (a directory). Docker never creates directory placeholders for directory bind-mounts — a directory mounted to a directory is always valid. The cloudflared command was updated to read from `/etc/cloudflared/tunnel/config.yml`. The credentials file mount (`${TUNNEL_ID}.json:/etc/cloudflared/credentials.json`) is unaffected and stays as-is (it lives in `~/.cloudflared/` which is always present).

  2. **`cloudflared_restart()` now uses `up -d --force-recreate` instead of `restart`.** `docker compose restart` sends SIGHUP to a running container — it cannot recover a container stuck in "Created" or "Exited (127)" state from a failed OCI mount. `docker compose up -d --force-recreate` tears down whatever exists and rebuilds the container from the compose definition, which handles any state.

  **Timeline of the bug:** This issue has been present since Ferry first used a file-level bind mount for `config.yml` in docker-compose.yml. It manifested on every reboot of the Raspberry Pi 5. Previous attempts added preflight directory detection (v0.6.5), empty-config recovery (v0.6.5), and config rebuild from Dokku state — all of which helped with interactive recovery but none prevented the boot-time failure. The underlying cause (Docker's handling of file bind-mounts during daemon restart) was never addressed until now.

### Changed
- `docker-compose.yml`: cloudflared config volume changed from file mount to directory mount (`./tunnels/providers/cloudflare:/etc/cloudflared/tunnel:ro`)
- `docker-compose.yml`: cloudflared command updated to `tunnel --config /etc/cloudflared/tunnel/config.yml run`
- `docker-compose.yml`: `webserver` network and `dokku-data` volume marked `external: true` — eliminates ownership warnings after project rename from `personal-webserver` to `ferry`
- `docker-compose.yml`: added `pid: host` to Dokku service — fixes Dokku's "port listening check" healthcheck which requires host PID namespace access to `nsenter` into app containers
- `cloudflared_restart()`: replaced `docker compose restart` with `docker compose up -d --force-recreate` for robust recovery from any container state
- `ferry deploy`: now sets `network:set initial-network webserver` on every app so containers start on the correct Docker network and nginx gets a routable upstream IP (prevents 504 timeouts after reboots)
- Version bumped to 0.7.2

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
