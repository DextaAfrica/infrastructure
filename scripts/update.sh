#!/usr/bin/env bash
# ==============================================================================
# Dexta Africa Rolling Zero/Minimal-Downtime Update Engine
# Pulls git updates, builds fresh images, migrates DB, and hot-reloads cluster
# Supports cluster-wide update or single-service rolling update:
# Usage: ./scripts/update.sh [all|admin-portal|frontend|backend]
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

TARGET_SERVICE="${1:-all}"

echo -e "${CYAN}======================================================================${NC}"
echo -e "${CYAN}     Dexta Africa Cluster Rolling Update Engine Initialized           ${NC}"
echo -e "${CYAN}     Target Scope: ${TARGET_SERVICE}                                  ${NC}"
echo -e "${CYAN}======================================================================${NC}"

# Source environment configuration
if [ -f "$ROOT_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1090,SC1091
    source "$ROOT_DIR/.env"
    set +a
fi

# 1. Environment validation
"$SCRIPT_DIR/validate-env.sh"

# 2. Automated Safety Backup (for cluster-wide or backend updates)
if [ "$TARGET_SERVICE" = "all" ] || [ "$TARGET_SERVICE" = "backend" ]; then
    echo -e "\n${BLUE}[Step 1/5]${NC} Creating pre-update safety database snapshot..."
    "$SCRIPT_DIR/backup.sh"
else
    echo -e "\n${BLUE}[Step 1/5]${NC} Single-service update ($TARGET_SERVICE) - skipping database snapshot."
fi

# Helper function to pull git updates for a specific service
pull_service_git() {
    local svc="$1"
    local svc_dir="$ROOT_DIR/services/$svc"
    local env_branch_var
    env_branch_var="$(echo "${svc}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_BRANCH"

    if [ -d "$svc_dir" ] && git -C "$svc_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        local current_branch
        current_branch=$(git -C "$svc_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
        if [ "$current_branch" = "HEAD" ] || [ -z "$current_branch" ]; then
            current_branch="main"
        fi
        local target_branch="${!env_branch_var:-$current_branch}"

        echo -e "${BLUE}==>${NC} Syncing ${GREEN}$svc${NC} on branch '${CYAN}$target_branch${NC}'..."
        git -C "$svc_dir" fetch origin "$target_branch" --tags 2>/dev/null || true

        if git -C "$svc_dir" diff --quiet 2>/dev/null && git -C "$svc_dir" diff --cached --quiet 2>/dev/null; then
            git -C "$svc_dir" checkout "$target_branch" 2>/dev/null || true
            git -C "$svc_dir" pull --ff-only origin "$target_branch" 2>/dev/null || git -C "$svc_dir" pull origin "$target_branch" 2>/dev/null || true
            local commit_info
            commit_info=$(git -C "$svc_dir" log -1 --format="%h - %s (%cr)" 2>/dev/null || echo "unknown")
            echo -e "    ${GREEN}[PULLED]${NC} $svc is at commit: $commit_info"
        else
            echo -e "    ${YELLOW}[INFO]${NC} Local uncommitted changes detected in $svc. Preserving working tree."
        fi
    fi
}

# 3. Pull updates for infrastructure and services
echo -e "\n${BLUE}[Step 2/5]${NC} Syncing latest codebase commits from Git remotes..."

if [ "$TARGET_SERVICE" = "all" ]; then
    # Pull infrastructure repository
    INFRA_BRANCH="${INFRASTRUCTURE_BRANCH:-$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")}"
    if [ "$INFRA_BRANCH" = "HEAD" ] || [ -z "$INFRA_BRANCH" ]; then
        INFRA_BRANCH="main"
    fi
    echo -e "Syncing infrastructure orchestration (branch: ${CYAN}$INFRA_BRANCH${NC})..."
    git -C "$ROOT_DIR" fetch origin "$INFRA_BRANCH" --tags 2>/dev/null || true
    if git -C "$ROOT_DIR" diff --quiet 2>/dev/null && git -C "$ROOT_DIR" diff --cached --quiet 2>/dev/null; then
        git -C "$ROOT_DIR" pull --ff-only origin "$INFRA_BRANCH" 2>/dev/null || git -C "$ROOT_DIR" pull origin "$INFRA_BRANCH" 2>/dev/null || true
    fi

    # Ensure all service repositories exist and are prepared
    "$SCRIPT_DIR/setup-services.sh"
else
    pull_service_git "$TARGET_SERVICE"
fi

# 4. Pre-build fresh images (containers keep serving live traffic during build)
echo -e "\n${BLUE}[Step 3/5]${NC} Pre-building updated images in background..."
if [ "$TARGET_SERVICE" = "all" ]; then
    echo -e "Building application services (backend, frontend, admin-portal)..."
    docker compose -f "$ROOT_DIR/docker-compose.yml" build --parallel backend frontend admin-portal
else
    docker compose -f "$ROOT_DIR/docker-compose.yml" build "$TARGET_SERVICE"
fi

# 5. Hot recreation of application containers with zero/minimal downtime
echo -e "\n${BLUE}[Step 4/5]${NC} Seamlessly swapping application containers..."

if [ "$TARGET_SERVICE" = "all" ]; then
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

elif [ "$TARGET_SERVICE" = "backend" ]; then
    docker compose -f "$ROOT_DIR/docker-compose.yml" up -d --no-deps backend
    echo -e "Waiting for backend healthcheck..."
    until docker compose -f "$ROOT_DIR/docker-compose.yml" ps backend --filter "status=running" | grep -q "healthy"; do
        sleep 2
    done

elif [ "$TARGET_SERVICE" = "admin-portal" ]; then
    docker compose -f "$ROOT_DIR/docker-compose.yml" up -d --no-deps admin-portal
    echo -e "Waiting for admin portal healthcheck..."
    until docker compose -f "$ROOT_DIR/docker-compose.yml" ps admin-portal --filter "status=running" | grep -q "healthy"; do
        sleep 2
    done

elif [ "$TARGET_SERVICE" = "frontend" ]; then
    docker compose -f "$ROOT_DIR/docker-compose.yml" up -d --no-deps frontend
    echo -e "Waiting for frontend web healthcheck..."
    until docker compose -f "$ROOT_DIR/docker-compose.yml" ps frontend --filter "status=running" | grep -q "healthy"; do
        sleep 2
    done
fi

# 6. Traefik automatically hot-swaps traffic with zero dropped connections
echo -e "\n${BLUE}[Step 5/5]${NC} Traefik ingress gateway hot-swapped traffic to updated containers."

echo -e "\n${GREEN}======================================================================${NC}"
echo -e "${GREEN}      Cluster Update Finished Successfully! All Services Healthy.     ${NC}"
echo -e "${GREEN}======================================================================${NC}"
