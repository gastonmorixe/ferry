<p align="center">
  <img src="docs/assets/ferry-logo.png?v=2" alt="Ferry" height="300" />
</p>

<h1 align="center">Ferry</h1>

<p align="center"><strong>Self-hosted PaaS for deploying web apps with zero open ports.</strong></p>

Ferry combines [Dokku](https://dokku.com) and [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) into a single workflow. One command takes a GitHub repo to a live HTTPS site with automatic DNS, ingress routing, and TLS termination at Cloudflare's edge. Your server's IP is never exposed.

```bash
ferry deploy myapp -r owner/repo -H app.example.com -y
# Done. Live at https://app.example.com
```

---

## Table of Contents

- [Features](#features)
- [How It Works](#how-it-works)
- [Quick Start](#quick-start)
- [CLI Reference](#cli-reference)
- [Examples](#examples)
- [Configuration](#configuration)
- [Documentation](#documentation)
- [Project Structure](#project-structure)
- [Requirements](#requirements)
- [License](#license)

---

## Features

- **Zero open ports.** No 80, no 443, no public IP. All traffic flows through Cloudflare's encrypted tunnel.
- **One-command deploy.** `ferry deploy` handles app creation, DNS, ingress, tunnel restart, git push, and verification.
- **Git push deploys.** Standard `git push dokku main:master` workflow, just like Heroku.
- **Automatic DNS.** CNAME records created via Cloudflare API for any domain in your account.
- **Auto port detection.** Reads `Dockerfile EXPOSE`, framework conventions (Next.js, Nuxt, Remix, Express), or `package.json` scripts.
- **Free TLS.** SSL certificates managed by Cloudflare at the edge.
- **Interactive TUI.** Arrow-key menu, 256-color palette, spinner animations, graceful degradation to plain text.
- **Fully scriptable.** `-y` flag for CI/CD, pipe-safe output, clean exit codes.
- **Docker Compose stack.** Two containers (`cloudflared` + `dokku`), persistent volumes, `restart: unless-stopped`.

---

## How It Works

```
                                ┌──────────────────────────────────────────┐
                                │               Your Server                │
                                │                                          │
Internet ──> Cloudflare Edge ───┼──> cloudflared ──> dokku ──> app         │
             (TLS + CDN)        │    (tunnel)        (nginx)   (container) │
                                │                                          │
                                └──────────────────────────────────────────┘
```

1. Cloudflare receives requests at their edge and terminates TLS
2. Traffic is forwarded through an encrypted QUIC tunnel to the `cloudflared` container
3. `cloudflared` matches the hostname against ingress rules and routes to Dokku's nginx
4. Nginx proxies to the correct app container based on the `Host` header
5. The response flows back through the same path

**Your server never exposes ports 80 or 443.** The only host port is `3022` (SSH for git push), accessible from LAN only.

---

## Quick Start

### 1. Clone Ferry

```bash
git clone https://github.com/gastonmorixe/ferry.git ~/ferry
cd ~/ferry
```

### 2. Configure environment

```bash
cp .env.example .env
# Edit .env: set TUNNEL_ID and DOKKU_HOSTNAME
```

### 3. Start the stack

```bash
docker compose up -d
```

### 4. Set up Cloudflare API access

```bash
ferry login
```

### 5. Deploy your first app

```bash
ferry deploy myapp -r owner/repo -H myapp.example.com
```

See [Initial Setup](docs/initial-setup.md) for the full first-time setup guide including tunnel creation, SSH keys, and DNS configuration.

---

## CLI Reference

Run `ferry` with no arguments for an interactive arrow-key menu, or pass a command directly.

### Commands

```
ferry                    Interactive menu
ferry login              Set up Cloudflare API access
ferry deploy [<name>]    Deploy a new app
ferry remove [<name>]    Remove an app + DNS + ingress
ferry status             Full system dashboard
ferry list               Quick app list
ferry reload             Validate config + restart cloudflared
ferry rebuild <name>     Rebuild a Dokku app
ferry logs <name>        Tail app logs
ferry help               Show help
```

### Flags

**Global:**

| Flag | Effect |
|---|---|
| `-y` / `--yes` | Skip all confirmations (non-interactive mode) |
| `-h` / `--help` | Show help |

**Deploy:**

| Flag | Effect |
|---|---|
| `-r` / `--repo` | GitHub repo to clone (`owner/repo` or URL) |
| `-H` / `--hostname` | Set hostname (default: `<name>.$DOKKU_HOSTNAME`) |
| `-p` / `--port` | Set app port (default: auto-detect, fallback: 5000) |
| `-b` / `--branch` | Git branch to push (default: auto-detect) |
| `-d` / `--dir` | Local app directory (skip clone) |
| `--no-push` | Set up infrastructure only, skip git push |

**Login:**

| Flag | Effect |
|---|---|
| `-t` / `--token` | Pass API token directly (skip interactive prompt) |

---

## Examples

```bash
# Deploy from GitHub (clone, detect port, create DNS, push, verify)
ferry deploy myapp -r owner/repo -H app.example.com -y

# Deploy with explicit port
ferry deploy myapp -H app.example.com -p 3000 -y

# Deploy from a local directory
ferry deploy myapp -d ./my-app -y

# Set up infrastructure only (push code later)
ferry deploy myapp -r owner/repo -H app.example.com --no-push -y

# Interactive deploy (prompts for everything)
ferry deploy

# Remove an app (destroys app, DNS, ingress)
ferry remove myapp -y

# Set up API token non-interactively
ferry login -t "your-api-token" -y

# Pipe-safe: colors auto-disabled when output is not a TTY
ferry status > status.txt
```

### Updating a deployed app

After the initial deploy, updates are just a git push:

```bash
cd apps/myapp
git pull origin main
git push dokku main:master
```

---

## Configuration

### Environment Variables (.env)

| Variable | Required | Description |
|---|---|---|
| `TUNNEL_ID` | Yes | Cloudflare tunnel UUID |
| `DOKKU_HOSTNAME` | Yes | Base domain for default app hostnames |
| `CF_API_TOKEN` | Auto | Cloudflare API token (set via `ferry login`) |
| `CF_ACCOUNT_ID` | Auto | Cloudflare account ID (auto-discovered from token) |

Copy `.env.example` to `.env` to get started.

### DNS Management

With an API token, Ferry creates and deletes DNS records via the Cloudflare API for any domain in your account. Zone IDs are auto-resolved from hostnames, so no manual configuration is needed.

Without an API token, DNS creation falls back to zone-scoped origin certs via `cloudflared tunnel route dns`, limited to domains with a matching cert file in `tunnels/providers/cloudflare/`.

### Scripting and CI/CD

All commands support `-y` for unattended use. The 256-color TUI degrades gracefully to 16-color or plain text when piped. Confirmation prompts auto-decline when stdin is not a TTY, making the script safe in pipelines.

---

## Documentation

Detailed guides in [`docs/`](docs/):

| Guide | Description |
|---|---|
| [Deploying Apps](docs/deploying-apps.md) | App lifecycle: deploy, update, scale, configure |
| [Deploy Guide: GitHub to Live](docs/deploy-guide-github-to-live.md) | End-to-end walkthrough from repo to live URL |
| [Architecture](docs/architecture.md) | Container topology, networking, DNS, traffic flow |
| [Troubleshooting](docs/troubleshooting.md) | Common problems and solutions |
| [Initial Setup](docs/initial-setup.md) | First-time server setup reference |
| [Cloudflare LLM Docs](docs/cloudflare-llms-index.md) | Cloudflare developer doc links |

---

## Project Structure

```
ferry/
├── ferry                           # CLI script (bash)
├── docker-compose.yml              # cloudflared + dokku services
├── .env                            # Secrets and config (gitignored)
├── .env.example                    # Template for .env
├── .gitignore
├── README.md
├── CHANGELOG.md
├── docs/
│   ├── deploying-apps.md
│   ├── deploy-guide-github-to-live.md
│   ├── architecture.md
│   ├── troubleshooting.md
│   ├── initial-setup.md
│   └── cloudflare-llms-index.md
├── tunnels/
│   └── providers/
│       └── cloudflare/
│           ├── config.yml          # Tunnel ingress rules (gitignored)
│           ├── config.yml.example
│           └── *.cert              # Zone-scoped origin certs (gitignored)
└── apps/                           # App source directories (gitignored)
```

---

## Requirements

| Component | Notes |
|---|---|
| Linux host | Any architecture supported by Docker (x86_64, arm64) |
| Docker + Docker Compose | v29+ / v5+ recommended |
| Cloudflare account | Free tier works (tunnel + DNS) |
| `cloudflared` | On host, for initial tunnel creation only |
| `bash`, `curl`, `jq`, `python3` + PyYAML | Used by the `ferry` script |
| `gh` (GitHub CLI) | Optional, for `--repo` clone support |

---

## License

MIT License. Copyright (c) 2025 [Gaston Morixe](https://github.com/gastonmorixe).

See [LICENSE](LICENSE) for details.
