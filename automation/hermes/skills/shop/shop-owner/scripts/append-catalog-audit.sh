#!/usr/bin/env bash
# Append one catalog-create audit line (JSONL). Never talks to Postgres.
# Pass create JSON via CREATE_RESPONSE env (not stdin — python heredoc would swallow stdin).
set -euo pipefail

AUDIT_DIR="${SHOP_CATALOG_AUDIT_DIR:-${HERMES_HOME:-/opt/data}/logs}"
AUDIT_FILE="${SHOP_CATALOG_AUDIT_FILE:-${AUDIT_DIR}/shop-catalog-audit.jsonl}"
mkdir -p "$AUDIT_DIR"

if [[ -z "${CREATE_RESPONSE:-}" && ! -t 0 ]]; then
  CREATE_RESPONSE="$(cat || true)"
fi
export AUDIT_FILE
export CREATE_RESPONSE="${CREATE_RESPONSE:-}"

python3 - <<'PY'
import json, os
from datetime import datetime, timezone

raw = (os.environ.get("CREATE_RESPONSE") or "").strip()
try:
    payload = json.loads(raw) if raw else {}
except Exception:
    payload = {"ok": False, "error": "non-json create response", "raw": raw[:500]}

ok = payload.get("ok") is True or payload.get("isSuccess") is True
product_id = payload.get("productId") or (payload.get("data") or {}).get("productId")
offer_id = payload.get("offerId") or (payload.get("data") or {}).get("offerId")
name = payload.get("name") or os.environ.get("NAME") or ""

line = {
    "ts": datetime.now(timezone.utc).isoformat(),
    "action": "catalog.create",
    "source": "telegram-owner",
    "channel": "hermes-script",
    "ok": bool(ok),
    "actorTelegramIds": [
        x.strip() for x in str(os.environ.get("TELEGRAM_ALLOWED_USERS") or "").split(",") if x.strip()
    ],
    "productId": product_id,
    "offerId": offer_id,
    "name": name,
    "categoryId": int(os.environ["CATEGORY_ID"]) if os.environ.get("CATEGORY_ID") else None,
    "brandId": int(os.environ["BRAND_ID"]) if os.environ.get("BRAND_ID") else None,
    "price": os.environ.get("PRICE"),
    "inventory": os.environ.get("INVENTORY"),
    "error": None if ok else (payload.get("error") or "create failed"),
}

path = os.environ["AUDIT_FILE"]
with open(path, "a", encoding="utf-8") as f:
    f.write(json.dumps(line, ensure_ascii=False) + "\n")
PY
