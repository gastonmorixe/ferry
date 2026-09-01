# Initial Setup Reference

This documents how the server was set up from scratch on 2026-03-02, updated for the current `ferry login` tunnel bootstrap. You shouldn't need to repeat these steps unless starting over on a new host.

## Prerequisites

The following were already installed on the host before this setup:

- **Linux** (any architecture supported by Docker)
- **Docker 29.3.0** + **Docker Compose v5.1.0**
- A working system DNS resolver (anything goes: router via DHCP, systemd-resolved, NextDNS, Pi-hole, corporate DNS — Ferry inherits whatever the host uses)

Host `cloudflared` CLI is **not** required. Tunnel create/select and connector token fetch happen through the Cloudflare API during `ferry login`. The connector itself runs as the `cloudflared` Docker service.

## Step 1: Project skeleton + Cloudflare login (preferred)

For why Ferry uses **one shared host tunnel** (and what `TUNNEL_ID` is for), see [TUNNEL_ID and the Shared Cloudflare Tunnel](tunnel-id.md).

Preferred path today:

```bash
mkdir -p ~/ferry
cd ~/ferry
# clone or copy the Ferry repo here, then:
cp .env.example .env
# edit .env: optional DOKKU_HOSTNAME for deploy defaults (leave TUNNEL_ID / TUNNEL_TOKEN blank)

ferry login
# optional: ferry login --tunnel-name my-host-tunnel
```

`ferry login`:

1. Saves `CF_API_TOKEN` and discovers `CF_ACCOUNT_ID`
2. Ensures a remotely-managed host tunnel via the Cloudflare API (`config_src: cloudflare`)
3. Writes `TUNNEL_ID` + `TUNNEL_TOKEN` to `.env`
4. Restarts `cloudflared` if compose already has it running

API token permissions:

- Zone → DNS → Edit
- Zone → Zone → Read
- Account → Cloudflare Tunnel → Edit

Compose starts the connector with `tunnel run` and `TUNNEL_TOKEN` from `.env`. There is no mount of `~/.cloudflared/<id>.json`.

### Historical / optional: host `cloudflared` CLI

Early setups used the host CLI to create the tunnel and a credentials JSON file:

```bash
cloudflared tunnel login
cloudflared tunnel create <tunnel-name>
# then pasted TUNNEL_ID into .env and mounted ~/.cloudflared/<id>.json
```

That path is obsolete for new hosts. Prefer `ferry login`. If you already have a Dashboard tunnel, you can still paste UUID + connector token into `.env` manually (see [tunnel-id.md](tunnel-id.md)).

### Zone cert fallback (optional)

The `cert.pem` from a host `cloudflared tunnel login` is zone-scoped (it contains a `zoneID` field locked to one zone). To use it as a DNS creation fallback when you are not using the API for a given zone, copy it to the zone cert directory and rename it to match the zone:

```bash
cp ~/.cloudflared/cert.pem ~/ferry/tunnels/providers/cloudflare/example.com.cert
```

For DNS on any domain in the account, use the API token from `ferry login` instead. That is the recommended approach.

