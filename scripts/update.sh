#!/usr/bin/env bash
# ==============================================================================
# Dexta Africa Rolling Zero/Minimal-Downtime Update Engine
# Pulls git updates, builds fresh images, migrates DB, and hot-reloads cluster
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
echo -e "${CYAN}     Dexta Africa Cluster Rolling Update Engine Initialized           ${NC}"
echo -e "${CYAN}======================================================================${NC}"

# 1. Environment validation
"$SCRIPT_DIR/validate-env.sh"

# 2. Automated Safety Backup
echo -e "\n${BLUE}[Step 1/5]${NC} Creating pre-update safety database snapshot..."
"$SCRIPT_DIR/backup.sh"

# 3. Pull updates for infrastructure and services
echo -e "\n${BLUE}[Step 2/5]${NC} Syncing latest codebase commits from Git remotes..."
git -C "$ROOT_DIR" pull origin main || true

for svc in frontend admin-portal backend; do
    if [ -d "$ROOT_DIR/services/$svc/.git" ]; then
        echo -e "Pulling updates for services/$svc..."
        git -C "$ROOT_DIR/services/$svc" pull || true
    fi
done

# 4. Pre-build fresh images (containers keep serving live traffic during build)
echo -e "\n${BLUE}[Step 3/5]${NC} Pre-building updated images in background..."
docker compose -f "$ROOT_DIR/docker-compose.yml" build --parallel

# 5. Hot recreation of application containers with zero/minimal downtime
echo -e "\n${BLUE}[Step 4/5]${NC} Seamlessly swapping application containers..."
docker compose -f "$ROOT_DIR/docker-compose.yml" up -d --no-deps backend
echo -e "Waiting for backend healthcheck and database migration..."
until docker compose -f "$ROOT_DIR/docker-compose.yml" ps backend --filter "status=running" | grep -q "healthy"; do
    sleep 2
done

docker compose -f "$ROOT_DIR/docker-compose.yml" up -d --no-deps frontend admin-portal
echo -e "Waiting for web and admin portals to achieve healthy status..."
until docker compose -f "$ROOT_DIR/docker-compose.yml" ps frontend --filter "status=running" | grep -q "healthy"; do
    sleep 2
done
until docker compose -f "$ROOT_DIR/docker-compose.yml" ps admin-portal --filter "status=running" | grep -q "healthy"; do
    sleep 2
done

# 6. Reload Edge Reverse Proxy (gracefully drains existing connections without drops)
echo -e "\n${BLUE}[Step 5/5]${NC} Reloading Nginx ingress proxy without dropping active connections..."
docker compose -f "$ROOT_DIR/docker-compose.yml" exec reverse-proxy nginx -s reload

echo -e "\n${GREEN}======================================================================${NC}"
echo -e "${GREEN}      Cluster Update Finished Successfully! All Services Healthy.     ${NC}"
echo -e "${GREEN}======================================================================${NC}"
