#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log()  { echo -e "${GREEN}[tokscale]${NC} $*"; }
err()  { echo -e "${RED}[tokscale]${NC} $*" >&2; }

DC="docker compose -f $SCRIPT_DIR/docker-compose.yml --env-file $SCRIPT_DIR/.env"

check_env() {
  if [ ! -f "$SCRIPT_DIR/.env" ]; then
    err ".env not found. Run: cp .env.example .env && edit .env"
    exit 1
  fi
  source "$SCRIPT_DIR/.env"

  for var in POSTGRES_PASSWORD GITHUB_CLIENT_ID GITHUB_CLIENT_SECRET NEXT_PUBLIC_URL; do
    if [ -z "${!var:-}" ]; then
      err "Missing required env var: $var"
      exit 1
    fi
  done

  if [ "$POSTGRES_PASSWORD" = "CHANGE_ME_TO_A_STRONG_PASSWORD" ]; then
    err "Change POSTGRES_PASSWORD from the default value."
    exit 1
  fi

  command -v docker >/dev/null 2>&1 || { err "docker is required."; exit 1; }
  docker compose version >/dev/null 2>&1 || { err "docker compose v2 is required."; exit 1; }
}

case "${1:-help}" in
  up)
    check_env
    source "$SCRIPT_DIR/.env"

    log "Building and starting services..."
    $DC up -d --build

    log "Waiting for database..."
    sleep 5

    log "Running database migrations..."
    $DC exec app npx drizzle-kit push --force

    log "Seeding admin user..."
    ADMIN_USERNAME="admin"
    ADMIN_TOKEN="tt_${ADMIN_USERNAME}"
    ADMIN_TOKEN_HASH=$(echo -n "$ADMIN_TOKEN" | shasum -a 256 | cut -d' ' -f1)
    $DC exec -T db psql -U tokscale -d tokscale -q <<SQL
INSERT INTO users (github_id, username, display_name, is_admin)
VALUES (abs(hashtext('$ADMIN_USERNAME')), '$ADMIN_USERNAME', '$ADMIN_USERNAME', true)
ON CONFLICT (username) DO UPDATE SET is_admin = true;

DELETE FROM api_tokens
WHERE user_id = (SELECT id FROM users WHERE username = '$ADMIN_USERNAME')
  AND name = 'default';

INSERT INTO api_tokens (user_id, token, name)
VALUES ((SELECT id FROM users WHERE username = '$ADMIN_USERNAME'), '$ADMIN_TOKEN_HASH', 'default');
SQL
    log "Admin seeded (token: $ADMIN_TOKEN)"

    log ""
    log "Tokscale is live at ${NEXT_PUBLIC_URL}"
    log ""
    log "Team setup:"
    log "  export TOKSCALE_API_URL=${NEXT_PUBLIC_URL}"
    log "  tokscale login"
    log "  tokscale submit"
    ;;

  down)
    $DC down
    ;;

  logs)
    $DC logs -f "${2:-}"
    ;;

  migrate)
    check_env
    log "Running database migrations..."
    $DC exec app npx drizzle-kit push --force
    ;;

  restart)
    $DC restart
    ;;

  status)
    $DC ps
    ;;

  *)
    echo "Usage: $0 {up|down|logs|migrate|restart|status}"
    echo ""
    echo "  up         Build, start, and migrate DB"
    echo "  down       Stop all services"
    echo "  logs       Tail logs (optionally: logs app|db)"
    echo "  migrate    Run DB migrations"
    echo "  restart    Restart all services"
    echo "  status     Show service status"
    ;;
esac
