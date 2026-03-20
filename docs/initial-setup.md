# Initial Setup Reference

This documents how the server was set up from scratch on 2026-03-02. You shouldn't need to repeat these steps unless starting over on a new host.

## Prerequisites

The following were already installed on the host before this setup:

- **Linux** (any architecture supported by Docker)
- **Docker 29.3.0** + **Docker Compose v5.1.0**
- **cloudflared 2026.2.0** (installed on the host, used only for tunnel creation)
- **NextDNS** running as system DNS resolver

## Step 1: Create Cloudflare Tunnel

This was done on the host using the `cloudflared` CLI:

```bash
# Login to Cloudflare (opens browser)
cloudflared tunnel login

# Create the tunnel
cloudflared tunnel create <tunnel-name>
# Output: tunnel ID <tunnel-id>
# Created: ~/.cloudflared/<tunnel-id>.json

# Route DNS to the tunnel
cloudflared tunnel route dns <tunnel-name> app.example.com
# Creates CNAME: app.example.com → <tunnel-id>.cfargotunnel.com
```

The `cert.pem` from `cloudflared tunnel login` is zone-scoped (it contains a `zoneID` field locked to one zone). To use it as a DNS creation fallback, copy it to the zone cert directory and rename it to match the zone:

```bash
cp ~/.cloudflared/cert.pem ~/ferry/tunnels/providers/cloudflare/example.com.cert
```

For DNS operations on other domains (or to avoid managing zone certs entirely), use a Cloudflare API token via `ferry login` instead. This is the recommended approach.

## Step 2: Generate SSH Key for Dokku

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "<user>@<tunnel-name>"
```

This key is used for `git push dokku` over SSH.

## Step 3: Configure NextDNS for Docker

Docker containers can't reach `localhost:53` (the host's loopback). NextDNS needs to also listen on the Docker bridge gateway (`172.17.0.1`).

**Critical boot ordering issue:** NextDNS starts before Docker, so the `docker0` interface (`172.17.0.1`) doesn't exist yet. If NextDNS tries to bind to an address that doesn't exist, it crashes **all** listeners (including `localhost:53`) due to a shared `cancel()` context in its source code. This causes total DNS failure on the host.

**Fix:** Add a systemd drop-in to make NextDNS start after Docker:

```bash
# 1. Create drop-in (survives NextDNS package upgrades)
sudo mkdir -p /etc/systemd/system/nextdns.service.d
sudo tee /etc/systemd/system/nextdns.service.d/after-docker.conf > /dev/null << 'EOF'
[Unit]
After=docker.service
EOF
sudo systemctl daemon-reload

# 2. Add the Docker bridge listener
sudo nextdns config set -listen localhost:53 -listen 172.17.0.1:53
sudo systemctl restart nextdns
```

Verify:
```bash
ss -lntu | grep ':53 '
# Should show both 127.0.0.1:53 AND 172.17.0.1:53
```

**Why this is safe:**
- Docker doesn't need DNS to start. It just creates the daemon and bridge interface
- Host DNS is briefly unavailable during early boot (until NextDNS starts), which is already the case today
- All container DNS goes through NextDNS, preserving ad-blocking and filtering

## Step 4: Create Project Files

```bash
mkdir -p ~/ferry/{tunnels/providers/cloudflare,apps/test-app,docs}
```

The following files were created:

- `docker-compose.yml`: cloudflared + dokku services
- `tunnels/providers/cloudflare/config.yml`: tunnel ingress rules (gitignored, auto-generated from TUNNEL_ID if missing)
- `tunnels/providers/cloudflare/config.yml.example`: template for config.yml
- `~/.cloudflared/<tunnel-id>.json`: tunnel credentials (mounted into container via docker-compose, never copied into project)
- `.env`: TUNNEL_ID, DOKKU_HOSTNAME, CF_API_TOKEN, CF_ACCOUNT_ID
- `.env.example`: template for .env
- `.gitignore`: keeps secrets out of git
- `apps/test-app/`: Node/Express test application

See the main README for the full file structure.

### Key detail: Credentials file permissions

The cloudflared container runs as a non-root user and needs to read the credentials file. It is mounted directly from the host, so there is no need to copy it into the project:

```bash
chmod 644 ~/.cloudflared/<tunnel-id>.json
```

## Step 5: Create Dokku Host Wrapper

```bash
sudo tee /usr/local/bin/dokku > /dev/null << 'EOF'
#!/bin/bash
exec docker compose -f ~/ferry/docker-compose.yml exec -T dokku dokku "$@"
EOF
sudo chmod +x /usr/local/bin/dokku
```

## Step 6: Start the Stack

```bash
cd ~/ferry
docker compose up -d
```

First run pulls `cloudflare/cloudflared:latest` (~55 MB) and `dokku/dokku:0.37.7` (~357 MB). Dokku takes ~15 seconds to initialize on first boot (generates SSH keys, DH parameters, sets hostname).

## Step 7: Register SSH Key in Dokku

```bash
docker compose exec -T dokku dokku ssh-keys:add admin < ~/.ssh/id_ed25519.pub
```

## Step 8: Configure Dokku Networking

Dokku deploys app containers on the default `bridge` network, but Dokku's nginx runs on the `webserver` network. They can't reach each other by default.

The fix is to tell Dokku to attach all app containers to the `webserver` network after deploy:

```bash
dokku network:set --global attach-post-deploy webserver
```

This is a **global** setting that applies to all current and future apps.

## Step 9: Deploy the Test App

```bash
# Create app and set domain
dokku apps:create test-app
dokku domains:set test-app app.example.com

