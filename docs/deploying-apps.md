# Deploying Apps

This guide covers deploying new apps, managing existing ones, and everything related to app lifecycle on Dokku.

## Prerequisites

If you plan to deploy to domains without a zone cert, you need a Cloudflare API token. Run login first:

```bash
ferry login
# optional: ferry login --tunnel-name my-host-tunnel
```

This saves `CF_API_TOKEN` and `CF_ACCOUNT_ID` to `.env`, and also ensures the host tunnel (`TUNNEL_ID` + `TUNNEL_TOKEN`) if those are missing. Without an API token, DNS creation falls back to zone-scoped certs, limited to domains with a matching cert file. See [tunnel-id.md](tunnel-id.md) for the shared-tunnel model.

## Non-interactive Deployment

For scripting or CI, use the `-y` flag with explicit options to skip all prompts:

```bash
# Deploy with hostname and port specified (no prompts)
ferry deploy myapp -H app.myproject.dev -p 3000 -y

# Deploy with defaults (hostname: myapp.$DOKKU_HOSTNAME, port: 5000)
ferry deploy myapp -y

# Remove without type-to-confirm
ferry remove myapp -y
```

Available flags for `deploy`:

| Flag | Description | Default |
|---|---|---|
| `-r` / `--repo` | GitHub repo to clone (`owner/repo` or URL) | (none) |
| `-H` / `--hostname` | App hostname | `<name>.$DOKKU_HOSTNAME` |
| `-p` / `--port` | App listen port | auto-detect, fallback: 5000 |
| `-b` / `--branch` | Git branch to push | auto-detect |
| `-d` / `--dir` | Local app directory (skip clone) | (none) |
| `--no-push` | Infrastructure only, skip git push | (off) |
| `-y` / `--yes` | Skip all confirmations | (interactive) |

When `-y` is used without a name, the script exits with an error immediately (no empty-name prompt). Colors are auto-disabled when output is piped, so redirected output is clean.

## Deploy a New App (Step by Step)

The recommended way is `ferry deploy`, which handles all 5 steps automatically. The manual steps are documented below for reference.

### 1. Create the Dokku app

```bash
dokku apps:create myapp
dokku domains:set myapp myapp.example.com
dokku ports:set myapp http:80:5000
```

The hostname can be on any domain in your Cloudflare account (e.g. `myapp.example.com`, `myapp.otherdomain.com`, or even a root domain like `example.com`).

### 2. Create DNS CNAME

The deploy script creates the CNAME automatically via `cf_dns_create_cname`. It prefers the Cloudflare API (works for all zones in the account), and falls back to zone-scoped certs via `cloudflared tunnel route dns` for domains with a matching cert file. The CNAME points to `<tunnel-id>.cfargotunnel.com`.

If deploying to a domain without a zone cert and without an API token, the script hard-gates and offers inline login via `cf_require_auth`. If DNS creation fails, the script asks whether to continue (ingress still works, DNS can be added later).

### 3. Add the ingress rule

The script adds a rule to `tunnels/providers/cloudflare/config.yml` **above** the catch-all `http_status:404`:

```yaml
ingress:
  - hostname: myapp.example.com
    service: http://dokku:80
  # ... other apps ...
  - service: http_status:404       # <-- catch-all must always be last
```

### 4. Restart cloudflared

```bash
docker compose restart cloudflared
```

### 5. Verify

The script checks that the Dokku app exists, the ingress rule is present, DNS resolves, and config validates.

```bash
curl https://myapp.example.com
```

### Push your app code

After deploy, push your app to Dokku:

```bash
cd /path/to/myapp
git init                                          # if not already a git repo
git add . && git commit -m "Initial commit"
git remote add dokku ssh://dokku@localhost:3022/myapp
git push dokku main:master
```

Dokku always deploys from the `master` branch. If your local branch is `main`, use `main:master`.


## Promoting production domains (tunnel cutover)

Use this when moving a live site from a retired VPS (e.g. DigitalOcean) to Ferry on a new host. Example: `multifiesta.com.uy` + `www.multifiesta.com.uy` → Dokku app `mf-www2` on Proxmox.

### 1. Add domains to the Dokku app

```bash
dokku domains:add mf-www2 multifiesta.com.uy
dokku domains:add mf-www2 www.multifiesta.com.uy
dokku nginx:build-config mf-www2 --parallel
```

Keep staging hostnames (e.g. `www2.example.com`) until you verify production.

### 2. Update tunnel ingress

Ferry manages ingress via the Cloudflare Tunnel config API. Add each hostname with `ferry deploy` (infrastructure only):

