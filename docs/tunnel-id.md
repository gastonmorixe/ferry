# TUNNEL_ID and the Shared Cloudflare Tunnel

Detailed report on what `TUNNEL_ID` is, why Ferry requires it, and how it relates to automatic DNS / ingress / Dokku deploy. Companion to [Initial Setup](initial-setup.md), [Deploying Apps](deploying-apps.md), and [Architecture](architecture.md).

## Short answer

Ferry runs **one Cloudflare Tunnel per host**, not one tunnel per app or domain.

`TUNNEL_ID` is that tunnel’s UUID. It is **host bootstrap config** in `.env`. Once it exists, `ferry deploy` reuses it and automatically:

1. Creates a Dokku app
2. Creates a DNS CNAME → `${TUNNEL_ID}.cfargotunnel.com`
3. Adds a tunnel ingress hostname rule → `http://dokku:80`
4. Restarts the `cloudflared` connector
5. Pushes the app and verifies

Different apps and domains are **ingress hostnames** (and DNS records) on the **same** tunnel — not new tunnels.

## Mental model

Think of `TUNNEL_ID` as the ID of the **pipe** from Cloudflare’s edge to the host’s `cloudflared` container.

```text
app1.example.com  ──CNAME──┐
app2.other.com    ──CNAME──┼──► <TUNNEL_ID>.cfargotunnel.com
blog.example.com  ──CNAME──┘              │
                                          ▼
                               cloudflared (one connector)
                                          │
                         ingress matches hostname
                                          ▼
                                    dokku:80 → app
```

| Layer | What changes per deploy | What stays fixed |
|---|---|---|
| DNS | New proxied CNAME for the app hostname | Target always `${TUNNEL_ID}.cfargotunnel.com` |
| Tunnel ingress | New hostname rule above the catch-all | Same tunnel config identity (`TUNNEL_ID`) |
| Connector | Restart to pick up routing | Same `cloudflared` service / auth |
| Dokku | New app, domain, ports, push | Same Dokku host |

## Why `TUNNEL_ID` is required

`preflight()` hard-fails if `TUNNEL_ID` is empty in `.env`.

Deploy needs the UUID for two concrete operations:

1. **DNS** — `cf_dns_create_cname` points the hostname at `${TUNNEL_ID}.cfargotunnel.com`
2. **Ingress API** — GET/PUT `/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations` to read/update hostname → service rules

Without it, Ferry does not know **which** tunnel to attach apps to. There is no per-deploy tunnel-create path, and there is no `--tunnel-id` deploy flag — the value is host config, not a deploy argument.

## How to set it

### Preferred: `ferry login`

After you copy `.env.example` → `.env` and set `DOKKU_HOSTNAME`, run:

```bash
ferry login
# optional: ferry login --tunnel-name my-host-tunnel
```

Login saves the Cloudflare API token, discovers `CF_ACCOUNT_ID`, then ensures a **remotely-managed** host tunnel (`config_src: cloudflare`) via the Cloudflare API:

1. If `TUNNEL_ID` + `TUNNEL_TOKEN` are already valid → keep them
2. If `TUNNEL_ID` is set but the token is missing → fetch `TUNNEL_TOKEN`
3. Otherwise list tunnels → pick interactively (or create a named tunnel; default name `ferry`)
4. Writes `TUNNEL_ID` + `TUNNEL_TOKEN` to `.env`
5. Restarts `cloudflared` if the compose service is already running

No host `cloudflared` CLI is required for this bootstrap. Credentials live in Ferry’s `.env` (`TUNNEL_TOKEN`), which compose passes to the connector as `tunnel run`.

Your API token must include **Account → Cloudflare Tunnel → Edit** (plus Zone DNS Edit / Zone Read for deploy DNS).

### Manual fallback (Dashboard / CLI)

Only if you are not using `ferry login` for tunnel bootstrap:

- Cloudflare Dashboard → Zero Trust → Networks → Tunnels — copy the tunnel UUID and connector token into `.env` as `TUNNEL_ID` / `TUNNEL_TOKEN`
- Or historically: `cloudflared tunnel create <name>` on a machine with the host CLI, then paste the UUID/token into `.env`

Prefer remotely-managed tunnels so Ferry can update ingress via the API. See [Initial Setup](initial-setup.md) for the full first-time host sequence.

## `TUNNEL_ID` vs `TUNNEL_TOKEN` vs API auth

Do not mix these up:

| Variable | Role | Set how |
|---|---|---|
| `TUNNEL_ID` | Tunnel **identity** for DNS CNAMEs and Cloudflare Tunnel config API | `ferry login` (preferred); manual Dashboard/CLI fallback |
| `TUNNEL_TOKEN` | Auth for the `cloudflared` container (`tunnel run` in `docker-compose.yml`) | `ferry login` writes the connector token for the same tunnel |
| `CF_API_TOKEN` / `CF_ACCOUNT_ID` | Cloudflare API access for DNS + tunnel list/create/config | `ferry login` (account ID auto-discovered) |

`ferry login` configures API access **and** host tunnel identity/token.

## What `ferry deploy` does automatically

Once the stack is up and `.env` has `TUNNEL_ID` (plus API auth or a zone-cert fallback), deploy auto-wires each app:

1. Create Dokku app + domain/ports/network
2. `dns_create_cname` → proxied CNAME to `${TUNNEL_ID}.cfargotunnel.com`
3. `yaml_add_ingress` → hostname rule to `http://dokku:80` (via tunnel config API)
4. Restart `cloudflared`
5. `git push dokku` (unless `--no-push`)
6. Verify

So: **automatic DNS + tunnel ingress + Dokku is the implemented per-app path.** Host tunnel bootstrap is handled by `ferry login` (or a rare manual Dashboard/CLI fallback).

## Common misconceptions

| Claim | Reality |
|---|---|
| Ferry creates a new Cloudflare Tunnel per deploy/domain | **No.** One host tunnel; many hostnames. |
| Because `TUNNEL_ID` is required, deploy cannot auto-create DNS/ingress/Dokku | **Wrong.** Those are automatic after bootstrap. |
| There should be a deploy CLI flag for the tunnel | **No.** Tunnel identity is host `.env` config, not a per-app deploy option. |
| `TUNNEL_ID` and `TUNNEL_TOKEN` are interchangeable | **No.** ID = which tunnel; token = connector auth. |
| `ferry login` only sets the API token | **Wrong.** Login also ensures `TUNNEL_ID` + `TUNNEL_TOKEN`. |
| You must install `cloudflared` on the host to bootstrap | **No.** Login uses the Cloudflare API. The connector runs in Docker. |

## Related docs

- [Initial Setup](initial-setup.md) — preferred `ferry login` path, compose, SSH keys
- [Deploying Apps](deploying-apps.md) — deploy lifecycle and flags
- [Architecture](architecture.md) — containers, traffic flow, ingress evaluation
- [Troubleshooting](troubleshooting.md) — DNS / tunnel connector failures
