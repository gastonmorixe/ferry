# Deploy Guide: GitHub Repo to Live

End-to-end guide for deploying a GitHub repository to a live URL using the Ferry server. Based on the real deployment of `my-app` to `staging.myproject.dev`.

## Prerequisites

Before your first deploy, make sure these are done (one-time setup):

| Requirement | How to check | How to fix |
|---|---|---|
| Docker stack running | `docker compose ps` (cloudflared + dokku running) | `cd ~/ferry && docker compose up -d` |
| Cloudflare API token | `ferry status` (no auth warnings) | `ferry login` |
| SSH key registered in Dokku | `dokku ssh-keys:list` | `dokku ssh-keys:add admin < ~/.ssh/id_ed25519.pub` |
| Domain in Cloudflare account | Cloudflare Dashboard > Websites | Add domain to Cloudflare first |
| `gh` CLI authenticated | `gh auth status` | `gh auth login` |

## Step 1: Clone the Repo

Clone your GitHub repo into the `apps/` directory:

```bash
cd ~/ferry

# Find your repo (if you're not sure of the exact name)
gh repo list --limit 50 | grep <keyword>

# Clone it
gh repo clone <owner>/<repo> apps/<repo>
```

**Real example:**
```bash
gh repo clone username/my-app apps/my-app
```

## Step 2: Identify the App's Port

Check what port the app listens on. This depends on the framework:

| Framework | Default port | Where to check |
|---|---|---|
| Next.js | 3000 | `next start` uses `$PORT` or 3000 |
| Express / Node | 5000 or 3000 | Look at `app.listen(PORT)` in code |
| Python / Flask | 5000 | `flask run` default |
| Rails | 3000 | `rails server` default |
| Static site | 5000 | Depends on the server you use |

**How to check:**
```bash
# Check package.json scripts
cat apps/<repo>/package.json | grep -A5 '"scripts"'

# Check for Dockerfile with EXPOSE
cat apps/<repo>/Dockerfile 2>/dev/null | grep EXPOSE

# Check for Procfile
cat apps/<repo>/Procfile 2>/dev/null
```

**Important:** Dokku sets the `$PORT` environment variable at runtime. Most frameworks (Next.js, Express, Rails) respect this automatically. If your app hardcodes a port, update it to use `process.env.PORT` or equivalent.

## Step 3: Check Deployment Method

Dokku supports two deployment methods:

### A) Buildpacks (auto-detect) — no Dockerfile needed

If your repo has **no Dockerfile**, Dokku uses Heroku buildpacks to auto-detect and build:

| File present | Detected as |
|---|---|
| `package.json` | Node.js (npm, pnpm, or yarn auto-detected from lockfile) |
| `requirements.txt` | Python |
| `Gemfile` | Ruby |
| `go.mod` | Go |

This is what happened with our Next.js deploy — Dokku detected `package.json` + `pnpm-lock.yaml`, installed pnpm, ran `pnpm install` and `pnpm run build`, then used `pnpm start` to run.

**Note on ARM64:** On ARM64 hosts, Herokuish doesn't work, so Dokku automatically switches to the Cloud Native Buildpacks (CNB) `pack` builder. This works but the first build is slower (pulls the builder image). On x86_64, both Herokuish and CNB work.

### B) Dockerfile — full control

If your repo has a `Dockerfile`, Dokku uses it directly. Recommended for:
- Apps with native dependencies (e.g. sharp, canvas, bcrypt)
- Custom system packages needed
- Multi-stage builds for smaller images
- Apps that don't fit standard buildpack patterns

**Tips for Dockerfiles:**
- Use multi-arch base images (most official images support both x86_64 and arm64)
- Prefer alpine-based images for faster builds
- Add a `.dockerignore` to exclude `node_modules/`, `.git/`, etc.
- Use `EXPOSE <port>` so Dokku auto-detects the port for health checks

## Step 4: Deploy Infrastructure

This creates the Dokku app, DNS record, ingress rule, and restarts cloudflared — all in one command:

```bash
ferry deploy <app-name> -H <hostname> -p <port>
```

**Real example:**
```bash
ferry deploy staging -H staging.myproject.dev -p 3000
```

**Non-interactive (for scripting):**
```bash
ferry deploy staging -H staging.myproject.dev -p 3000 -y
```

What this does (5 steps):

1. Creates Dokku app + sets domain and port mapping
2. Creates DNS CNAME (`staging.myproject.dev → <tunnel-id>.cfargotunnel.com`)
3. Adds ingress rule to `tunnels/providers/cloudflare/config.yml`
4. Restarts cloudflared to pick up the new rule
5. Verifies everything is in place

**Choose the right app name:** This becomes the Dokku app identifier. Keep it short and descriptive (e.g. `staging`, `myapp`, `blog`). It's separate from the hostname.

## Step 5: Push Code to Dokku