```bash
ferry deploy mf-www2 -H multifiesta.com.uy --no-push -y
ferry deploy mf-www2 -H www.multifiesta.com.uy --no-push -y
```

Or add rules manually in the Cloudflare Zero Trust dashboard for the host tunnel. Every app rule points to `http://dokku:80`; Dokku nginx routes by `Host` header.

### 3. Switch Cloudflare DNS to the tunnel

**Ferry ≥ 0.12.6** deletes conflicting `A` / `AAAA` records before creating the proxied CNAME to `<tunnel-id>.cfargotunnel.com`.

Verify in Cloudflare DNS:

| Name | Type | Target | Proxy |
| --- | --- | --- | --- |
| `multifiesta.com.uy` | CNAME | `<tunnel-id>.cfargotunnel.com` | Proxied |
| `www.multifiesta.com.uy` | CNAME | `<tunnel-id>.cfargotunnel.com` | Proxied |

No apex `A` record should remain pointing at the old VPS IP.

### 4. Smoke test

```bash
curl -sI https://multifiesta.com.uy | head -5
curl -sI https://www.multifiesta.com.uy | head -5
docker exec dokku curl -sI -H 'Host: multifiesta.com.uy' http://127.0.0.1/ | head -5
```

### 5. No global Dokku VHOST

Multi-app Ferry hosts must **not** set a global default domain. If `dokku domains:report --global` shows a stale hostname after upgrade, run `dokku domains:clear-global` once. Ferry 0.12.6+ clears this during `ferry reload`.


## Updating an Existing App

Just push again:

```bash
cd /path/to/myapp
git add . && git commit -m "description of change"
git push dokku main:master
```

Dokku will rebuild the Docker image and do a zero-downtime deploy.

## Common App Management Commands

```bash
# List all apps
dokku apps:list

# App status and info
dokku ps:report myapp

# View logs (follow mode)
dokku logs myapp -t

# View recent logs
dokku logs myapp -n 100

# Restart an app
dokku ps:restart myapp

# Rebuild an app (re-runs Dockerfile)
dokku ps:rebuild myapp

# Stop an app
dokku ps:stop myapp

# Start a stopped app
dokku ps:start myapp

# Delete an app (irreversible)
dokku apps:destroy myapp
```

## Environment Variables

Set config/env vars that your app can read:

```bash
# Set a variable
dokku config:set myapp DATABASE_URL=postgres://...
dokku config:set myapp NODE_ENV=production

# View all variables
dokku config:show myapp

# Remove a variable
dokku config:unset myapp DATABASE_URL
```

Setting a config var automatically restarts the app.

## Scaling

```bash
# Run 2 instances of the web process
dokku ps:scale myapp web=2

# Check current scale
dokku ps:report myapp
```

## Custom Domains

```bash
# Add another domain to an app
dokku domains:add myapp another-domain.com

# View domains
dokku domains:report myapp

# Remove a domain
dokku domains:remove myapp old-domain.com
```

Remember: each domain also needs a Cloudflare Tunnel DNS route and an ingress rule in `tunnels/providers/cloudflare/config.yml`.

## Dockerfile Tips

- Always include a `.dockerignore` to exclude `node_modules`, `.git`, etc.
- Use `COPY package.json package-lock.json ./` + `RUN npm ci` before `COPY . .` to leverage Docker layer caching
- Expose the port your app listens on with `EXPOSE`
- Ferry generators ship an `app.json` HTTP startup check (`/health`, or `/` for static React). That is the hard zero-downtime gate. Dokku may also warn about a default port-listening probe when Dokku does not share the host PID namespace; ignore that warning when the HTTP check passes.
- Use alpine-based images to keep builds fast

## Buildpacks (Alternative to Dockerfile)

If your app doesn't have a Dockerfile, Dokku can use Heroku buildpacks to auto-detect the language and build. Just push code that has a `package.json` (Node), `requirements.txt` (Python), `Gemfile` (Ruby), etc.

The Dockerfile approach is recommended because it gives you more control and faster builds.

## SSH Key for Git Push

The SSH key used for `git push dokku` is at `~/.ssh/id_ed25519`. It was added to Dokku as the `admin` key:

```bash
# View registered keys
dokku ssh-keys:list

# Add a new key
dokku ssh-keys:add <name> < /path/to/key.pub

# Remove a key
dokku ssh-keys:remove <name>
```

If pushing from another machine on the LAN, use:

```bash
git remote add dokku ssh://dokku@<pi-ip>:3022/myapp
```
