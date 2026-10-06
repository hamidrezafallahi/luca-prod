# Hermes (containerized)

Hermes runs in `docker-compose.automation.yml` as `shop-hermes-prod`, on the
same Docker network as n8n (`shop-network-prod`). It does **not** run as host
root and does **not** get the Docker socket.

## Why automation compose (not tools, not a fourth file)

- **prod** is the shop (nginx, frontend, backend, postgres). Keep the AI agent
  out of that blast radius and deploy cycle.
- **tools** is operator UIs (pgAdmin, Portainer). Wrong job.
- **automation** already owns n8n. Hermes talks to n8n webhooks and the shop
  API. One `./deploy.sh automation` starts both.

Trade-off: restarting automation recreates n8n *and* Hermes. That is acceptable
because they are a pair. A separate compose would isolate restarts but would
duplicate the external network wiring for little gain.

## Talk to it

| Channel | Where |
| --- | --- |
| Web dashboard | `http://SERVER_IP:9119` (basic auth from `.env`) |
| OpenAI-compatible API | `http://SERVER_IP:8642/v1` (Bearer `API_SERVER_KEY`) |
| Telegram | existing bot token in `/opt/shop/.env` |

Credentials after first bootstrap: `/root/hermes-access.txt` (mode 600).

## Data

| Host path | Container | Purpose |
| --- | --- | --- |
| `/root/.hermes` | `/opt/data` | SOUL.md, USER.md, config, sessions, memory |
| `/opt/shop/.env` | env | secrets + Docker DNS URLs |
| `./automation/hermes/skills/shop` | `/opt/data/skills/shop` (ro) | only shop-owner skill (P013) |

Inside the container, n8n is `http://n8n:5678` and the shop API is
`http://backend:8080`. Do not use `127.0.0.1` for those.

## Install skill files (already in this repo)

```bash
# bind-mounted read-only; no copy to ~/.hermes needed
./deploy.sh automation recreate
```

Hermes `.env` keys (all in `/opt/shop/.env`):

```bash
SHOP_OWNER_WEBHOOK_URL=http://n8n:5678/webhook/shop-product-create
SHOP_OWNER_WEBHOOK_SECRET=   # same value used by n8n workflows
SHOP_API_PUBLIC=http://backend:8080/api
N8N_BASE_URL=http://n8n:5678
N8N_API_KEY=
```

Scripts:

- `create-product.sh` → `/webhook/shop-product-create`
- `update-offer.sh` → `/webhook/shop-offer-update`
- `set-product-active.sh` → `/webhook/shop-product-active`
- `list-orders.sh` → `/webhook/shop-orders-summary`
- `find-product.sh` / `list-taxonomy.sh` → shop GET APIs via `backend`

n8n also pushes a 24h order digest to Telegram daily at 08:00 Asia/Tehran
(`shop-orders-digest`). That path does not go through Hermes.

n8n workflows live in `automation/n8n/shop-*.workflow.json`.

## Host gateway

The old `hermes-gateway.service` (root systemd) must stay **masked** (P004).
Two gateways with the same Telegram token will fight. Do not `systemctl unmask`.

## Telegram toolsets (P006)

In `/root/.hermes/config.yaml`, Telegram must **not** include `terminal`:

```yaml
platform_toolsets:
  telegram:
    - skills
    - vision
```

`known_builtin_toolsets.telegram` should still list `terminal` so Hermes treats it as declined.
Do not re-enable host shell from Telegram. Shop-owner scripts stay on disk; they cannot run until a later restricted executor exists.

## Shop-owner skill path (P013)

Canonical path only:

`automation/hermes/skills/shop/shop-owner` → `/opt/data/skills/shop/shop-owner`

Do not restore `skills/shop-owner` at the skills root (old copy with `127.0.0.1` and `requires_toolsets: [terminal]`). VPS backups: `/root/shop-owner.skill.p013.bak-*` and `/root/shop-owner.repo.p013.bak-*`.

## Docker DNS (P014)

Shop-owner scripts must call `http://n8n:5678` and `http://backend:8080`, never `127.0.0.1`.
They read optional extras from `${HERMES_HOME}/.env` and **do not** override compose env or accept loopback URLs.

Do not change n8n's own `N8N_WEBHOOK_URL=http://127.0.0.1:5678/` on the host — that is for the n8n UI/host, not Hermes.

## STT (P007)

In `/root/.hermes/config.yaml`:

```yaml
stt:
  enabled: true
  language: fa
```

Keep `fa` so owner voice notes transcribe as Persian. Do not set this back to `en`.
