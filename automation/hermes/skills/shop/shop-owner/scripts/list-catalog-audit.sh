#!/usr/bin/env bash
# Tail Telegram catalog-create audit log (P025). Read-only.
set -euo pipefail

LINES=30
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tail|-n) LINES="${2:-30}"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--tail N]" >&2
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

AUDIT_DIR="${SHOP_CATALOG_AUDIT_DIR:-${HERMES_HOME:-/opt/data}/logs}"
AUDIT_FILE="${SHOP_CATALOG_AUDIT_FILE:-${AUDIT_DIR}/shop-catalog-audit.jsonl}"

if [[ ! -f "$AUDIT_FILE" ]]; then
  echo "{\"ok\":true,\"count\":0,\"file\":\"${AUDIT_FILE}\",\"lines\":[],\"hint\":\"no audit lines yet\"}"
  exit 0
fi

AUDIT_FILE="$AUDIT_FILE" LINES="$LINES" python3 - <<'PY'
import json, os
path = os.environ["AUDIT_FILE"]
n = max(1, int(os.environ.get("LINES") or 30))
with open(path, encoding="utf-8") as f:
    lines = [ln.strip() for ln in f if ln.strip()]
tail = lines[-n:]
parsed = []
for ln in tail:
    try:
        parsed.append(json.loads(ln))
    except Exception:
        parsed.append({"raw": ln[:300]})
print(json.dumps({
    "ok": True,
    "file": path,
    "count": len(lines),
    "tail": len(parsed),
    "lines": parsed,
}, ensure_ascii=False))
PY
