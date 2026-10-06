#!/usr/bin/env bash
# List open orders or one order's detail via n8n (Docker DNS: n8n:5678). Never 127.0.0.1.
# Read-only. «سفارش‌های امروز» = --hours 24. Does not confirm/pay/cancel.
set -euo pipefail

HOURS="72"
STATUSES="pending,confirmed,paid"
LIMIT="15"
ORDER_ID=""

usage() {
  echo "Usage: $0 [--hours N] [--status pending,confirmed,paid] [--limit N] [--order-id ID]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hours) HOURS="${2:-}"; shift 2 ;;
    --status|--statuses) STATUSES="${2:-}"; shift 2 ;;
    --limit) LIMIT="${2:-}"; shift 2 ;;
    --order-id) ORDER_ID="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

load_env() {
  python3 - <<'PY'
import os
from pathlib import Path
p = Path(os.environ.get("HERMES_HOME") or "/opt/data") / ".env"
if not p.exists():
    raise SystemExit(0)
want = {
    "SHOP_OWNER_WEBHOOK_SECRET",
    "SHOP_OWNER_ORDERS_URL",
}
for line in p.read_text(encoding="utf-8").splitlines():
    raw = line.strip()
    if not raw or raw.startswith("#") or "=" not in raw:
        continue
    key, val = raw.split("=", 1)
    if key not in want:
        continue
    if os.environ.get(key):
        continue
    if "127.0.0.1" in val or "localhost" in val.lower():
        continue
    print(f"{key}={val}")
PY
}

ENV_FILE="${HERMES_HOME:-/opt/data}/.env"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  eval "$(load_env)"
  set +a
fi

WEBHOOK_URL="${SHOP_OWNER_ORDERS_URL:-http://n8n:5678/webhook/shop-orders-summary}"
case "$WEBHOOK_URL" in
  *127.0.0.1*|*localhost*|*[::1]*)
    WEBHOOK_URL="http://n8n:5678/webhook/shop-orders-summary"
    ;;
esac
SECRET="${SHOP_OWNER_WEBHOOK_SECRET:-}"

if [[ -z "$SECRET" ]]; then
  echo "SHOP_OWNER_WEBHOOK_SECRET is not set" >&2
  exit 1
fi

ARGS=(
  -sS
  -X POST
  "$WEBHOOK_URL"
  -H "X-Shop-Webhook-Secret: ${SECRET}"
  -F "webhookSecret=${SECRET}"
  -F "hours=${HOURS}"
  -F "statuses=${STATUSES}"
  -F "limit=${LIMIT}"
)

[[ -n "$ORDER_ID" ]] && ARGS+=(-F "orderId=${ORDER_ID}")

curl "${ARGS[@]}"
echo
