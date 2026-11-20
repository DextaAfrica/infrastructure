#!/usr/bin/env bash
# ==============================================================================
# Dexta Africa Enterprise Production Image Builder & Publisher
# Builds multi-stage production images with BuildKit caching & pushes to GHCR
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DEXTA_ROOT="$(dirname "$ROOT_DIR")"

TAG="${1:-main}"
DO_PUSH="${2:-false}"
REGISTRY="${REGISTRY:-ghcr.io/dextaafrica}"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "\n${CYAN}======================================================================${NC}"
echo -e "${CYAN}    Dexta Africa Enterprise Image Builder [Target: ${TAG}]            ${NC}"
echo -e "${CYAN}======================================================================${NC}"

# Enable Docker BuildKit for parallel multi-stage building and caching
export DOCKER_BUILDKIT=1

# ------------------------------------------------------------------------------
# 1. Build Backend API Gateway (Go Distroless)
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}==> [1/4] Building Backend API Gateway (${REGISTRY}/backend:${TAG})...${NC}"
BACKEND_DIR="$DEXTA_ROOT/Backend/Backend"
if [ ! -d "$BACKEND_DIR" ]; then
  BACKEND_DIR="$ROOT_DIR/services/backend"
fi

docker build \
  --file "$BACKEND_DIR/Dockerfile" \
  --tag "${REGISTRY}/backend:${TAG}" \
  --tag "${REGISTRY}/backend:latest" \
  --tag "${REGISTRY}/dexta-api:${TAG}" \
  --tag "${REGISTRY}/dexta-api:latest" \
  "$BACKEND_DIR"

# ------------------------------------------------------------------------------
# 2. Build Frontend Web Application (Next.js Standalone)
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}==> [2/4] Building Frontend Web Application (${REGISTRY}/frontend:${TAG})...${NC}"
FRONTEND_DIR="$DEXTA_ROOT/Frontend"
if [ ! -d "$FRONTEND_DIR" ]; then
  FRONTEND_DIR="$ROOT_DIR/services/frontend"
fi

docker build \
  --file "$FRONTEND_DIR/Dockerfile.prod" \
  --tag "${REGISTRY}/frontend:${TAG}" \
  --tag "${REGISTRY}/frontend:latest" \
  --tag "${REGISTRY}/dexta-frontend:${TAG}" \
  --tag "${REGISTRY}/dexta-frontend:latest" \
  "$FRONTEND_DIR"

# ------------------------------------------------------------------------------
# 3. Build Admin & Operations Portal (Next.js Multi-Tenant)
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}==> [3/4] Building Admin & Operations Portal (${REGISTRY}/admin-portal:${TAG})...${NC}"
ADMIN_DIR="$DEXTA_ROOT/Admin-portal"
if [ ! -d "$ADMIN_DIR" ]; then
  ADMIN_DIR="$ROOT_DIR/services/admin-portal"
fi

docker build \
  --file "$ADMIN_DIR/Dockerfile" \
  --build-arg DATABASE_URL="file:/app/prisma/admin_portal.db" \
  --build-arg APP_SECRET="dexta_build_fallback_secret_key_production_standalone" \
  --tag "${REGISTRY}/admin-portal:${TAG}" \
  --tag "${REGISTRY}/admin-portal:latest" \
  --tag "${REGISTRY}/dexta-admin:${TAG}" \
  --tag "${REGISTRY}/dexta-admin:latest" \
  "$ADMIN_DIR"

# ------------------------------------------------------------------------------
# 4. Build Lightweight Maintenance Gateway (Nginx HTTP 503)
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}==> [4/4] Building Maintenance Gateway (dexta-maintenance:local)...${NC}"
docker build \
  --file "$ROOT_DIR/prod/maintenance/Dockerfile" \
  --tag "dexta-maintenance:local" \
  --tag "${REGISTRY}/dexta-maintenance:${TAG}" \
  --tag "${REGISTRY}/dexta-maintenance:latest" \
  "$ROOT_DIR/prod/maintenance"

# ------------------------------------------------------------------------------
# Optional Push to Registry
# ------------------------------------------------------------------------------
if [ "$DO_PUSH" = "true" ] || [ "$DO_PUSH" = "--push" ]; then
  echo -e "\n${YELLOW}==> Pushing images to ${REGISTRY}...${NC}"
  docker push "${REGISTRY}/backend:${TAG}"
  docker push "${REGISTRY}/backend:latest"
  docker push "${REGISTRY}/dexta-api:${TAG}"
  docker push "${REGISTRY}/dexta-api:latest"

  docker push "${REGISTRY}/frontend:${TAG}"
  docker push "${REGISTRY}/frontend:latest"
  docker push "${REGISTRY}/dexta-frontend:${TAG}"
  docker push "${REGISTRY}/dexta-frontend:latest"

  docker push "${REGISTRY}/admin-portal:${TAG}"
  docker push "${REGISTRY}/admin-portal:latest"
  docker push "${REGISTRY}/dexta-admin:${TAG}"
  docker push "${REGISTRY}/dexta-admin:latest"

  docker push "${REGISTRY}/dexta-maintenance:${TAG}"
  docker push "${REGISTRY}/dexta-maintenance:latest"
  echo -e "\n${GREEN}[OK] Successfully pushed all images to ${REGISTRY}.${NC}"
fi

echo -e "\n${GREEN}======================================================================${NC}"
echo -e "${GREEN}     All Dexta Africa OCI Production Images Built Successfully!        ${NC}"
echo -e "${GREEN}======================================================================${NC}"
echo -e "Ready for zero-downtime cluster pull via: ${CYAN}make deploy${NC}\n"
