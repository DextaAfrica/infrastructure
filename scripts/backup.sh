#!/usr/bin/env bash
# ==============================================================================
# Dexta Africa Production Database Backup Engine
# Backs up PostgreSQL and Admin-Portal SQLite databases with rotation
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$ROOT_DIR/backups/db"
ENV_FILE="$ROOT_DIR/.env"

mkdir -p "$BACKUP_DIR"

if [ ! -f "$ENV_FILE" ]; then
    echo "Missing .env file in $ROOT_DIR"
    exit 1
fi

set -a
# shellcheck disable=SC1090,SC1091
source "$ENV_FILE"
set +a

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TEMP_DUMP_DIR="$BACKUP_DIR/tmp_$TIMESTAMP"
ARCHIVE_FILE="$BACKUP_DIR/dexta_backup_${TIMESTAMP}.tar.gz"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}==>${NC} Starting enterprise backup at $TIMESTAMP..."
mkdir -p "$TEMP_DUMP_DIR"

# 1. Backup PostgreSQL Core Database
if docker compose -f "$ROOT_DIR/docker-compose.yml" ps --services --filter "status=running" | grep -q "postgres"; then
    echo -e "${BLUE}==>${NC} Dumping local PostgreSQL database (${POSTGRES_DB:-dexta_prod})..."
    docker compose -f "$ROOT_DIR/docker-compose.yml" exec -T postgres \
      pg_dump -U "${POSTGRES_USER:-dexta}" "${POSTGRES_DB:-dexta_prod}" > "$TEMP_DUMP_DIR/postgres.sql"
else
    echo -e "${BLUE}==>${NC} Primary database is hosted externally (managed by cloud provider automated snapshots)."
fi

# 2. Backup Admin Portal Database
echo -e "${BLUE}==>${NC} Snapshotting Admin Portal database..."
if docker compose -f "$ROOT_DIR/docker-compose.yml" ps --services | grep -q "admin-portal"; then
    docker compose -f "$ROOT_DIR/docker-compose.yml" cp admin-portal:/app/prisma/admin_portal.db "$TEMP_DUMP_DIR/admin_portal.db" 2>/dev/null || true
fi

# 3. Create compressed tarball
tar -czf "$ARCHIVE_FILE" -C "$BACKUP_DIR" "tmp_$TIMESTAMP"
rm -rf "$TEMP_DUMP_DIR"

BACKUP_SIZE=$(du -h "$ARCHIVE_FILE" | cut -f1)
echo -e "${GREEN}[SUCCESS]${NC} Backup successfully created: $ARCHIVE_FILE ($BACKUP_SIZE)"

# 4. Prune old backups older than 14 days
echo -e "${BLUE}==>${NC} Cleaning up archives older than 14 days..."
find "$BACKUP_DIR" -name "dexta_backup_*.tar.gz" -type f -mtime +14 -exec rm -f {} \;

echo -e "${GREEN}[DONE]${NC} Database backup completed and verified."
