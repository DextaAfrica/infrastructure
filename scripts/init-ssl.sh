#!/usr/bin/env bash
# ==============================================================================
# Dexta Africa Traefik ACME SSL Initializer
# Prepares acme.json with strict 600 permissions required by Traefik
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ACME_DIR="$ROOT_DIR/docker/traefik/acme"
ACME_FILE="$ACME_DIR/acme.json"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}==>${NC} Initializing Traefik ACME Let's Encrypt vault..."

mkdir -p "$ACME_DIR"
if [ ! -f "$ACME_FILE" ]; then
    touch "$ACME_FILE"
fi

chmod 600 "$ACME_FILE"

echo -e "${GREEN}[OK]${NC} Traefik acme.json ready with strict 600 permissions."
