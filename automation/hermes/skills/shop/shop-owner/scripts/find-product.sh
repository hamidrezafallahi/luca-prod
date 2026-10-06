#!/usr/bin/env bash
# Search live catalog by name (public GET).
set -euo pipefail

KEYWORD="${1:-}"
if [[ -z "$KEYWORD" ]]; then
  echo "Usage: $0 KEYWORD" >&2
  exit 2
fi

load_env() {
  python3 - <<'PY'
import os
from pathlib import Path
p = Path(os.environ.get("HERMES_HOME") or "/opt/data") / ".env"
if not p.exists():
    raise SystemExit(0)
want = {"SHOP_API_PUBLIC"}
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

API_BASE="${SHOP_API_PUBLIC:-http://backend:8080/api}"
case "$API_BASE" in
  *127.0.0.1*|*localhost*|*[::1]*)
    API_BASE="http://backend:8080/api"
    ;;
esac
curl -sS "${API_BASE}/Products/search?keyword=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$KEYWORD")"
echo
