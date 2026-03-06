# Ferry

Deploy web apps via **Dokku** + **Cloudflare Tunnel**. Git-push deploys with automatic DNS, ingress, and TLS — no open ports, no public IP.

## Architecture

```
                                   ┌──────────────────────────────────────────────────┐
                                   │                     <device>                     │
                                   │                                                  │
Internet ──► Cloudflare Edge ──────┼──► cloudflared ──► dokku:80 ──► app containers   │
                                   │    (tunnel)        (nginx)     (test-app, ...)   │
                                   │                                                  │
                                   │    Host:                                          │
                                   │      /usr/local/bin/dokku  (wrapper command)      │
                                   │      git push via SSH :3022                       │
                                   │      NextDNS on 127.0.0.1 + 172.17.0.1           │
                                   └──────────────────────────────────────────────────┘
```

**How it works:**

1. Cloudflare receives requests for your app's hostname at their edge
2. Cloudflare forwards them through an encrypted tunnel to the `cloudflared` container
3. `cloudflared` routes by hostname to Dokku's nginx (port 80)
4. Nginx proxies to the correct app container based on the domain
5. The app responds back through the same path

**Key properties:**
- Server's IP address is never exposed to the internet
- No ports (80, 443) opened on the router/firewall
- TLS is terminated at Cloudflare's edge (free SSL)
- Adding a new app = `ferry deploy` + `git push`

## Ferry CLI

The `ferry` script is the primary interface for managing apps. Run it with no arguments for an interactive arrow-key selector menu, or pass a command directly.

```
ferry                    # Interactive menu
ferry login              # Set up Cloudflare API access
ferry deploy [<name>]    # Deploy a new app (interactive prompts)
ferry remove [<name>]    # Remove an app + DNS + ingress
ferry status             # Full system dashboard
ferry list               # Quick app list
ferry reload             # Validate config + restart cloudflared
ferry rebuild <name>     # Rebuild a Dokku app
ferry logs <name>        # Tail app logs
ferry help | -h | --help # Show help
```

**Global flags:**

| Flag | Effect |
|---|---|
| `-y` / `--yes` | Skip all confirmations (non-interactive mode) |
| `-h` / `--help` | Show help |

**Command-specific flags:**

| Command | Flag | Effect |
|---|---|---|
| `deploy` | `-r` / `--repo` | GitHub repo to clone (`owner/repo` or URL) |
| `deploy` | `-H` / `--hostname` | Set hostname (e.g. `app.example.com`) |
| `deploy` | `-p` / `--port` | Set app port (default: auto-detect, fallback: 5000) |
| `deploy` | `-b` / `--branch` | Git branch to push (default: auto-detect) |
| `deploy` | `-d` / `--dir` | Local app directory (skip clone) |
| `deploy` | `--no-push` | Infrastructure only, skip git push |
| `login` | `-t` / `--token` | Pass API token directly (no interactive paste) |

### Non-interactive / Scripting

All commands support `-y` for unattended use. The 256-color palette degrades gracefully to 16-color or no-color when piped, and `confirm()` prompts return false when stdin is not a TTY, so the script is safe to use in pipelines.

```bash
# Full auto-deploy from GitHub (clone + detect port + infra + push + verify)
ferry deploy myapp -r owner/repo -H app.myproject.dev -y

# Deploy with explicit options
ferry deploy myapp -H app.myproject.dev -p 3000 -y

# Deploy from local directory
ferry deploy myapp -d ./my-app -y

# Remove without confirmation
ferry remove myapp -y

# Set up API token non-interactively
ferry login -t "your-api-token" -y

# Pipe-safe: no ANSI codes in output
ferry status > status.txt
```

**Auth handling:** On startup, the CLI checks for a valid Cloudflare API token and shows a red warning banner if missing or expired, listing what you cannot do without it. Commands that need DNS access (`deploy` to domains without a zone cert, `remove` with DNS cleanup) hard-gate and offer inline login via `cf_require_auth`. Run `ferry login` to set up a token interactively -- it guides you through token creation, validates permissions, reports accessible zones, and auto-discovers your account ID.

