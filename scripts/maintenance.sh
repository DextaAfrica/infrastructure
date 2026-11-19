#!/usr/bin/env bash
# ==============================================================================
# Dexta Africa Maintenance Mode CLI Control Engine
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
MAINTENANCE_DIR="$ROOT_DIR/docker/nginx/maintenance"
ACTIVE_FLAG="$MAINTENANCE_DIR/active"

mkdir -p "$MAINTENANCE_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ACTION="${1:-status}"

case "$ACTION" in
    on|enable|start)
        echo -e "${YELLOW}==>${NC} Enabling Enterprise Maintenance Mode..."
        touch "$ACTIVE_FLAG"
        
        # Reload Nginx if container is running
        if docker compose -f "$ROOT_DIR/docker-compose.yml" ps --services --filter "status=running" | grep -q "reverse-proxy"; then
            docker compose -f "$ROOT_DIR/docker-compose.yml" exec reverse-proxy nginx -s reload >/dev/null 2>&1 || true
        fi
        
        echo -e "${GREEN}[ACTIVE]${NC} Maintenance mode is now ENABLED."
        echo -e "         Public visitors will receive HTTP 503 with the branded maintenance page."
        echo -e "         Allowed CIDR bypass IPs and /api/health probes remain accessible."
        ;;

    off|disable|stop)
        echo -e "${BLUE}==>${NC} Disabling Enterprise Maintenance Mode..."
        rm -f "$ACTIVE_FLAG"
        
        # Reload Nginx if container is running
        if docker compose -f "$ROOT_DIR/docker-compose.yml" ps --services --filter "status=running" | grep -q "reverse-proxy"; then
            docker compose -f "$ROOT_DIR/docker-compose.yml" exec reverse-proxy nginx -s reload >/dev/null 2>&1 || true
        fi
        
        echo -e "${GREEN}[INACTIVE]${NC} Maintenance mode is now DISABLED."
        echo -e "           Full production traffic has been restored to all services."
        ;;

    status)
        if [ -f "$ACTIVE_FLAG" ]; then
            echo -e "${YELLOW}[STATUS]${NC} Maintenance mode is currently: ${RED}ACTIVE${NC} (Branded 503 Page Rendering)"
        else
            echo -e "${GREEN}[STATUS]${NC} Maintenance mode is currently: ${GREEN}INACTIVE${NC} (Live Traffic Serving)"
        fi
        ;;

    *)
        echo "Usage: $0 {on|off|status}"
        exit 1
        ;;
esac
