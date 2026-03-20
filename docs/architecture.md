# Architecture

Deep dive into how all the pieces fit together: containers, networks, DNS, and traffic flow.

## Container Topology

```
┌─────────────────────────────────────────────────────────────────────┐
│  Docker Engine                                                      │
│                                                                     │
│  ┌─────────────────────────────────────────────┐                    │
│  │  "webserver" network (172.18.0.0/16)        │                    │
│  │                                              │                    │
│  │  ┌──────────────┐    ┌──────────────┐        │                    │
│  │  │  cloudflared  │───►│    dokku      │       │                    │
│  │  │  (tunnel)     │    │  (nginx+ssh)  │       │                    │
│  │  │  172.18.0.3   │    │  172.18.0.2   │       │                    │
│  │  └──────────────┘    └──────┬───────┘        │                    │
│  │                             │ proxy           │                    │
│  │                       ┌─────▼──────┐          │                    │
│  │                       │  test-app   │         │                    │
│  │                       │  :5000      │         │                    │
│  │                       └────────────┘          │                    │
│  └─────────────────────────────────────────────┘                    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Containers

| Container | Image | Network(s) | Purpose |
|---|---|---|---|
| `cloudflared` | `cloudflare/cloudflared:latest` | webserver | Runs the Cloudflare Tunnel, receives traffic from the internet |
| `dokku` | `dokku/dokku:0.37.7` | webserver, bridge | Runs nginx (port 80) + SSH (port 22), manages app lifecycle |
| `test-app.web.1` | `dokku/test-app:latest` | bridge, webserver | The actual app container, managed by Dokku |

### Why Dokku is on Both Networks

Dokku needs to be on the `webserver` network so `cloudflared` can reach it. But Dokku also creates app containers using the Docker socket, and those containers initially land on the default `bridge` network. By setting `dokku network:set --global attach-post-deploy webserver`, Dokku attaches app containers to the `webserver` network after deploy, allowing nginx to reach them by container IP.

Dokku automatically connects itself to the `bridge` network as well because it manages containers there.

## Docker Compose Services

Defined in `docker-compose.yml`:

```
cloudflared
  ├── depends_on: dokku
  ├── volumes: ./cloudflared → /etc/cloudflared (read-only)
  ├── dns: 172.17.0.1 (NextDNS on Docker bridge gateway)
  ├── mem_limit: 256m
  ├── network: webserver
  └── restart: unless-stopped

dokku
  ├── ports: 3022 → 22 (SSH for git push)
  ├── volumes:
  │     dokku-data → /mnt/dokku (persistent state)
  │     /var/run/docker.sock (so Dokku can manage containers)
  ├── dns: 172.17.0.1
  ├── mem_limit: 256m
  ├── network: webserver
  ├── env: DOKKU_HOSTNAME, DOKKU_HOST_ROOT, DOKKU_LIB_HOST_ROOT
  └── restart: unless-stopped
```

### Named Volume: `dokku-data`

All Dokku state is persisted in the `dokku-data` Docker volume, mounted at `/mnt/dokku` inside the container. This includes:

- App git repos
- SSH keys
- Configuration (domains, ports, network settings, env vars)
- Nginx configs

This means `docker compose down && docker compose up -d` preserves everything. You can even recreate the Dokku container and all apps/settings survive.

**To inspect the volume:**

```bash
docker volume inspect dokku-data
```

**To back up:**

```bash
docker run --rm -v dokku-data:/data -v $(pwd):/backup alpine tar czf /backup/dokku-backup.tar.gz -C /data .
```

## DNS Resolution

### External DNS (internet hostnames)

The host runs **NextDNS** as the system DNS resolver. NextDNS uses DNS-over-HTTPS (port 443) to reach its upstream servers, which is important because the gateway firewall blocks all external DNS on port 53 (8.8.8.8, 1.1.1.1, 9.9.9.9 are all unreachable).

```
Host:        localhost:53       (for host processes)
Docker:      172.17.0.1:53     (for containers, via Docker bridge gateway)
Upstream:    DNS-over-HTTPS     (bypasses port 53 firewall block)
```

Both `cloudflared` and `dokku` services have `dns: [172.17.0.1]` in docker-compose.yml so they can resolve external hostnames through NextDNS.

**Why this is needed:** The host's `/etc/resolv.conf` points to `127.0.0.1` (host loopback). Containers can't reach `127.0.0.1` on the host — they need the Docker bridge gateway IP (`172.17.0.1`) instead.

**Boot ordering:** NextDNS must start **after** Docker, or the `docker0` interface (`172.17.0.1`) won't exist yet and the bind will fail — crashing all DNS. A systemd drop-in ensures correct ordering:

```
/etc/systemd/system/nextdns.service.d/after-docker.conf:
  [Unit]
  After=docker.service
