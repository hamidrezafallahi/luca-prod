#!/usr/bin/env bash
# Print active categories and brands from the shop API (Docker DNS: backend:8080). Never 127.0.0.1.
set -euo pipefail

API_BASE="${SHOP_API_PUBLIC:-http://backend:8080/api}"
case "$API_BASE" in
  *127.0.0.1*|*localhost*|*[::1]*)
    API_BASE="http://backend:8080/api"
    ;;
esac

echo "=== CATEGORIES ==="
curl -sS "${API_BASE}/Categories?page=1&pageSize=100&onlyActives=true"
echo
echo
echo "=== BRANDS ==="
curl -sS "${API_BASE}/Brands?page=1&pageSize=100&onlyActives=true"
echo
