# SEO Automation Pack (candyRose / production)

This repo hosts **infra + n8n workflows**. App code (`SeoOps`, blog quality gates) lives in [OnlineShop-Compose](https://github.com/hamidrezafallahi/OnlineShop-Compose) and reaches production only after a **new backend image** is deployed.

## Workflows in this folder

| File | Schedule (Asia/Tehran) | Purpose | Human gate |
|---|---|---|---|
| `ai-blog-seo-daily.workflow.json` | Daily 08:00 | AI draft from **Google Suggest search-demand** (multi-seed) + catalog relevance; `.env` keywords are optional boost only | Activate in admin |
| `seo-site-health-daily.workflow.json` | Daily 07:00 | Probe sitemap/robots/home/blog/API | Alert only |
| `seo-weekly-digest.workflow.json` | Mon 09:00 | Inventory + priorities | Review digest |
| `seo-meta-optimizer-weekly.workflow.json` | Tue 10:00 | Title/meta suggestions | Apply manually |
| `seo-internal-links-weekly.workflow.json` | Wed 11:00 | Internal link suggestions | Edit manually |
| `seo-content-refresh-weekly.workflow.json` | Thu 12:00 | Refresh briefs for stale posts | Edit + republish |
| `shop-product-create.workflow.json` | Webhook `POST /webhook/shop-product-create` | Create product + image + offer from Hermes | Confirm in Telegram first |
| `shop-offer-update.workflow.json` | Webhook `POST /webhook/shop-offer-update` | Change price and/or inventory | Confirm in Telegram first |
| `shop-product-active.workflow.json` | Webhook `POST /webhook/shop-product-active` | Enable or disable a product | Confirm in Telegram first |
| `shop-orders-summary.workflow.json` | Webhook `POST /webhook/shop-orders-summary` | Open/new order summary or one order detail | Read-only |
| `shop-orders-digest.workflow.json` | Daily 08:00 Tehran + webhook `POST /webhook/shop-orders-digest` | Push last-24h order summary to owner Telegram | Automatic |

## Prerequisite: backend image with SeoOps

These endpoints must exist on production API (from OnlineShop-Compose):

- `GET /api/SeoOps/health`
- `GET /api/SeoOps/snapshot`
- `GET /api/SeoOps/meta-audit`
- `GET /api/SeoOps/refresh-candidates`
- `GET /api/SeoOps/internal-links/{id}`
- `GET /api/Blogs/getslugs?includeInactive=true` (draft-safe slug check)
- `POST /api/Blogs/validate-content`

If backend SHA is older than that code, import workflows but expect `404` on `/api/SeoOps/*` until you deploy a new backend image.

## VPS setup

```bash
cd /opt/shop
# 1) ensure .env has SEO/n8n keys (see ../.env.example)
# 2) deploy backend that includes SeoOps
./deploy.sh backend <onlineShop-Compose-sha>
# 3) refresh n8n + workflow files from this repo
./deploy.sh automation recreate
```

Open n8n (SSH tunnel recommended):

```bash
ssh -L 5678:127.0.0.1:5678 user@VPS
# then http://localhost:5678
```

Import every `*.workflow.json` here → Test once → Activate.

## Required env (production)

```bash
API_BASE_URL=http://backend:8080/api
CONTENT_BOT_EMAIL=content-bot@onlineshop.local
CONTENT_BOT_PASSWORD=...          # must match ContentAutomation__ServiceAccountPassword
CONTENT_ADMIN_BASE_URL=https://lucaloupe.com

# AI blog keywords (edit anytime; recreate n8n to reload env)
# BLOG_KEYWORDS_JSON='["keyword 1","keyword 2",...]'
# BLOG_SUGGEST_QUERY=لوپ دندان‌پزشکی
# SEED_TOPICS_JSON is legacy fallback if BLOG_KEYWORDS_JSON is unset

# Owner-command webhook (Hermes on host → n8n on 127.0.0.1:5678)
SHOP_OWNER_WEBHOOK_SECRET=

# Daily order digest (n8n → Telegram Bot API). Token only on VPS .env, never in git.
TELEGRAM_CHAT_ID=
TELEGRAM_BOT_TOKEN=

# Backend health probes (from inside Docker network / public site)
SeoOps__SitePublicUrl=https://lucaloupe.com
SeoOps__ApiPublicUrl=http://backend:8080

# Optional alert sink: Slack/Discord/generic JSON { "text": "..." }
SEO_ALERT_WEBHOOK_URL=
SEO_STALE_DAYS=90

# LLM — same OpenRouter registration as Hermes Telegram (`/root/.hermes/config.yaml`)
# Hermes model alias: openrouter/free (resolves to a live free model).
# Do not use meta-llama/llama-3.3-70b-instruct:free — that ID 404s on this key.
LLM_API_URL=https://openrouter.ai/api/v1/chat/completions
LLM_MODEL=openrouter/free
OPENROUTER_API_KEY=               # used by daily blog + digest/meta/refresh via $env
```

### Daily blog LLM auth

SEO LLM nodes (daily blog + weekly digest/meta/refresh) call OpenRouter with `$env.LLM_MODEL` (default **`openrouter/free`**). Auth is `OPENROUTER_API_KEY` (or `LLM_API_KEY`) from container env.

Do **not** use `meta-llama/llama-3.3-70b-instruct:free` — OpenRouter 404s that slug. Recreate n8n after changing `.env`, then re-import this workflow JSON (n8n does not load disk files by itself).

## Safety rules (do not change)

- Drafts stay inactive until human activates
- Meta / links / refresh workflows only **suggest**
- No auto-publish, no mass outreach

## Troubleshooting

| Symptom | Fix |
|---|---|
| `/api/SeoOps/*` 404 | Deploy newer backend image from OnlineShop-Compose |
| LLM 403 | Use OpenRouter, not Groq, on VPS |
| Login failed | Sync `CONTENT_BOT_*` with `ContentAutomation__*` |
| Health fails on public URLs | Set `SeoOps__SitePublicUrl=https://lucaloupe.com` and recreate backend |
| No Slack/Discord message | Set `SEO_ALERT_WEBHOOK_URL` or read n8n Executions |
| Owner product webhook 401 | Set `SHOP_OWNER_WEBHOOK_SECRET` in `/opt/shop/.env` and Hermes `.env`, then `./deploy.sh automation recreate` |
| Owner product webhook 404 | Import + activate `shop-product-create.workflow.json`; URL is `/webhook/shop-product-create` not `/webhook-test/` |
| Offer update 403 Unauthorized | Deploy backend that allows ContentEditor to update any ProductOffer (staff bypass). Current catalog offers belong to SuperAdmin, not the content bot. |
| Daily digest did not arrive | Set `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` in `/opt/shop/.env`, then `./deploy.sh automation recreate`. Smoke: `POST /webhook/shop-orders-digest` with the owner webhook secret. |