```

NextDNS is configured to listen on both addresses:

```bash
sudo nextdns config set -listen localhost:53 -listen 172.17.0.1:53
```

### Internal DNS (container-to-container)

Docker's embedded DNS (`127.0.0.11`) handles resolution of container names within user-defined networks. This is how:

- `cloudflared` resolves `dokku` to `172.18.0.2` (used in ingress rules: `http://dokku:80`)
- `dokku`'s nginx resolves app containers by IP (Dokku writes the container IP directly into nginx upstream config)

## Traffic Flow (Request Lifecycle)

```
1. User visits https://app.example.com

2. DNS resolves to Cloudflare edge (104.21.3.34 / 172.67.130.41)
   - CNAME: app.example.com → <tunnel-id>.cfargotunnel.com

3. Cloudflare terminates TLS (free SSL cert for *.example.com)

4. Cloudflare forwards the request through the QUIC tunnel to the
   cloudflared container on the host

5. cloudflared matches the hostname against ingress rules in config.yml:
   - app.example.com → http://dokku:80

6. Request hits Dokku's nginx on port 80

7. Nginx matches server_name "app.example.com" and proxies
   to upstream test-app-5000 (container IP:5000)

8. Express app handles the request and responds

9. Response flows back: app → nginx → cloudflared → Cloudflare → user
```

## Port Mappings

| Host Port | Container | Container Port | Purpose |
|---|---|---|---|
| 3022 | dokku | 22 | SSH for `git push dokku` |
| (none) | dokku | 80 | Nginx — only reachable from webserver network |
| (none) | test-app | 5000 | App — only reachable from webserver network |

No ports 80 or 443 are exposed on the host. All HTTP traffic goes through the Cloudflare Tunnel.

## Cloudflare Tunnel

- **Tunnel name:** `<tunnel-name>`
- **Tunnel ID:** `<tunnel-id>`
- **Protocol:** QUIC
- **Connections:** 4 concurrent (to different Cloudflare edge locations)

The tunnel is authenticated via a credentials file mounted from `~/.cloudflared/<tunnel-id>.json` into the container. This file is never copied into the project directory.

### Ingress Rules

Defined in `tunnels/providers/cloudflare/config.yml`. Rules are evaluated top-to-bottom; first match wins. The last rule must always be a catch-all:

```yaml
ingress:
  - hostname: app.example.com
    service: http://dokku:80
  # Add new hostnames here, above the catch-all
  - service: http_status:404
```

All rules point to `http://dokku:80` because Dokku's nginx handles per-app routing based on the `Host` header.

## Cloudflare API Layer (ferry)

The `ferry` script includes a full Cloudflare API integration layer:

- **Helpers:** `cf_api` (raw HTTP), `cf_api_ok` (success check), `cf_api_error` (error extraction)
- **Token verification:** `cf_token_verify` tries `/user/tokens/verify` first, then `/accounts/{id}/tokens/verify`, with fallback to zone listing
- **Account discovery:** Auto-discovers `CF_ACCOUNT_ID` from `/accounts` or from zone response, caches in `.env`
- **Zone resolution:** `cf_resolve_zone_id` walks up domain labels (e.g., `app.example.com` -> `example.com`) to find the matching zone, with per-session caching
- **DNS operations:** `cf_dns_create_cname` (proxied CNAME to tunnel), `cf_dns_delete_record`, `cf_dns_list_records`
- **Auth gating:** `cf_auth_check` runs on startup (red banner if not authed), `cf_require_auth` hard-gates with inline login offer

The API token (`CF_API_TOKEN`) replaces zone-scoped certs for DNS operations and works across all accessible zones. Zone certs are retained as a DNS creation fallback for domains with a matching cert file.

## Host Wrapper: `/usr/local/bin/dokku`

A bash script that forwards any `dokku` command into the running container:

```bash
#!/bin/bash
exec docker compose -f ~/ferry/docker-compose.yml exec -T dokku dokku "$@"
```

This means you can run `dokku apps:list`, `dokku logs test-app`, etc. from anywhere on the host without prefixing `docker compose exec`.

## Security Model

- **No inbound ports:** The only host port exposed is `3022` (SSH for Dokku git push), accessible only from LAN
- **Cloudflare handles TLS:** Free SSL certificates, DDoS protection, WAF
- **Hidden origin IP:** The server's public IP is never revealed; all traffic goes through Cloudflare
- **Secrets gitignored:** `.env`, zone certs, and `config.yml` are all in `.gitignore`
- **Docker socket access:** The Dokku container has access to `/var/run/docker.sock` — this is required for it to manage app containers but means the Dokku container has effective root access to the host's Docker engine
