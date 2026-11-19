#!/usr/bin/env bash
# ==============================================================================
# Dexta Africa Service Discovery & Preparation Script
# Resolves or clones Frontend, Admin-portal, and Backend codebases
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
SERVICES_DIR="$ROOT_DIR/services"
PARENT_DIR="$(dirname "$ROOT_DIR")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$SERVICES_DIR"

echo -e "${BLUE}==>${NC} Discovering and syncing application repositories..."

# Function to link or clone service
prepare_service() {
    local service_name="$1"
    local repo_url="$2"
    local default_branch="${3:-main}"
    local target_dir="$SERVICES_DIR/$service_name"
    local sibling_dir="$PARENT_DIR/$service_name"

    # Handle case difference in naming (e.g. Admin-portal vs admin-portal)
    if [ ! -d "$sibling_dir" ]; then
        if [ "$service_name" = "admin-portal" ] && [ -d "$PARENT_DIR/Admin-portal" ]; then
            sibling_dir="$PARENT_DIR/Admin-portal"
        elif [ "$service_name" = "frontend" ] && [ -d "$PARENT_DIR/Frontend" ]; then
            sibling_dir="$PARENT_DIR/Frontend"
        elif [ "$service_name" = "backend" ] && [ -d "$PARENT_DIR/Backend" ]; then
            sibling_dir="$PARENT_DIR/Backend"
        fi
    fi

    if [ -d "$target_dir" ] && [ -f "$target_dir/Dockerfile" -o -f "$target_dir/Dockerfile.prod" ]; then
        echo -e "${GREEN}[FOUND]${NC} Service $service_name already prepared in $target_dir."
    elif [ -d "$sibling_dir" ]; then
        echo -e "${GREEN}[LINK]${NC} Found local repository at $sibling_dir. Linking to $target_dir..."
        rm -rf "$target_dir"
        ln -s "$sibling_dir" "$target_dir"
    else
        echo -e "${YELLOW}[CLONE]${NC} Cloning $service_name from $repo_url (branch: $default_branch)..."
        git clone -b "$default_branch" "$repo_url" "$target_dir"
    fi

    # Special handling for Go Backend: if Backend has a nested Backend/ folder with Dockerfile
    if [ "$service_name" = "backend" ]; then
        if [ -f "$target_dir/Backend/Dockerfile" ]; then
            echo -e "${BLUE}[INFO]${NC} Detected nested Go structure in $target_dir/Backend."
        fi
    fi
}

prepare_service "frontend" "https://github.com/DextaAfrica/Frontend.git" "main"
prepare_service "admin-portal" "https://github.com/DextaAfrica/Admin-portal.git" "main"
prepare_service "backend" "https://github.com/DextaAfrica/Backend.git" "develop"

echo -e "${GREEN}[SUCCESS]${NC} All service repositories are ready for building."
