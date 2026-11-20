#!/usr/bin/env bash
# ==============================================================================
# Dexta Africa Production Health Check Probe
# Waits up to 180s for api, frontend, and admin to achieve healthy status
# Dumps failing container diagnostics automatically if health check times out
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

TIMEOUT=180
ELAPSED=0
INTERVAL=3

COMPOSE="docker compose -f $ROOT_DIR/docker-compose-prod.yml --env-file $ROOT_DIR/.env.prod"

echo "Waiting for api/frontend/admin to report healthy (timeout: ${TIMEOUT}s)..."

while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    ALL_HEALTHY=true

    for svc in api frontend admin; do
        health=$($COMPOSE ps "$svc" --format '{{.Health}}' 2>/dev/null || echo "")
        status=$($COMPOSE ps "$svc" --format '{{.Status}}' 2>/dev/null || echo "")

        # If container exited unexpectedly, fail fast
        if [[ "$status" == *"Exited"* ]]; then
            echo -e "\n\033[0;31m[ERROR]\033[0m Container for $svc exited unexpectedly!"
            $COMPOSE logs --tail=30 "$svc"
            exit 1
        fi

        if [ "$health" != "healthy" ]; then
            ALL_HEALTHY=false
            break
        fi
    done

    if [ "$ALL_HEALTHY" = "true" ]; then
        echo "==> All services healthy"
        exit 0
    fi

    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
done

# If timeout reached, dump diagnostics
echo -e "\n\033[0;31m[TIMEOUT]\033[0m Services did not reach healthy state within ${TIMEOUT}s."
for svc in api frontend admin; do
    echo -e "\n--- Diagnostics for $svc ---"
    $COMPOSE logs --tail=25 "$svc" || true
done
exit 1
