#!/usr/bin/env bash
# ==============================================================================
# Dexta Africa Automated Let's Encrypt SSL Provisioning Script
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "Missing .env file in $ROOT_DIR"
    exit 1
fi

# Load environment
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

DOMAIN="${DOMAIN:-dextaafrica.com}"
WWW_DOMAIN="${WWW_DOMAIN:-www.dextaafrica.com}"
ADMIN_DOMAIN="${ADMIN_DOMAIN:-admin.dextaafrica.com}"
OPS_DOMAIN="${OPS_DOMAIN:-ops.dextaafrica.com}"
API_DOMAIN="${API_DOMAIN:-api.dextaafrica.com}"
SSL_EMAIL="${SSL_EMAIL:-devops@dextaafrica.com}"

CERT_PATH="/etc/letsencrypt/live/$DOMAIN"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}==>${NC} Verifying SSL certificate status for $DOMAIN..."

# Check if certificates already exist in Docker volume
CERT_EXISTS=$(docker compose -f "$ROOT_DIR/docker-compose.yml" run --rm --entrypoint test certbot -f "$CERT_PATH/fullchain.pem" && echo "yes" || echo "no")

if [ "$CERT_EXISTS" = "yes" ]; then
    echo -e "${GREEN}[OK]${NC} Valid certificate already present for $DOMAIN."
    exit 0
fi

echo -e "${YELLOW}[NOTICE]${NC} No existing certificates found. Creating bootstrap self-signed certificates..."

# Generate bootstrap dummy certs inside volume so Nginx can start
docker compose -f "$ROOT_DIR/docker-compose.yml" run --rm --entrypoint "\
  sh -c '\
    mkdir -p /etc/letsencrypt/live/$DOMAIN && \
    openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
      -keyout /etc/letsencrypt/live/$DOMAIN/privkey.pem \
      -out /etc/letsencrypt/live/$DOMAIN/fullchain.pem \
      -subj \"/CN=localhost\" \
  '" certbot

echo -e "${BLUE}==>${NC} Starting edge reverse proxy with bootstrap certificates..."
docker compose -f "$ROOT_DIR/docker-compose.yml" up -d reverse-proxy

echo -e "${BLUE}==>${NC} Removing bootstrap certificates and requesting official Let's Encrypt certificates..."
docker compose -f "$ROOT_DIR/docker-compose.yml" run --rm --entrypoint "\
  rm -rf /etc/letsencrypt/live/$DOMAIN && \
  rm -rf /etc/letsencrypt/archive/$DOMAIN && \
  rm -rf /etc/letsencrypt/renewal/$DOMAIN.conf \
" certbot

# Run Certbot ACME challenge
DOMAINS_ARGS="-d $DOMAIN -d $WWW_DOMAIN -d $ADMIN_DOMAIN -d $OPS_DOMAIN -d $API_DOMAIN"

echo -e "${BLUE}==>${NC} Requesting Let's Encrypt certificate for:${NC} $DOMAINS_ARGS"
if docker compose -f "$ROOT_DIR/docker-compose.yml" run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    --email $SSL_EMAIL \
    $DOMAINS_ARGS \
    --rsa-key-size 4096 \
    --agree-tos \
    --force-renewal \
    --non-interactive \
" certbot; then
    echo -e "${GREEN}[SUCCESS]${NC} Let's Encrypt SSL certificates successfully generated!"
    echo -e "${BLUE}==>${NC} Reloading Nginx configuration..."
    docker compose -f "$ROOT_DIR/docker-compose.yml" exec reverse-proxy nginx -s reload
else
    echo -e "${YELLOW}[WARNING]${NC} Let's Encrypt certificate issuance failed (DNS records may not yet point to this server)."
    echo -e "          Restoring temporary self-signed certificates so the site remains accessible..."
    docker compose -f "$ROOT_DIR/docker-compose.yml" run --rm --entrypoint "\
      sh -c '\
        mkdir -p /etc/letsencrypt/live/$DOMAIN && \
        openssl req -x509 -nodes -newkey rsa:2048 -days 30 \
          -keyout /etc/letsencrypt/live/$DOMAIN/privkey.pem \
          -out /etc/letsencrypt/live/$DOMAIN/fullchain.pem \
          -subj \"/CN=$DOMAIN\" \
      '" certbot
    docker compose -f "$ROOT_DIR/docker-compose.yml" exec reverse-proxy nginx -s reload
fi
