#!/usr/bin/env bash
# Create a shop product via the n8n webhook (Docker DNS: n8n:5678).
# Does not talk to Postgres or the shop login. n8n owns that.
# Never use 127.0.0.1 — that is the Hermes container loopback, not n8n.
set -euo pipefail

NAME=""
DESCRIPTION=""
PRICE=""
INVENTORY=""
CATEGORY_ID=""
BRAND_ID=""
IMAGE=""
SEO_TITLE=""
META_DESC=""
MAGNIFICATION=""
WORKING_DISTANCE=""
FIELD_OF_VIEW=""

usage() {
  echo "Usage: $0 --name TEXT --price NUMBER --inventory INT --category-id ID --brand-id ID [--description TEXT] [--image FILE] [--seo-title TEXT] [--meta-desc TEXT] [--magnification X] [--working-distance CM] [--field-of-view MM]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="${2:-}"; shift 2 ;;
    --description) DESCRIPTION="${2:-}"; shift 2 ;;
    --price) PRICE="${2:-}"; shift 2 ;;
    --inventory) INVENTORY="${2:-}"; shift 2 ;;
    --category-id) CATEGORY_ID="${2:-}"; shift 2 ;;
    --brand-id) BRAND_ID="${2:-}"; shift 2 ;;
    --image) IMAGE="${2:-}"; shift 2 ;;
    --seo-title) SEO_TITLE="${2:-}"; shift 2 ;;
    --meta-desc) META_DESC="${2:-}"; shift 2 ;;
    --magnification) MAGNIFICATION="${2:-}"; shift 2 ;;
    --working-distance) WORKING_DISTANCE="${2:-}"; shift 2 ;;
    --field-of-view) FIELD_OF_VIEW="${2:-}"; shift 2 ;;
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

WEBHOOK_URL="${SHOP_OWNER_WEBHOOK_URL:-http://n8n:5678/webhook/shop-product-create}"
case "$WEBHOOK_URL" in
  *127.0.0.1*|*localhost*|*[::1]*)
    WEBHOOK_URL="http://n8n:5678/webhook/shop-product-create"
    ;;
esac
SECRET="${SHOP_OWNER_WEBHOOK_SECRET:-}"

if [[ -z "$SECRET" ]]; then
  echo "SHOP_OWNER_WEBHOOK_SECRET is not set" >&2
  exit 1
fi

if [[ -z "$NAME" || -z "$PRICE" || -z "$INVENTORY" || -z "$CATEGORY_ID" || -z "$BRAND_ID" ]]; then
  usage
fi

if [[ -n "$IMAGE" && ! -f "$IMAGE" ]]; then
  echo "Image file not found: $IMAGE" >&2
  exit 1
fi

# P024: never invent taxonomy — ids must already exist on the live lists.
API_BASE="${SHOP_API_PUBLIC:-http://backend:8080/api}"
case "$API_BASE" in
  *127.0.0.1*|*localhost*|*[::1]*)
    API_BASE="http://backend:8080/api"
    ;;
esac
CATEGORY_ID="$CATEGORY_ID" BRAND_ID="$BRAND_ID" API_BASE="$API_BASE" python3 - <<'PY'
import json, os, urllib.request, sys

api = os.environ["API_BASE"].rstrip("/")
cid = int(os.environ["CATEGORY_ID"])
bid = int(os.environ["BRAND_ID"])

def fetch(path):
    with urllib.request.urlopen(f"{api}/{path}", timeout=30) as r:
        return json.loads(r.read().decode())

def records(payload):
    data = payload.get("data") if isinstance(payload, dict) else payload
    if isinstance(data, dict):
        return data.get("records") or data.get("Records") or []
    return data if isinstance(data, list) else []

cats = records(fetch("Categories?page=1&pageSize=100&onlyActives=true"))
brands = records(fetch("Brands?page=1&pageSize=100&onlyActives=true"))
if not any(int(c.get("id", -1)) == cid for c in cats if isinstance(c, dict)):
    print(json.dumps({"ok": False, "error": f"categoryId {cid} is not in live taxonomy; never create categories"}, ensure_ascii=False))
    sys.exit(1)
if not any(int(b.get("id", -1)) == bid for b in brands if isinstance(b, dict)):
    print(json.dumps({"ok": False, "error": f"brandId {bid} is not in live taxonomy; never create brands"}, ensure_ascii=False))
    sys.exit(1)
PY

ARGS=(
  -sS
  -X POST
  "$WEBHOOK_URL"
  -H "X-Shop-Webhook-Secret: ${SECRET}"
  -F "name=${NAME}"
  -F "description=${DESCRIPTION:-$NAME}"
  -F "price=${PRICE}"
  -F "inventory=${INVENTORY}"
  -F "categoryId=${CATEGORY_ID}"
  -F "brandId=${BRAND_ID}"
  -F "seoTitleFa=${SEO_TITLE:-$NAME}"
  -F "metaDescriptionFa=${META_DESC:-${DESCRIPTION:-$NAME}}"
  -F "webhookSecret=${SECRET}"
)

if [[ -n "$IMAGE" ]]; then
  ARGS+=(-F "image=@${IMAGE}")
fi
[[ -n "$MAGNIFICATION" ]] && ARGS+=(-F "magnification=${MAGNIFICATION}")
[[ -n "$WORKING_DISTANCE" ]] && ARGS+=(-F "workingDistance=${WORKING_DISTANCE}")
[[ -n "$FIELD_OF_VIEW" ]] && ARGS+=(-F "fieldOfView=${FIELD_OF_VIEW}")

RESP="$(curl "${ARGS[@]}")"
echo "$RESP"

# P025: append-only JSONL audit (who/what from Telegram create path)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/append-catalog-audit.sh" ]]; then
  CREATE_RESPONSE="$RESP" NAME="$NAME" CATEGORY_ID="$CATEGORY_ID" BRAND_ID="$BRAND_ID" \
    PRICE="$PRICE" INVENTORY="$INVENTORY" \
    bash "${SCRIPT_DIR}/append-catalog-audit.sh" || true
fi