**DNS management:** With an API token, DNS records are created/deleted via the Cloudflare API for any domain in your account. Zone IDs are auto-resolved from hostnames by walking up domain labels (no manual `CF_ZONE_ID` needed). Without an API token, DNS creation falls back to zone-scoped certs via `cloudflared tunnel route dns`, limited to domains with a matching cert file.

## Quick Reference

| Action | Command |
|---|---|
| Start everything | `cd ~/ferry && docker compose up -d` |
| Stop everything | `cd ~/ferry && docker compose down` |
| Deploy from GitHub | `ferry deploy myapp -r owner/repo -H app.example.com -y` |
| Deploy (interactive) | `ferry deploy` |
| Remove an app | `ferry remove` |
| System dashboard | `ferry status` |
| Set up Cloudflare API | `ferry login` |
| Push code to app | `git push dokku main:master` |

## Deployed Apps

| App | Domain | Port | Tech |
|---|---|---|---|
| test-app | `app.example.com` | 5000 | Node.js / Express |
| staging | `staging.myproject.dev` | 3000 | Next.js |

## Documentation

Detailed guides are in the [`docs/`](docs/) folder:

- **[Deploying Apps](docs/deploying-apps.md)** — How to deploy new apps and manage existing ones
- **[Architecture](docs/architecture.md)** — How the networking, DNS, and containers fit together
- **[Troubleshooting](docs/troubleshooting.md)** — Common problems and how to fix them
- **[Initial Setup](docs/initial-setup.md)** — How this server was set up from scratch (historical reference)
- **[Cloudflare LLM Docs](docs/cloudflare-llms-index.md)** — Links to Cloudflare developer docs for LLMs

## Environment Variables (.env)

| Variable | Required | Description |
|---|---|---|
| `TUNNEL_ID` | Yes | Cloudflare tunnel ID |
| `DOKKU_HOSTNAME` | Yes | Default domain for app hostnames |
| `CF_API_TOKEN` | Auto | Cloudflare API token (set via `ferry login`) |
| `CF_ACCOUNT_ID` | Auto | Cloudflare account ID (auto-discovered from token) |

## Project Structure

```
personal-webserver/
├── ferry                           # CLI for deploy/remove/status/login/etc.
├── CHANGELOG.md                    # Version history
├── docker-compose.yml              # Defines cloudflared + dokku services
├── .env                            # TUNNEL_ID, DOKKU_HOSTNAME, CF_API_TOKEN, etc. (gitignored)
├── .env.example                    # Template for .env
├── .gitignore                      # Keeps secrets out of git
├── README.md
├── docs/
│   ├── deploying-apps.md           # How to deploy and manage apps
│   ├── architecture.md             # Networking, DNS, container topology
│   ├── troubleshooting.md          # Common issues and fixes
│   ├── initial-setup.md            # One-time setup reference
│   ├── deploy-guide-github-to-live.md  # GitHub-to-live auto-deploy guide
│   └── cloudflare-llms-index.md    # Cloudflare LLM doc links
├── tunnels/
│   └── providers/
│       └── cloudflare/
│           ├── config.yml          # Tunnel ingress rules (gitignored, auto-generated)
│           ├── config.yml.example  # Template for config.yml
│           └── *.cert              # Zone-scoped certs for DNS fallback (gitignored)
└── apps/
    └── test-app/                   # Example app (Node/Express)
        ├── Dockerfile
        ├── package.json
        ├── package-lock.json
        ├── app.js
        └── .dockerignore
```

## Software Versions (as of initial setup)

| Component | Version |
|---|---|
| Host OS | Linux |
| Docker | 29.2.1 |
| Docker Compose | v5.1.0 |
| Dokku | 0.37.6 |
| cloudflared | 2026.2.0 |
| NextDNS | Running on host |
