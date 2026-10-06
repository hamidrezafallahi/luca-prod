#!/bin/bash
# =============================================================================
# Deploy / rollback using immutable image tags (git SHA).
#
# Usage:
#   ./deploy.sh frontend <sha>
#   ./deploy.sh backend <sha>
#   ./deploy.sh all <sha>
#   ./deploy.sh nginx
#   ./deploy.sh automation [up|recreate|down]
#   ./deploy.sh rollback frontend
#   ./deploy.sh rollback backend
#   ./deploy.sh rollback all
#
# CI: see DEPLOY.md and .github/workflows/deploy.yml (always pass <sha> for app deploys).
# =============================================================================

set -euo pipefail

LOG_FILE="/var/log/shop-deploy.log"
STATE_DIR="/opt/shop/.deploy-state"
COMPOSE="docker compose -p shop -f docker-compose.prod.yml"
COMPOSE_AUTOMATION="docker compose -p shop -f docker-compose.automation.yml"

# هم در GitHub Actions نمایش داده می‌شود و هم در فایل لاگ ذخیره می‌شود.
exec > >(tee -a "$LOG_FILE") 2>&1

mkdir -p "$STATE_DIR"
cd /opt/shop

echo "=================================================="
echo "Deploy started at: $(date)"
echo "Args: $*"
echo "=================================================="

read_sha() {
  local service="$1"
  local file="$STATE_DIR/${service}.sha"
  if [[ -f "$file" ]]; then
    cat "$file"
  fi
}

write_sha() {
  local service="$1"
  local sha="$2"
  local file="$STATE_DIR/${service}.sha"
  local prev="$STATE_DIR/${service}.sha.prev"

  if [[ -f "$file" ]]; then
    cp "$file" "$prev"
  fi
  echo -n "$sha" > "$file"
}

update_env_tag() {
  local var_name="$1"
  local sha="$2"

  if grep -q "^${var_name}=" .env 2>/dev/null; then
    sed -i "s|^${var_name}=.*|${var_name}=${sha}|" .env
  else
    echo "${var_name}=${sha}" >> .env
  fi
}

wait_healthy() {
  local service="$1"
  local container="shop-${service}-prod"
  echo "Waiting for $container to become healthy..."
  for _ in $(seq 1 40); do
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container" 2>/dev/null || true)"
    if [[ "$status" == "healthy" ]]; then
      echo "$container is $status"
      return 0
    fi
    sleep 3
  done
  echo "ERROR: $container did not become healthy in time (last=${status:-unknown})"
  return 1
}

recreate_nginx() {
  echo "Recreating nginx..."
  $COMPOSE up -d --force-recreate --no-deps nginx
}

deploy_service() {
  local service="$1"
  local sha="$2"
  local var_name

  if [[ -z "$sha" ]]; then
    echo "ERROR: SHA is required for $service deploy (do not use :latest)."
    echo "Usage: ./deploy.sh $service <git-sha>"
    exit 1
  fi

  if [[ "$service" == "frontend" ]]; then
    var_name="FRONTEND_IMAGE_TAG"
  elif [[ "$service" == "backend" ]]; then
    var_name="BACKEND_IMAGE_TAG"
  else
    echo "ERROR: Unknown service '$service'"
    exit 1
  fi

  echo "Deploying $service @ $sha"
  update_env_tag "$var_name" "$sha"
  export "$var_name=$sha"

  $COMPOSE pull "$service"
  $COMPOSE up -d --force-recreate --no-deps "$service"
  wait_healthy "$service"
  write_sha "$service" "$sha"
}

rollback_service() {
  local service="$1"
  local prev_file="$STATE_DIR/${service}.sha.prev"
  if [[ ! -f "$prev_file" ]]; then
    echo "ERROR: No previous SHA for $service (cannot rollback)."
    exit 1
  fi
  local prev
  prev="$(cat "$prev_file")"
  if [[ -z "$prev" ]]; then
    echo "ERROR: Previous SHA for $service is empty."
    exit 1
  fi
  echo "Rolling back $service to $prev"
  deploy_service "$service" "$prev"
}

ACTION="${1:-}"
ARG2="${2:-}"

case "$ACTION" in
  frontend|backend)
    deploy_service "$ACTION" "$ARG2"
    if [[ "$ACTION" == "backend" ]]; then
      recreate_nginx
    fi
    ;;

  all)
    deploy_service frontend "$ARG2"
    deploy_service backend "$ARG2"
    recreate_nginx
    ;;

  nginx)
    recreate_nginx
    ;;

  automation|n8n|hermes)
    AUTOMATION_ACTION="${ARG2:-up}"
    case "$AUTOMATION_ACTION" in
      up|"")
        echo "Starting automation (n8n + hermes)..."
        $COMPOSE_AUTOMATION up -d
        ;;
      recreate)
        echo "Recreating automation (n8n + hermes)..."
        $COMPOSE_AUTOMATION up -d --force-recreate --no-deps n8n hermes
        ;;
      down)
        echo "Stopping automation (n8n + hermes)..."
        $COMPOSE_AUTOMATION down
        ;;
      *)
        echo "Usage: ./deploy.sh automation [up|recreate|down]"
        exit 1
        ;;
    esac
    ;;

  rollback)
    TARGET="${ARG2:-}"
    case "$TARGET" in
      frontend|backend)
        rollback_service "$TARGET"
        if [[ "$TARGET" == "backend" ]]; then
          recreate_nginx
        fi
        ;;
      all)
        rollback_service frontend
        rollback_service backend
        recreate_nginx
        ;;
      *)
        echo "Usage: ./deploy.sh rollback {frontend|backend|all}"
        exit 1
        ;;
    esac
    ;;

  *)
    echo "Usage:"
    echo "  ./deploy.sh {frontend|backend|all} <sha>"
    echo "  ./deploy.sh nginx"
    echo "  ./deploy.sh automation [up|recreate|down]"
    echo "  ./deploy.sh rollback {frontend|backend|all}"
    echo "Current frontend SHA: $(read_sha frontend || true)"
    echo "Current backend SHA:  $(read_sha backend || true)"
    exit 1
    ;;
esac

echo
echo "Pruning unused images..."
docker image prune -f

echo "=================================================="
echo "Deploy finished successfully at: $(date)"
echo "Frontend SHA: $(read_sha frontend || true)"
echo "Backend SHA:  $(read_sha backend || true)"
echo "Frontend image: $(docker inspect shop-frontend-prod --format '{{.Config.Image}}' 2>/dev/null || true)"
echo "Backend image:  $(docker inspect shop-backend-prod --format '{{.Config.Image}}' 2>/dev/null || true)"
echo "=================================================="
