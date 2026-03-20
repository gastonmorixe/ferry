# Troubleshooting

Common problems encountered during setup and operation, with solutions.

## Container Issues

### Check if containers are running

```bash
cd ~/ferry
docker compose ps
```

You should see `cloudflared` and `dokku` both with status `Up`. App containers (like `test-app.web.1`) are managed by Dokku, not Compose, so they won't appear here. Use `docker ps` instead.

### Containers won't start

```bash
docker compose logs cloudflared
docker compose logs dokku
```

### Restart everything

```bash
docker compose down
docker compose up -d
```

After restarting Dokku, wait ~15 seconds for it to fully initialize before running commands.

### Dokku container was recreated and apps don't respond

When the Dokku container is recreated (`docker compose up -d` after a config change), SSH host keys regenerate. Fix:

```bash
# Remove old host keys
ssh-keygen -R "[localhost]:3022"

# Add new ones
ssh-keyscan -p 3022 localhost >> ~/.ssh/known_hosts
```

App data survives container recreation because it's on the `dokku-data` volume.

## DNS Issues

### Containers can't resolve external hostnames

**Symptom:** `npm install` fails inside Docker builds with `EAI_AGAIN`, `getaddrinfo` errors. Or cloudflared shows `server misbehaving` when looking up Cloudflare edge IPs.

**Cause:** The host uses NextDNS on `127.0.0.1:53` (via DNS-over-HTTPS), which isn't reachable from inside containers. All external DNS servers (8.8.8.8, 1.1.1.1, etc.) are blocked by the gateway firewall on port 53. The only option is NextDNS listening on the Docker bridge gateway.

**Fix:** Verify NextDNS is listening on both addresses:

```bash
ss -lntu | grep ':53 '
# Must show BOTH 127.0.0.1:53 AND 172.17.0.1:53
```

If `172.17.0.1:53` is missing:

```bash
sudo nextdns config set -listen localhost:53 -listen 172.17.0.1:53
sudo systemctl restart nextdns
```

Containers in `docker-compose.yml` are configured with `dns: [172.17.0.1]`.

### DNS breaks completely after reboot

**Symptom:** After a host reboot, all DNS stops working. Not just containers, but the host too. `nslookup google.com` fails everywhere.

**Cause:** NextDNS starts before Docker. The `docker0` interface (`172.17.0.1`) doesn't exist yet when NextDNS tries to bind to it. NextDNS has a bug/design issue where if **any** listener fails to bind, it tears down **all** listeners (including the working `localhost:53`) via a shared `cancel()` context.

**Fix:** Ensure the systemd drop-in exists to make NextDNS start after Docker:

```bash
cat /etc/systemd/system/nextdns.service.d/after-docker.conf
# Should contain:
# [Unit]
# After=docker.service

# If missing, create it:
sudo mkdir -p /etc/systemd/system/nextdns.service.d
sudo tee /etc/systemd/system/nextdns.service.d/after-docker.conf > /dev/null << 'EOF'
[Unit]
After=docker.service
EOF
sudo systemctl daemon-reload
```

### Find the Docker bridge gateway IP

```bash
docker network inspect bridge --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}'
# Should output: 172.17.0.1
```

## Networking Issues

### App deploys but site returns 502 or times out

**Symptom:** `curl https://app.example.com` times out or returns 502.

**Cause:** Dokku's nginx can't reach the app container. They're on different Docker networks.

**Fix:** Ensure the global network setting is configured:

```bash
dokku network:report test-app
# Look for "Network computed attach post deploy" (should say "webserver")

# If missing:
dokku network:set --global attach-post-deploy webserver
dokku ps:rebuild test-app
```

### Verify the whole chain works

Test each hop individually:

```bash
# 1. Is the app container running?
docker ps | grep test-app

# 2. Can Dokku's nginx reach the app?
docker compose exec dokku curl -s -H "Host: app.example.com" http://localhost:80

# 3. Is the tunnel connected?
docker compose logs cloudflared | grep "Registered"

# 4. Does the public URL work?
curl -s https://app.example.com
```

