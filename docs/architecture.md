# Architecture

Deep dive into how all the pieces fit together: containers, networks, DNS, and traffic flow.

## Container Topology

```
┌─────────────────────────────────────────────────────────────────────┐
│  Docker Engine                                                      │
│  ┌─────────────────────────────────────────────┐                    │
│  │  "webserver" network (172.18.0.0/16)        │                    │
│  │  ┌──────────────┐    ┌──────────────┐       │                    │
│  │  │  cloudflared │───►│    dokku     │       │                    │
│  │  │  (tunnel)    │    │  (nginx+ssh  │       │                    │
│  │  │  172.18.0.3  │    │  172.18.0.2  │       │                    │
│  │  └──────────────┘    └──────┬───────┘       │                    │
│  │                             │ proxy         │                    │
│  │                       ┌─────▼──────┐        │                    │
│  │                       │  test-app  │        │                    │
│  │                       │  :5000     │        │                    │
│  │                       └────────────┘        │                    │
│  └─────────────────────────────────────────────┘                    │
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
  ├── env: TUNNEL_TOKEN (remotely-managed tunnel auth)
  ├── DNS: inherits host /etc/resolv.conf via Docker embedded resolver
  ├── mem_limit: 256m
  ├── network: webserver
  └── restart: unless-stopped

dokku
  ├── ports: 3022 → 22 (SSH for git push)
  ├── volumes:
  │     dokku-data → /mnt/dokku (persistent state)
  │     /var/run/docker.sock (so Dokku can manage containers)
  ├── DNS: inherits host /etc/resolv.conf via Docker embedded resolver
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

Ferry containers inherit DNS from the host. There is no `dns:` override in `docker-compose.yml`. The chain is:

```
container → 127.0.0.11 (Docker embedded resolver)
          → forwards to host's nameservers from /etc/resolv.conf
          → upstream resolver (router, ISP, systemd-resolved, NextDNS, Pi-hole, etc.)
```

This works for any host DNS setup without configuration. `ferry status` auto-detects the active host resolvers via `resolvectl` (or `/etc/resolv.conf` as fallback) and verifies that an ephemeral container in the `webserver` network can resolve a real Cloudflare hostname — proving the path cloudflared depends on actually works.

**Why no hardcoded resolver?** Earlier Ferry versions pinned `dns: [172.17.0.1]` to point at a NextDNS listener on the Docker bridge gateway. That broke instantly when NextDNS was removed — cloudflared crash-looped because nothing answered on `172.17.0.1:53`. Inheriting the host's real resolver chain avoids that whole class of failure.

**Custom upstream (optional):** If your host resolver is on `127.0.0.1` (a local proxy) and you can't change the host setup, add a `dns:` block to the compose service pointing at any reachable nameserver — see [troubleshooting.md](troubleshooting.md#custom-dns-upstream-optional).

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
| (none) | dokku | 80 | Nginx, only reachable from webserver network |
| (none) | test-app | 5000 | App, only reachable from webserver network |

No ports 80 or 443 are exposed on the host. All HTTP traffic goes through the Cloudflare Tunnel.

## Cloudflare Tunnel

Ferry uses **one shared host tunnel** for every app hostname. See [TUNNEL_ID and the Shared Cloudflare Tunnel](tunnel-id.md) for why `TUNNEL_ID` is host bootstrap (not per-deploy) and how deploy attaches DNS + ingress on top of it.

- **Tunnel name:** set via `ferry login --tunnel-name` (default `ferry`)
- **Tunnel ID:** `TUNNEL_ID` in `.env` (written by `ferry login`)
- **Protocol:** QUIC
- **Connections:** 4 concurrent (to different Cloudflare edge locations)

The connector is remotely managed: compose runs `cloudflared tunnel run` with `TUNNEL_TOKEN` from `.env` (no `~/.cloudflared/<id>.json` mount). `ferry login` creates/selects the tunnel and writes both `TUNNEL_ID` and `TUNNEL_TOKEN`.

### Ingress Rules

Ingress is managed through the Cloudflare Tunnel config API (`/accounts/.../cfd_tunnel/${TUNNEL_ID}/configurations`), not a local credentials-driven config file on the host. Rules are evaluated top-to-bottom; first match wins. The last rule must always be a catch-all (`http_status:404`).

All app rules point to `http://dokku:80` because Dokku's nginx handles per-app routing based on the `Host` header. `ferry deploy` / `yaml_add_ingress` add hostname rules; `ferry remove` / prune remove them.

## Cloudflare API Layer (ferry)

The `ferry` script includes a full Cloudflare API integration layer:

- **Helpers:** `cf_api` (raw HTTP), `cf_api_ok` (success check), `cf_api_error` (error extraction)
- **Token verification:** `cf_token_verify` tries `/user/tokens/verify` first, then `/accounts/{id}/tokens/verify`, with fallback to zone listing
- **Account discovery:** Auto-discovers `CF_ACCOUNT_ID` from `/accounts` or from zone response, caches in `.env`
- **Tunnel bootstrap:** `cf_ensure_tunnel` (via `ferry login`) lists/creates a remotely-managed tunnel and fetches the connector token
- **Zone resolution:** `cf_resolve_zone_id` walks up domain labels (e.g., `app.example.com` -> `example.com`) to find the matching zone, with per-session caching
- **DNS operations:** `cf_dns_create_cname` (proxied CNAME to tunnel), `cf_dns_delete_record`, `cf_dns_list_records`
- **Auth gating:** `cf_auth_check` runs on startup (red banner if not authed), `cf_require_auth` hard-gates with inline login offer

The API token (`CF_API_TOKEN`) needs Zone DNS Edit, Zone Read, and Account → Cloudflare Tunnel → Edit. Zone certs are retained as a DNS creation fallback for domains with a matching cert file.

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
- **Docker socket access:** The Dokku container has access to `/var/run/docker.sock`. This is required for it to manage app containers, but it means the Dokku container has effective root access to the host's Docker engine
