#!/usr/bin/env bash
# ==============================================================================
# Dexta Africa Service Discovery & Synchronization Script
# Resolves, clones, or synchronizes Frontend, Admin-portal, and Backend codebases
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
SERVICES_DIR="$ROOT_DIR/services"
PARENT_DIR="$(dirname "$ROOT_DIR")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Source environment variables if .env exists
if [ -f "$ROOT_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1090,SC1091
    source "$ROOT_DIR/.env"
    set +a
fi

mkdir -p "$SERVICES_DIR"

echo -e "${BLUE}==>${NC} Discovering and syncing application repositories..."

# Function to link, clone, or synchronize service
prepare_service() {
    local service_name="$1"
    local repo_url="$2"
    local default_branch="${3:-main}"
    local target_dir="$SERVICES_DIR/$service_name"
    local sibling_dir="$PARENT_DIR/$service_name"

    # Resolve branch override from environment (e.g. ADMIN_PORTAL_BRANCH)
    local env_branch_var
    env_branch_var="$(echo "${service_name}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_BRANCH"
    local target_branch="${!env_branch_var:-$default_branch}"

    # Handle case difference in naming (e.g. Admin-portal vs admin-portal)
    if [ "$service_name" = "admin-portal" ] && [ -d "$PARENT_DIR/Admin-portal" ]; then
        sibling_dir="$PARENT_DIR/Admin-portal"
    elif [ "$service_name" = "frontend" ] && [ -d "$PARENT_DIR/Frontend" ]; then
        sibling_dir="$PARENT_DIR/Frontend"
    elif [ "$service_name" = "backend" ] && [ -d "$PARENT_DIR/Backend/Backend" ]; then
        sibling_dir="$PARENT_DIR/Backend/Backend"
    elif [ "$service_name" = "backend" ] && [ -d "$PARENT_DIR/Backend" ]; then
        sibling_dir="$PARENT_DIR/Backend"
    fi

    # If backend has a nested Backend folder containing the Dockerfile, link directly to it
    if [ "$service_name" = "backend" ] && [ -d "$sibling_dir/Backend" ] && [ -f "$sibling_dir/Backend/Dockerfile" ]; then
        sibling_dir="$sibling_dir/Backend"
    fi

    if [ -d "$target_dir" ] && { [ -f "$target_dir/Dockerfile" ] || [ -f "$target_dir/Dockerfile.prod" ]; }; then
        echo -e "${GREEN}[FOUND]${NC} Service $service_name already prepared in $target_dir."

        # Synchronize repository if it is a git worktree
        if [ "${SYNC_SERVICES:-true}" = "true" ] && git -C "$target_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            local current_branch
            current_branch=$(git -C "$target_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "$target_branch")
            if [ "$current_branch" = "HEAD" ] || [ -z "$current_branch" ]; then
                current_branch="$target_branch"
            fi
            local sync_branch="${!env_branch_var:-$current_branch}"

            echo -e "${BLUE}[SYNC]${NC} Checking remote updates for $service_name on branch '${CYAN}$sync_branch${NC}'..."
            git -C "$target_dir" fetch origin "$sync_branch" --tags 2>/dev/null || true

            # If working tree is clean, pull updates
            if git -C "$target_dir" diff --quiet 2>/dev/null && git -C "$target_dir" diff --cached --quiet 2>/dev/null; then
                git -C "$target_dir" checkout "$sync_branch" 2>/dev/null || true
                git -C "$target_dir" pull --ff-only origin "$sync_branch" 2>/dev/null || git -C "$target_dir" pull origin "$sync_branch" 2>/dev/null || true
                local latest_commit
                latest_commit=$(git -C "$target_dir" log -1 --format="%h - %s" 2>/dev/null || echo "")
                echo -e "    ${GREEN}[PULLED]${NC} $service_name is at: $latest_commit"
            else
                echo -e "    ${YELLOW}[INFO]${NC} Local uncommitted changes detected in $service_name. Skipping auto-pull to protect work."
            fi
        fi

    elif [ -d "$sibling_dir" ]; then
        echo -e "${GREEN}[LINK]${NC} Found local repository at $sibling_dir. Linking to $target_dir..."
        rm -rf "$target_dir"
        ln -s "$sibling_dir" "$target_dir"
    else
        echo -e "${YELLOW}[CLONE]${NC} Cloning $service_name from $repo_url (branch: $target_branch)..."
        git clone -b "$target_branch" "$repo_url" "$target_dir"
    fi

    # Special handling for Go Backend: if Backend has a nested Backend/ folder with Dockerfile
    if [ "$service_name" = "backend" ]; then
        if [ -f "$target_dir/Backend/Dockerfile" ]; then
            echo -e "${BLUE}[INFO]${NC} Detected nested Go structure in $target_dir/Backend."
        fi
    fi
}

prepare_service "frontend" "https://github.com/DextaAfrica/Frontend.git" "${FRONTEND_BRANCH:-develop}"
prepare_service "admin-portal" "https://github.com/DextaAfrica/Admin-portal.git" "${ADMIN_PORTAL_BRANCH:-develop}"
prepare_service "backend" "https://github.com/DextaAfrica/Backend.git" "${BACKEND_BRANCH:-main}"

echo -e "${GREEN}[SUCCESS]${NC} All service repositories are synchronized and ready for building."