### Port mapping is wrong

**Symptom:** Dokku reports `http://app.example.com:5000` instead of just `http://app.example.com`.

**Cause:** Dokku auto-detected the port mapping as `http:5000:5000` (nginx listens on 5000) instead of `http:80:5000`.

**Fix:**

```bash
dokku ports:report test-app
# If it shows http:5000:5000:
dokku ports:set test-app http:80:5000
```

## Cloudflare Tunnel Issues

### Tunnel not connecting

```bash
docker compose logs cloudflared | tail -20
```

Common errors:

| Error | Fix |
|---|---|
| `permission denied` on credentials.json | `chmod 644 ~/.cloudflared/<tunnel-id>.json` |
| `tunnel not found` | Verify tunnel ID in `config.yml` matches the credentials file |
| `server misbehaving` on DNS lookup | DNS inside container is broken. See "DNS Issues" above |
| `failed to sufficiently increase receive buffer` | Warning only, safe to ignore |

### Verify tunnel is connected

```bash
docker compose logs cloudflared | grep "Registered"
```

You should see 4 registered connections (to different Cloudflare edge locations). Example:

```
INF Registered tunnel connection connIndex=0 ... location=eze01 protocol=quic
INF Registered tunnel connection connIndex=1 ... location=gru13 protocol=quic
INF Registered tunnel connection connIndex=2 ... location=eze07 protocol=quic
INF Registered tunnel connection connIndex=3 ... location=gru20 protocol=quic
```

### DNS CNAME creation fails silently

**Symptom:** Deploy reports DNS success but the CNAME record is never created in Cloudflare DNS.

**Cause:** Zone certs (e.g. `example.com.cert` in `tunnels/providers/cloudflare/`) are zone-scoped. Each is tied to a single domain. When using the zone cert fallback, the cert must exist for the correct zone and be readable by the container.

**Fix:** Use an API token instead of zone certs. Run `ferry login` to configure one. The ferry script handles zone certs correctly when falling back: it mounts the cert to `/tmp/cert.pem` inside the container and passes `--origincert /tmp/cert.pem` to cloudflared. The API token approach is recommended because it works for all zones in your account without managing cert files.

### cloudflared restart takes time to reconnect

**Symptom:** After a cloudflared restart, the tunnel isn't immediately available.

**Context:** The `cloudflared_restart` function in ferry already handles this. It polls for `"Registered tunnel connection"` in the container logs (up to 5 attempts x 3 seconds) before declaring success. The tunnel needs all 4 connections registered to be fully operational. If the poll times out, the restart is flagged as having issues but the deploy continues.

### Auth / token issues

- If the API token is missing, expired, or invalid, run `ferry login` to reconfigure it.
- Token verification supports both user tokens (`/user/tokens/verify`) and account-scoped tokens (`/accounts/{id}/tokens/verify`), with fallback to zone listing.
- Zone certs are scoped to one domain each (they contain a `zoneID` field locked to one zone). Use an API token for broader access.
- `CF_ACCOUNT_ID` is auto-discovered from the API (from `/accounts` or from zone response) and cached in `.env`.

### Credentials file issues

The credentials file is mounted directly from the host into the container via `docker-compose.yml`:
- Source: `~/.cloudflared/<tunnel-id>.json`
- Must be readable by the container (permissions `644`)

If the file is missing or unreadable:

```bash
chmod 644 ~/.cloudflared/<tunnel-id>.json
docker compose restart cloudflared
```

## ferry CLI Issues

### Output has ANSI escape codes

**Symptom:** Redirected or piped output contains `\033[0;31m` escape sequences instead of clean text.

**Cause:** The script uses colored output for interactive use.

**Fix:** Colors are auto-disabled when stdout is not a TTY (piped or redirected). If you still see codes, the detection may have failed. Redirect output explicitly:

