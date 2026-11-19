#!/usr/bin/env bash
# ==============================================================================
# Dexta Africa Enterprise Production Deployment Engine
# One-command orchestration for full production environment bootstrap
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}======================================================================${NC}"
echo -e "${CYAN}    Dexta Africa Enterprise Infrastructure - Production Deployment     ${NC}"
echo -e "${CYAN}======================================================================${NC}"

# 1. Environment preflight check
echo -e "\n${BLUE}[Step 1/6]${NC} Validating configuration and prerequisites..."
"$SCRIPT_DIR/validate-env.sh"

# Load environment
set -a
# shellcheck disable=SC1090
source "$ROOT_DIR/.env"
set +a

# 2. Service codebase preparation
echo -e "\n${BLUE}[Step 2/6]${NC} Resolving service repositories..."
"$SCRIPT_DIR/setup-services.sh"

# 3. Docker build
echo -e "\n${BLUE}[Step 3/6]${NC} Building multi-stage production container images..."
docker compose -f "$ROOT_DIR/docker-compose.yml" build --parallel

# 4. Bootstrap core persistence services (Postgres, Redis)
echo -e "\n${BLUE}[Step 4/6]${NC} Starting persistence services and verifying health..."
docker compose -f "$ROOT_DIR/docker-compose.yml" up -d postgres redis

echo -e "Waiting for PostgreSQL and Redis to achieve healthy status..."
until docker compose -f "$ROOT_DIR/docker-compose.yml" ps postgres --filter "status=running" | grep -q "healthy"; do
    sleep 2
done
until docker compose -f "$ROOT_DIR/docker-compose.yml" ps redis --filter "status=running" | grep -q "healthy"; do
    sleep 2
done
echo -e "${GREEN}[OK]${NC} PostgreSQL and Redis are healthy and accepting connections."

# 5. Start application cluster (Backend, Frontend, Admin-Portal)
echo -e "\n${BLUE}[Step 5/6]${NC} Launching application cluster and running migrations..."
docker compose -f "$ROOT_DIR/docker-compose.yml" up -d backend frontend admin-portal

echo -e "Waiting for applications to achieve healthy status..."
until docker compose -f "$ROOT_DIR/docker-compose.yml" ps backend --filter "status=running" | grep -q "healthy"; do
    sleep 2
done
until docker compose -f "$ROOT_DIR/docker-compose.yml" ps frontend --filter "status=running" | grep -q "healthy"; do
    sleep 2
done
until docker compose -f "$ROOT_DIR/docker-compose.yml" ps admin-portal --filter "status=running" | grep -q "healthy"; do
    sleep 2
done
echo -e "${GREEN}[OK]${NC} Core Backend, Frontend Web, and Admin Portal are fully operational."

# 6. Initialize SSL and Edge Reverse Proxy
echo -e "\n${BLUE}[Step 6/6]${NC} Initializing SSL certificates and ingress routing..."
"$SCRIPT_DIR/init-ssl.sh"

# Start Certbot auto-renewal background worker
docker compose -f "$ROOT_DIR/docker-compose.yml" up -d certbot

echo -e "\n${GREEN}======================================================================${NC}"
echo -e "${GREEN}     Dexta Africa Infrastructure Deployment Successfully Completed!    ${NC}"
echo -e "${GREEN}======================================================================${NC}"
echo -e "  • Public Web Experience:      https://${DOMAIN:-dextaafrica.com}"
echo -e "  • Operations Command Portal:  https://${OPS_DOMAIN:-ops.dextaafrica.com}"
echo -e "  • Systems IT Admin Portal:    https://${ADMIN_DOMAIN:-admin.dextaafrica.com}"
echo -e "  • Core API Gateway:           https://${API_DOMAIN:-api.dextaafrica.com}"
echo -e "\nRun ${CYAN}make status${NC} to view live container telemetry."
echo -e "Run ${CYAN}make logs${NC} to monitor unified streaming logs."
