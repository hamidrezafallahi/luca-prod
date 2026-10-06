#!/usr/bin/env bash
# Enable or disable a product via n8n (Docker DNS: n8n:5678). Never 127.0.0.1.
set -euo pipefail

NAME=""
PRODUCT_ID=""
ACTIVE=""

usage() {
  echo "Usage: $0 (--product-id ID | --name TEXT) --active true|false" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="${2:-}"; shift 2 ;;
    --product-id) PRODUCT_ID="${2:-}"; shift 2 ;;
    --active) ACTIVE="${2:-}"; shift 2 ;;
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
    "SHOP_OWNER_WEBHOOK_URL",
    "SHOP_OWNER_OFFER_UPDATE_URL",
    "SHOP_OWNER_PRODUCT_ACTIVE_URL",
    "SHOP_API_PUBLIC",
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

WEBHOOK_URL="${SHOP_OWNER_PRODUCT_ACTIVE_URL:-http://n8n:5678/webhook/shop-product-active}"
case "$WEBHOOK_URL" in
  *127.0.0.1*|*localhost*|*[::1]*)
    WEBHOOK_URL="http://n8n:5678/webhook/shop-product-active"
    ;;
esac
SECRET="${SHOP_OWNER_WEBHOOK_SECRET:-}"

if [[ -z "$SECRET" ]]; then
  echo "SHOP_OWNER_WEBHOOK_SECRET is not set" >&2
  exit 1
fi

if [[ -z "$NAME" && -z "$PRODUCT_ID" ]]; then
  usage
fi
if [[ "$ACTIVE" != "true" && "$ACTIVE" != "false" ]]; then
  usage
fi

ARGS=(
  -sS
  -X POST
  "$WEBHOOK_URL"
  -H "X-Shop-Webhook-Secret: ${SECRET}"
  -F "webhookSecret=${SECRET}"
  -F "isActive=${ACTIVE}"
)

[[ -n "$NAME" ]] && ARGS+=(-F "name=${NAME}")
[[ -n "$PRODUCT_ID" ]] && ARGS+=(-F "productId=${PRODUCT_ID}")

curl "${ARGS[@]}"
echo
