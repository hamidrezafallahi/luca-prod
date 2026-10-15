#!/bin/bash
# =============================================================================
# First-time Let's Encrypt issuance for ${DOMAIN_NAME} and www.${DOMAIN_NAME}.
#
# Usage: ./init-ssl.sh
#
# Requires DNS A records for both names pointing at SERVER_IP and the stack
# already up (deploy.sh / compose up). This script does not start or recreate
# services: nginx must already be running to serve the webroot challenge.
# nginx_reloader restarts it onto the new cert; certbot_renew handles renewal.
# =============================================================================

set -euo pipefail

cd "$(dirname "$0")"
COMPOSE="docker compose -p shop -f docker-compose.prod.yml"

DOMAIN_NAME="$(grep -E '^DOMAIN_NAME=' .env | cut -d= -f2-)"
SERVER_IP="$(grep -E '^SERVER_IP=' .env | cut -d= -f2-)"

echo "Checking DNS for ${DOMAIN_NAME} (expect ${SERVER_IP})..."
dns_ok=1
for name in "${DOMAIN_NAME}" "www.${DOMAIN_NAME}"; do
  ips="$(getent ahostsv4 "$name" | awk '{print $1}' | sort -u | tr '\n' ' ' || true)"
  echo "  $name -> ${ips:-<no record>}"
  if [[ " $ips " != *" ${SERVER_IP} "* ]]; then
    dns_ok=0
  fi
done
if [[ "$dns_ok" != 1 ]]; then
  echo "ERROR: DNS does not point at ${SERVER_IP} yet. Fix the A records and retry."
  exit 1
fi

# Only check; "up -d" would pull/recreate nginx's dependencies (backend, frontend).
echo "Checking that nginx is running (serves /.well-known/acme-challenge/)..."
running="$($COMPOSE ps --status running --services)"
if ! grep -qx nginx <<<"$running"; then
  echo "ERROR: nginx is not running. Bring the stack up first, e.g.:"
  echo "  $COMPOSE up -d"
  exit 1
fi
for svc in certbot_renew nginx_reloader; do
  if ! grep -qx "$svc" <<<"$running"; then
    echo "WARNING: $svc is not running; start it with: $COMPOSE up -d --no-deps $svc"
  fi
done

echo "Requesting certificate..."
$COMPOSE --profile init-certs run --rm certbot_init

echo "Restarting nginx onto the Let's Encrypt cert..."
docker restart shop-nginx-prod >/dev/null
sleep 5
echo | openssl s_client -connect 127.0.0.1:443 -servername "${DOMAIN_NAME}" 2>/dev/null \
  | openssl x509 -noout -issuer -subject -enddate
