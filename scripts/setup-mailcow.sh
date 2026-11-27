#!/usr/bin/env bash
# ==============================================================================
# Dexta Africa Enterprise Infrastructure - Mailcow Dockerized Installer
# Integrates Mailcow with host shared_traefik on external network: traefik-public
# ==============================================================================
set -euo pipefail

MAILCOW_DIR="${HOME}/apps/mailcow"
MAILCOW_HOSTNAME="mail.dextaafrica.com"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "\n${CYAN}======================================================================${NC}"
echo -e "${CYAN}      Dexta Africa - Mailcow Dockerized Setup & Traefik Bridge         ${NC}"
echo -e "${CYAN}======================================================================${NC}\n"

# 1. Verify Docker & Compose
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] Docker is not installed or not in PATH.${NC}"
    exit 1
fi

# 2. Verify traefik-public network exists
if ! docker network inspect traefik-public >/dev/null 2>&1; then
    echo -e "${YELLOW}==>${NC} Creating external network: traefik-public"
    docker network create traefik-public
fi

# 3. Clone or update Mailcow repository
if [ ! -d "$MAILCOW_DIR" ]; then
    echo -e "${GREEN}==>${NC} Cloning mailcow-dockerized into $MAILCOW_DIR..."
    git clone https://github.com/mailcow/mailcow-dockerized.git "$MAILCOW_DIR"
else
    echo -e "${GREEN}==>${NC} Mailcow repository already exists at $MAILCOW_DIR."
fi

cd "$MAILCOW_DIR"

# 4. Generate mailcow.conf if missing
if [ ! -f "mailcow.conf" ]; then
    echo -e "${GREEN}==>${NC} Generating initial mailcow.conf..."
    # Generate config non-interactively
    ./generate_config.sh <<EOF
$MAILCOW_HOSTNAME
UTC
EOF
fi

# 5. Patch mailcow.conf for Traefik reverse proxy integration (Zero Port Collisions)
echo -e "${GREEN}==>${NC} Patching mailcow.conf for Traefik reverse proxy..."
sed -i.bak \
    -e 's|^HTTP_PORT=.*|HTTP_PORT=8080|' \
    -e 's|^HTTP_BIND=.*|HTTP_BIND=127.0.0.1|' \
    -e 's|^HTTPS_PORT=.*|HTTPS_PORT=8443|' \
    -e 's|^HTTPS_BIND=.*|HTTPS_BIND=127.0.0.1|' \
    -e 's|^SKIP_LETS_ENCRYPT=.*|SKIP_LETS_ENCRYPT=y|' \
    mailcow.conf

# Check memory constraint and optionally disable ClamAV if RAM < 8GB
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "8000000")
if [ "$TOTAL_RAM_KB" -lt 7000000 ]; then
    echo -e "${YELLOW}==>${NC} System RAM is under 7GB. Disabling ClamAV to optimize memory footprint..."
    sed -i -e 's|^SKIP_CLAMD=.*|SKIP_CLAMD=y|' mailcow.conf
fi

# 6. Apply docker-compose.override.yml
echo -e "${GREEN}==>${NC} Applying Traefik override configuration..."
cp "$INFRA_DIR/docker/mailcow/docker-compose.override.yml" "$MAILCOW_DIR/docker-compose.override.yml"

echo -e "\n${GREEN}[OK]${NC} Mailcow configuration is ready."
echo -e "\nNext steps to launch:"
echo -e "  cd $MAILCOW_DIR"
echo -e "  docker compose pull"
echo -e "  docker compose up -d"
echo -e "\nOnce running, access your webmail at: ${CYAN}https://$MAILCOW_HOSTNAME${NC}"
echo -e "Default login: ${YELLOW}admin${NC} / Password: ${YELLOW}moohoo${NC} (Change immediately upon first login)\n"