## Step 2: Generate SSH Key for Dokku

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "<user>@<tunnel-name>"
```

This key is used for `git push dokku` over SSH.

## Step 3: Verify DNS works inside containers

Ferry inherits DNS from the host — no compose override needed for most setups. After starting the stack (Step 6), confirm both sides of the path work:

```bash
ferry status
# Look for:
#   Host DNS           <your resolver> ✓
#   Container DNS      ✓ argotunnel.com resolves from webserver net
```

If `Container DNS` shows ✗ while `Host DNS` is fine, the host resolver is unreachable from containers — most commonly because it's bound to `127.0.0.1` (a local DNS proxy like NextDNS CLI, dnsmasq, or systemd-resolved's stub). Containers cannot reach the host's loopback.

**Two options to fix:**

1. **Recommended:** Make the host resolver listen on an interface containers can reach (LAN IP, or the Docker bridge gateway `172.17.0.1`). Then nothing in Ferry needs to change.
2. **Compose override:** Add a `dns:` block to the affected service pointing at any reachable nameserver (your router, a LAN DNS server, or a public resolver if your network allows port 53 out). See [troubleshooting.md](troubleshooting.md#custom-dns-upstream-optional).

## Step 4: Create Project Files

```bash
mkdir -p ~/ferry/{tunnels/providers/cloudflare,apps/test-app,docs}
```

The following files were created / expected:

- `docker-compose.yml`: cloudflared + dokku services (`cloudflared` uses `TUNNEL_TOKEN` via `tunnel run`)
- `tunnels/providers/cloudflare/config.yml`: tunnel ingress rules (gitignored, recovered from Dokku app domains when possible, otherwise generated from TUNNEL_ID)
- `.env`: optional `DOKKU_HOSTNAME` (deploy hostname defaults), plus `TUNNEL_ID` / `TUNNEL_TOKEN` / `CF_API_TOKEN` / `CF_ACCOUNT_ID` from `ferry login`
- `.env.example`: template for .env
- `.gitignore`: keeps secrets out of git
- `apps/test-app/`: Node/Express test application

Ferry no longer keeps a checked-in `config.yml.example`.

If `config.yml` is missing:

- with a running Dokku instance and existing apps, Ferry rebuilds ingress from the current Dokku app domains so routes are not dropped
- with no existing apps but a configured `TUNNEL_ID`, Ferry generates a minimal config with only the catch-all rule
- with Dokku unavailable, Ferry refuses to generate a blank config automatically and asks you to restore the stack first

See the main README for the full file structure.

### Key detail: Tunnel credentials live in `.env`

The connector authenticates with `TUNNEL_TOKEN` from Ferry’s `.env` (compose `environment: TUNNEL_TOKEN`). Keep `.env` gitignored and readable by the user who runs compose. There is no root-owned secret file and no `~/.cloudflared/<id>.json` mount in the current compose file.

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

First run pulls `cloudflare/cloudflared:latest` and `dokku/dokku:latest`. Ferry follows current Dokku by maintenance policy; `latest` is intentionally **not** a reproducible apply pin. Immediately before any target VM `docker compose up`, resolve and record the selected Dokku image as `dokku/dokku:latest@sha256:…` in the approved BOM/rehearsal evidence, then review that resolved digest before applying. `cloudflare/cloudflared:latest` remains separately deferred: resolve and record its digest at the same BOM/apply gate. Dokku takes about 15 seconds to initialize on first boot (generates SSH keys, DH parameters, sets hostname).

You can run `ferry login` before or after `compose up`. If cloudflared is already running when login writes a new token, Ferry restarts it. If not, the token applies on the next `docker compose up -d`.

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

(Or use `ferry deploy` / `ferry new ... --deploy` once login + compose are done.)

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

**Root cause:** The host's resolver is unreachable from inside containers. The classic case: `/etc/resolv.conf` points at `127.0.0.1` (a local DNS proxy like NextDNS CLI, dnsmasq, or systemd-resolved's stub) — Docker's embedded DNS at `127.0.0.11` forwards there, but containers cannot reach the host's loopback. A previous Ferry hardcoded `dns: [172.17.0.1]` to point at a NextDNS listener on the Docker bridge gateway, which crash-looped cloudflared the day NextDNS was removed.

**Solution:** Ferry no longer hardcodes a resolver. Containers inherit `/etc/resolv.conf` from the host. If your host resolver lives on `127.0.0.1` and you can't move it, see [troubleshooting.md → Custom DNS upstream](troubleshooting.md#custom-dns-upstream-optional) for the per-service `dns:` override. `ferry status` reports both `Host DNS` and `Container DNS` rows so this category of failure is visible on every run.

### 2. Cloudflared missing or invalid `TUNNEL_TOKEN`

**Problem:** cloudflared exits or never registers connections after compose up.

**Root cause:** `.env` has no `TUNNEL_TOKEN`, or the token does not match a remotely-managed tunnel.

**Solution:** Run `ferry login` (API token needs Account → Cloudflare Tunnel → Edit). Login writes `TUNNEL_ID` + `TUNNEL_TOKEN` and restarts cloudflared when it is already running. Then `docker compose up -d` / `ferry reload` if needed.

(Historical note: older setups mounted `~/.cloudflared/<tunnel-id>.json` and hit `chmod 600` permission errors inside the container. Current compose uses `TUNNEL_TOKEN` only.)

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