```bash
cd apps/<repo>

# Add Dokku as a git remote
git remote add dokku ssh://dokku@localhost:3022/<app-name>

# Push to deploy (Dokku always deploys from master)
git push dokku main:master
```

**Real example:**
```bash
cd apps/my-app
git remote add dokku ssh://dokku@localhost:3022/staging
git push dokku main:master
```

This triggers the full build pipeline:
1. Dokku receives the push
2. Detects build method (Dockerfile or buildpacks)
3. Installs dependencies
4. Runs the build (e.g. `next build`)
5. Creates a container image
6. Runs health checks (port listening + uptime)
7. Starts the app and reloads nginx
8. Reports the live URL

**Typical build times:**
- Simple Node/Express: ~30 seconds
- Next.js with 669 packages: ~2-3 minutes
- First deploy is slower (pulls builder images)

## Step 6: Verify

```bash
# Check DNS resolves (may need to flush local DNS cache)
dig +short <hostname>

# If using NextDNS locally and DNS doesn't resolve yet:
sudo nextdns restart

# Test the live site
curl -sI https://<hostname> | head -5
```

**Real example:**
```bash
$ dig +short staging.myproject.dev
104.21.7.209
172.67.188.6

$ curl -sI https://staging.myproject.dev | head -5
HTTP/2 200
content-type: text/html; charset=utf-8
server: cloudflare
```

## Step 7: Set Environment Variables (if needed)

If your app needs env vars (database URLs, API keys, etc.):

```bash
dokku config:set <app-name> DATABASE_URL=postgres://... SECRET_KEY=abc123
```

This automatically restarts the app. To set without restart:

```bash
dokku config:set --no-restart <app-name> KEY=value
```

---

## Updating the App

After the initial deploy, updates are just a git push:

```bash
cd apps/<repo>
git pull origin main          # get latest from GitHub
git push dokku main:master    # deploy to Dokku
```

Or push directly from any machine:

```bash
git remote add dokku ssh://dokku@<pi-ip>:3022/<app-name>
git push dokku main:master
```

## Removing an App

```bash
ferry remove <app-name>

# Non-interactive:
ferry remove <app-name> -y
```

This destroys the Dokku app, removes the ingress rule, restarts cloudflared, and deletes the DNS CNAME.

---

## Quick Reference

### Full deploy in 4 commands

```bash
# 1. Clone
gh repo clone <owner>/<repo> apps/<repo>

# 2. Create infrastructure
ferry deploy <app-name> -H <hostname> -p <port> -y

# 3. Add remote and push
cd apps/<repo>
git remote add dokku ssh://dokku@localhost:3022/<app-name>
git push dokku main:master

# 4. Verify
curl https://<hostname>
```

### Common ports

| Stack | Port |
|---|---|
| Next.js | 3000 |
| Express / Fastify | 3000 or 5000 |
| Flask / Django | 5000 or 8000 |
| Rails | 3000 |
| Go (net/http) | 8080 |
| Static (serve/http-server) | 3000 or 5000 |

### Available domains

Any domain in the Cloudflare account can be used. Check with `ferry status` to see accessible zones.

---

## Troubleshooting First Deploy

### Build fails: "no matching builder" or buildpack errors

Some buildpacks may not support your architecture. Fix: add a `Dockerfile` to your repo.

### Health check fails: "port listening check"

Your app must listen on `0.0.0.0` (not `127.0.0.1` or `localhost`). Most frameworks do this by default when `$PORT` is set.

The "unable to enter the container to check that the process is bound" warning is cosmetic on Dokku with Docker's default PID namespace — it still deploys.

### DNS doesn't resolve after deploy

1. **Negative cache:** If you queried the hostname before the CNAME existed, your DNS resolver cached the negative response. Fix: `sudo nextdns restart` (or wait ~30 minutes for TTL expiry).
2. **Propagation delay:** New CNAME records can take 1-5 minutes to propagate globally.
3. **Wrong zone:** The domain must be in your Cloudflare account. Check with `ferry status`.

### Site returns 502 Bad Gateway

The app isn't running or isn't listening on the configured port. Check:

```bash
dokku logs <app-name> -t     # check app logs
dokku ps:report <app-name>   # check container status
dokku ports:report <app-name> # verify port mapping
```

### Build is slow

First deploys are slower because Dokku pulls builder images. Subsequent pushes reuse cached layers. For faster builds:
- Use a `Dockerfile` with multi-stage builds
- Add `.dockerignore` to exclude test files, docs, `.git/`
- Use alpine base images

### pnpm/yarn not detected

Dokku's Node.js buildpack detects the package manager from the lockfile:
- `package-lock.json` → npm
- `pnpm-lock.yaml` → pnpm
- `yarn.lock` → yarn

Make sure the lockfile is committed to git. If using pnpm, also set `packageManager` in `package.json`:
```json
{
  "packageManager": "pnpm@10.28.0"
}
```
