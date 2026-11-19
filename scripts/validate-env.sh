#!/usr/bin/env bash
# ==============================================================================
# Dexta Africa Production Preflight Environment Validator
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT_DIR/.env"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}==>${NC} Validating deployment environment..."

if [ ! -f "$ENV_FILE" ]; then
    if [ -f "$ROOT_DIR/.env-prod" ]; then
        echo -e "${BLUE}[INFO]${NC} Found .env-prod, syncing to .env..."
        cp "$ROOT_DIR/.env-prod" "$ENV_FILE"
    else
        echo -e "${RED}[ERROR]${NC} Missing .env file in $ROOT_DIR!"
        echo -e "       Copy template: cp .env.example .env"
        echo -e "       Configure required secrets before running make deploy."
        exit 1
    fi
fi

# Load variables
set -a
# shellcheck disable=SC1090,SC1091
source "$ENV_FILE"
set +a

ERRORS=0

validate_required() {
    local var_name="$1"
    local value="${!var_name:-}"

    if [ -z "$value" ]; then
        echo -e "${RED}[MISSING]${NC} Variable ${var_name} must be set in .env."
        ERRORS=$((ERRORS + 1))
    elif [[ "$value" == *"replace_with"* ]] || [[ "$value" == *"change-me"* ]]; then
        echo -e "${RED}[INSECURE]${NC} Variable ${var_name} contains placeholder '${value}'! Must be set to a real secure production secret."
        ERRORS=$((ERRORS + 1))
    fi
}

validate_required "DOMAIN"
if [ -n "${DATABASE_URL:-}" ] && [[ "${DATABASE_URL:-}" != *"localhost"* ]] && [[ "${DATABASE_URL:-}" != *"postgres:5432"* ]]; then
    validate_required "DATABASE_URL"
else
    validate_required "POSTGRES_PASSWORD"
fi
validate_required "REDIS_PASSWORD"
validate_required "JWT_SECRET"
validate_required "FRONTEND_REVALIDATE_SECRET"
validate_required "ADMIN_APP_SECRET"

if [ $ERRORS -gt 0 ]; then
    echo -e "\n${RED}[FAILED]${NC} Environment validation failed with ${ERRORS} error(s)."
    echo -e "         Please update your .env file with valid production secrets."
    exit 1
fi

echo -e "${GREEN}[OK]${NC} Environment validation successful. All critical keys are present and configured."
