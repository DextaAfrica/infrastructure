#!/usr/bin/env bash
# ==============================================================================
# Dexta Africa Production Database Recovery Engine
# Restores PostgreSQL and Admin-Portal SQLite databases from backup archive
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$ROOT_DIR/backups/db"
ENV_FILE="$ROOT_DIR/.env"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ ! -f "$ENV_FILE" ]; then
    echo "Missing .env file in $ROOT_DIR"
    exit 1
fi

set -a
# shellcheck disable=SC1090,SC1091
source "$ENV_FILE"
set +a

BACKUP_ARCHIVE="${1:-}"

if [ -z "$BACKUP_ARCHIVE" ]; then
    echo -e "${YELLOW}Available backups in $BACKUP_DIR:${NC}"
    ls -lh "$BACKUP_DIR"/dexta_backup_*.tar.gz 2>/dev/null || echo "No backups found."
    echo -e "\nUsage: $0 <path-to-dexta_backup_*.tar.gz>"
    exit 1
fi

if [ ! -f "$BACKUP_ARCHIVE" ]; then
    echo -e "${RED}[ERROR]${NC} Backup archive not found: $BACKUP_ARCHIVE"
    exit 1
fi

echo -e "${RED}[WARNING]${NC} Restoring this backup will overwrite current PostgreSQL and Admin Portal data!"
read -p "Are you sure you want to proceed? (yes/no): " -r CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Restore cancelled."
    exit 0
fi

TEMP_RESTORE_DIR="/tmp/dexta_restore_$$"
mkdir -p "$TEMP_RESTORE_DIR"
tar -xzf "$BACKUP_ARCHIVE" -C "$TEMP_RESTORE_DIR"

DUMP_SUBDIR=$(find "$TEMP_RESTORE_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)

# 1. Restore PostgreSQL
if [ -f "$DUMP_SUBDIR/postgres.sql" ]; then
    echo -e "${BLUE}==>${NC} Restoring PostgreSQL database (${POSTGRES_DB:-dexta_prod})..."
    docker compose -f "$ROOT_DIR/docker-compose.yml" exec -T postgres \
      psql -U "${POSTGRES_USER:-dexta}" -d "${POSTGRES_DB:-dexta_prod}" < "$DUMP_SUBDIR/postgres.sql"
    echo -e "${GREEN}[OK]${NC} PostgreSQL database restored."
fi

# 2. Restore Admin SQLite
if [ -f "$DUMP_SUBDIR/admin_portal.db" ]; then
    echo -e "${BLUE}==>${NC} Restoring Admin Portal database..."
    docker compose -f "$ROOT_DIR/docker-compose.yml" cp "$DUMP_SUBDIR/admin_portal.db" admin-portal:/app/prisma/admin_portal.db
    echo -e "${GREEN}[OK]${NC} Admin Portal database restored."
fi

rm -rf "$TEMP_RESTORE_DIR"
echo -e "${GREEN}[SUCCESS]${NC} Database restoration finished successfully."
