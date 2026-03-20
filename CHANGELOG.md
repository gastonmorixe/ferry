# Changelog

All notable changes to Ferry are documented here.

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
