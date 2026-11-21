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

if [ -f "$ROOT_DIR/.env.prod" ]; then
    ENV_FILE="$ROOT_DIR/.env.prod"
    [ ! -f "$ROOT_DIR/.env" ] && cp "$ROOT_DIR/.env.prod" "$ROOT_DIR/.env"
elif [ -f "$ROOT_DIR/.env-prod" ]; then
    ENV_FILE="$ROOT_DIR/.env-prod"
    [ ! -f "$ROOT_DIR/.env" ] && cp "$ROOT_DIR/.env-prod" "$ROOT_DIR/.env"
    [ ! -f "$ROOT_DIR/.env.prod" ] && cp "$ROOT_DIR/.env-prod" "$ROOT_DIR/.env.prod"
elif [ -f "$ROOT_DIR/.env" ]; then
    ENV_FILE="$ROOT_DIR/.env"
    [ ! -f "$ROOT_DIR/.env.prod" ] && cp "$ROOT_DIR/.env" "$ROOT_DIR/.env.prod"
else
    echo -e "${RED}[ERROR]${NC} Missing environment file (.env.prod or .env) in $ROOT_DIR!"
    echo -e "       Create from template: cp .env.example .env.prod"
    echo -e "       Configure required secrets before running make deploy."
    exit 1
fi

# Load variables
set -a
# shellcheck disable=SC1090,SC1091
source "$ENV_FILE"
set +a

ERRORS=0

validate_required() {
    local var_name="$1"
    local min_length="${2:-0}"
    local value="${!var_name:-}"

    if [ -z "$value" ]; then
        echo -e "${RED}[MISSING]${NC} Variable ${var_name} must be set in .env."
        ERRORS=$((ERRORS + 1))
    elif [[ "$value" == *"replace_with"* ]] || [[ "$value" == *"change-me"* ]]; then
        echo -e "${RED}[INSECURE]${NC} Variable ${var_name} contains placeholder '${value}'! Must be set to a real secure production secret."
        ERRORS=$((ERRORS + 1))
    elif [ "$min_length" -gt 0 ] && [ "${#value}" -lt "$min_length" ]; then
        echo -e "${RED}[WEAK]${NC} Variable ${var_name} length (${#value}) is below minimum ${min_length} chars required for cryptographic security."
        ERRORS=$((ERRORS + 1))
    fi
}

validate_required "DOMAIN"
if [ -n "${DATABASE_URL:-}" ] && [[ "${DATABASE_URL:-}" != *"localhost"* ]] && [[ "${DATABASE_URL:-}" != *"postgres:5432"* ]]; then
    validate_required "DATABASE_URL"
else
    validate_required "POSTGRES_PASSWORD" 16
fi
validate_required "REDIS_PASSWORD" 16
validate_required "JWT_SECRET" 32
validate_required "FRONTEND_REVALIDATE_SECRET" 16
validate_required "ADMIN_APP_SECRET" 32

if [ $ERRORS -gt 0 ]; then
    echo -e "\n${RED}[FAILED]${NC} Environment validation failed with ${ERRORS} error(s)."
    echo -e "         Please update your .env file with valid production secrets."
    exit 1
fi

echo -e "${GREEN}[OK]${NC} Environment validation successful. All critical keys and rate limits are configured."