# Fix port mapping (nginx :80 → app :5000)
dokku ports:set test-app http:80:5000

# Push to deploy
cd ~/ferry/apps/test-app
git init && git add . && git commit -m "Initial test-app"
ssh-keyscan -p 3022 localhost >> ~/.ssh/known_hosts
git remote add dokku dokku@localhost:test-app
GIT_SSH_COMMAND="ssh -i ~/.ssh/id_ed25519 -p 3022" git push dokku master
```

## Step 10: Verify

```bash
# Containers running
docker compose ps

# Tunnel connected (should show 4 registered connections)
docker compose logs cloudflared | grep "Registered"

# App deployed
dokku apps:list

# Public URL works
curl https://app.example.com
# {"app":"test-app","status":"running","hostname":"...","timestamp":"..."}
```

## Gotchas Encountered During Setup

These are problems we hit and solved. Documented here so we don't repeat them.

### 1. DNS fails inside Docker containers

**Problem:** `npm install` during Docker build fails with `EAI_AGAIN` / `getaddrinfo` errors. After reboot, cloudflared can't resolve Cloudflare edge IPs.

**Root cause:** Host DNS is `127.0.0.1` (NextDNS via DNS-over-HTTPS). Containers can't reach `127.0.0.1` on the host. All external DNS servers (8.8.8.8, 1.1.1.1, 9.9.9.9) are blocked by the gateway firewall on port 53.

**Solution:** Configure NextDNS to also listen on `172.17.0.1:53` (Docker bridge gateway), and add `dns: [172.17.0.1]` to compose services. **But** NextDNS must start **after** Docker. Otherwise `172.17.0.1` doesn't exist yet, the bind fails, and NextDNS's shared `cancel()` context tears down all listeners including `localhost:53`, causing total DNS failure. See Step 3 for the systemd drop-in fix.

### 2. Cloudflared can't read credentials.json

**Problem:** `permission denied` reading `/etc/cloudflared/credentials.json`.

**Root cause:** File was `chmod 600` (owner-only), but the container runs as a different user.

**Solution:** `chmod 644 ~/.cloudflared/<tunnel-id>.json`.

### 3. npm ci fails without package-lock.json

**Problem:** Dockerfile uses `npm ci --production` but there's no lockfile.

**Root cause:** `npm ci` requires `package-lock.json` to exist.

**Solution:** Generate `package-lock.json` with `npm install` first (ran in a Docker container to avoid needing Node on the host). Changed Dockerfile to `npm ci --omit=dev` (the `--production` flag is deprecated).

### 4. App deploys but site times out

**Problem:** `curl https://app.example.com` hangs after TLS handshake.

**Root cause:** Dokku's nginx (on `webserver` network) tries to proxy to the app container (on `bridge` network). Different networks can't communicate.

**Solution:** `dokku network:set --global attach-post-deploy webserver` attaches app containers to the `webserver` network. Required `dokku ps:rebuild test-app` to take effect.

### 5. Wrong port mapping after first deploy

**Problem:** Dokku reports the app at `http://app.example.com:5000` instead of port 80.

**Root cause:** Dokku auto-detected the port mapping as `http:5000:5000` from the `EXPOSE 5000` in the Dockerfile.

**Solution:** `dokku ports:set test-app http:80:5000` to map nginx's port 80 to the app's port 5000.

### 6. Can't use default bridge network in Docker Compose

**Problem:** Adding `bridge` as an external network in compose causes "network-scoped aliases are only supported for user-defined networks".

**Root cause:** Docker doesn't allow service aliases on the default `bridge` network.

**Solution:** Instead of connecting Dokku to bridge, bring app containers to Dokku's network via `dokku network:set --global attach-post-deploy webserver`.