```bash
ferry status > status.txt
ferry list | less
```

### Script hangs when piped or in automation

**Symptom:** The script blocks waiting for input when used in a pipeline or from a non-interactive shell.

**Cause:** Confirmation prompts (`confirm()`, `confirm_name()`) wait for user input on stdin.

**Fix:** Use the `-y` / `--yes` flag to skip all confirmations. The `confirm()` and `confirm_name()` functions also return false automatically when stdin is not a TTY, so the script will not hang. It may skip steps you wanted, so use `-y` with explicit flags for predictable behavior:

```bash
ferry deploy myapp -H app.example.com -p 3000 -y
```

## ferry Script Issues

### Apps disappear from status listing

**Symptom:** `ferry status` shows only one app (or none) even though multiple apps are deployed.

**Cause:** `docker compose exec -T` still reads from stdin, which consumes the `while read` loop's input (the heredoc or pipe feeding app names). Each `exec` call eats lines meant for the loop.

**Fix:** Redirect stdin to `/dev/null` inside `dokku_cmd` (or any function that calls `docker compose exec`) so it doesn't steal from the outer loop's input.

### Script exits unexpectedly with set -euo pipefail

**Symptom:** The script aborts at an arithmetic expression like `((count++))` with no useful error message.

**Cause:** When `count` is `0`, `((count++))` evaluates to `0` (falsy in bash), which returns exit code 1. Under `set -e`, that kills the script.

**Fix:** Use `((count++)) || true` to suppress the non-zero exit code.

## Git Push Issues

### Permission denied when pushing

```bash
# Verify key is registered in Dokku
dokku ssh-keys:list

# Test SSH connection
ssh -i ~/.ssh/id_ed25519 -p 3022 dokku@localhost
```

### Host key verification failed

Happens after Dokku container is recreated:

```bash
ssh-keygen -R "[localhost]:3022"
ssh-keyscan -p 3022 localhost >> ~/.ssh/known_hosts
```

### Push rejected / build fails

```bash
# Check Dokku logs for build errors
dokku logs test-app

# Common: missing package-lock.json for npm ci
# Fix: run npm install locally to generate it, commit, and push again
```

## App Issues

### View app logs

```bash
# Last 100 lines
dokku logs test-app -n 100

# Follow logs in real time
dokku logs test-app -t
```

### App health check fails

Dokku runs a port listening check. Your app must:

1. Listen on `0.0.0.0` (not `127.0.0.1` or `localhost`)
2. Listen on the port you `EXPOSE` in the Dockerfile
3. Start within the health check timeout (default 60s)

The "unable to enter the container to check that the process is bound to the correct port" warning is cosmetic in containerized Dokku and can be ignored as long as the uptime check passes.

### Rebuild from scratch

```bash
dokku ps:rebuild test-app
```

### Check nginx config for an app

```bash
docker compose exec dokku cat /home/dokku/test-app/nginx.conf
```

## System / Host Issues

### After host reboot

**Boot order:** Docker starts first (creates `docker0` bridge), then NextDNS starts (binds to `localhost:53` + `172.17.0.1:53`), then Docker Compose containers start and use NextDNS for DNS resolution.

Containers with `restart: unless-stopped` auto-start. Dokku app containers also auto-start because Dokku manages their restart policy.

Verify after reboot:

```bash
# 1. Check DNS is working on both addresses
ss -lntu | grep ':53 '

# 2. Check all containers are running
docker ps

# 3. Check tunnel is connected (4 "Registered" lines)
docker logs cloudflared --tail 10

# 4. Check app responds
dokku apps:list
curl https://app.example.com
```

If cloudflared is in a restart loop with DNS errors, see "DNS breaks completely after reboot" above.

### Docker disk usage

```bash
docker system df
```

Clean up unused images/containers:

```bash
docker system prune -f
```

### Check what's using ports

```bash
sudo ss -tlnp | grep -E ':(3022|80|443|53)\s'
```
