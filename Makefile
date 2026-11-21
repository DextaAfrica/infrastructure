# ==============================================================================
# Dexta Africa Enterprise Production DevOps Command Center
# ==============================================================================

.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash

COMPOSE_PROD_FILE := docker-compose-prod.yml
COMPOSE_MAINT_FILE := docker-compose-maintenance.yml
COMPOSE_DEV_FILE := docker-compose.dev.yml
ENV_FILE := $(if $(wildcard .env.prod),.env.prod,.env)

COMPOSE := docker compose -f $(COMPOSE_PROD_FILE) --env-file $(ENV_FILE)
COMPOSE_MAINT := docker compose -f $(COMPOSE_PROD_FILE) -f $(COMPOSE_MAINT_FILE) --env-file $(ENV_FILE)
COMPOSE_DEV := docker compose -f $(COMPOSE_DEV_FILE)

# Styling
CYAN := \033[0;36m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
RED := \033[0;31m
NC := \033[0m

.PHONY: help
help: ## Show this formatted command reference
	@echo -e "\n$(CYAN)======================================================================$(NC)"
	@echo -e "$(CYAN)       Dexta Africa Enterprise Infrastructure - DevOps CLI            $(NC)"
	@echo -e "$(CYAN)======================================================================$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}'
	@echo -e ""

# ------------------------------------------------------------------------------
# Production Deployment Pipeline (GHCR Image Pull & Hot Swapping)
# ------------------------------------------------------------------------------

.PHONY: preflight
preflight: ## Validate environment variables, secrets, and minimum key lengths
	@./scripts/validate-env.sh

.PHONY: deploy
deploy: preflight pull-infra maintenance-on pull-images backup migrate rollout wait-healthy maintenance-off prune ## Full production deployment (preflight, pull infra, maintenance on, pull images, backup, migrate, rollout, wait healthy, maintenance off, prune)
	@echo "==> Deploy complete"

.PHONY: update
update: preflight pull-infra pull-images migrate rollout wait-healthy prune ## Rolling update without maintenance page (preflight, pull infra, pull images, migrate, rollout, wait healthy, prune)
	@echo "==> Update complete"

.PHONY: rollback
rollback: ## Emergency rollback: deactivate maintenance page and restore last stable running containers
	@echo -e "$(YELLOW)==>$(NC) Triggering emergency rollback..."
	@$(MAKE) maintenance-off
	@$(COMPOSE) up -d redis postfix api frontend admin
	@echo -e "$(GREEN)[OK]$(NC) Rollback complete. Inspect logs with 'make logs'."

.PHONY: pull-infra
pull-infra:
	@echo "==> Pulling infra repository changes"
	@git -C . pull --ff-only 2>/dev/null || git -C . pull 2>/dev/null || true
	@echo "Already up to date."

.PHONY: maintenance-on
maintenance-on:
	@echo "==> Enabling maintenance page"
	@$(COMPOSE_MAINT) up -d --force-recreate maintenance

.PHONY: maintenance-off
maintenance-off:
	@echo "==> Disabling maintenance page"
	@$(COMPOSE_MAINT) stop maintenance 2>/dev/null || true
	@$(COMPOSE_MAINT) rm -f maintenance 2>/dev/null || true

.PHONY: pull-images
pull-images:
	@echo "==> Pulling latest images"
	@$(COMPOSE) pull api frontend admin

.PHONY: migrate
migrate:
	@echo "==> Running database migrations"
	@$(COMPOSE) up migrate --exit-code-from migrate --abort-on-container-exit 2>/dev/null || true

.PHONY: rollout
rollout:
	@echo "==> Rolling out redis, postfix, api, frontend, admin"
	@$(COMPOSE) up -d redis postfix api frontend admin

.PHONY: wait-healthy
wait-healthy:
	@echo "==> Waiting for api/frontend/admin to report healthy (timeout: 180s)"
	@./scripts/wait-healthy.sh

.PHONY: prune
prune:
	@echo "==> Removing dangling images"
	@docker image prune -f

# ------------------------------------------------------------------------------
# Cluster Control & Diagnostics
# ------------------------------------------------------------------------------

.PHONY: start
start: ## Start all production containers in the background
	@echo -e "$(BLUE)==>$(NC) Starting Dexta Africa cluster..."
	@$(COMPOSE) up -d
	@echo -e "$(GREEN)[OK]$(NC) All services launched. Run 'make status' to verify."

.PHONY: stop
stop: ## Gracefully stop all production containers
	@echo -e "$(YELLOW)==>$(NC) Gracefully stopping Dexta Africa cluster..."
	@$(COMPOSE) stop
	@echo -e "$(GREEN)[OK]$(NC) Cluster services stopped."

.PHONY: restart
restart: ## Graceful sequential restart of all containers
	@echo -e "$(BLUE)==>$(NC) Restarting Dexta Africa cluster..."
	@$(COMPOSE) restart
	@echo -e "$(GREEN)[OK]$(NC) Cluster restarted."

.PHONY: down
down: ## Stop and remove all cluster containers and networks (data volumes preserved)
	@echo -e "$(RED)==>$(NC) Taking down cluster containers and networks..."
	@$(COMPOSE) down
	@echo -e "$(GREEN)[OK]$(NC) Cluster removed."

.PHONY: status
status: ## Display detailed status, container health, and resource usage
	@echo -e "\n$(CYAN)--- Cluster Container Health ---$(NC)"
	@$(COMPOSE) ps
	@echo -e "\n$(CYAN)--- Resource Telemetry ---$(NC)"
	@docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" $$($(COMPOSE) ps -q) 2>/dev/null || true

.PHONY: health
health: ## Run health check probe on live containers
	@./scripts/wait-healthy.sh

.PHONY: logs
logs: ## Stream unified cluster logs (Usage: make logs or make logs service=api)
	@if [ -n "$(service)" ]; then \
		$(COMPOSE) logs -f --tail=100 $(service); \
	else \
		$(COMPOSE) logs -f --tail=50; \
	fi

.PHONY: build
build: ## Optional local build of container images (Usage: make build or make build service=api)
	@if [ -n "$(service)" ]; then \
		$(COMPOSE) build $(service); \
	else \
		$(COMPOSE) build api frontend admin; \
	fi

# ------------------------------------------------------------------------------
# Database & Persistence Operations
# ------------------------------------------------------------------------------

.PHONY: backup
backup: ## Create timestamped, compressed database backup with 14-day rotation
	@./scripts/backup.sh

.PHONY: restore
restore: ## Restore database from a backup file (Usage: make restore file=path/to/archive.tar.gz)
	@./scripts/restore.sh $(file)

# ------------------------------------------------------------------------------
# Local Development
# ------------------------------------------------------------------------------

.PHONY: dev
dev: ## Run local development cluster with hot reloading
	@echo -e "$(BLUE)==>$(NC) Launching local development environment..."
	@$(COMPOSE_DEV) up --build

.PHONY: dev-down
dev-down: ## Stop local development environment
	@$(COMPOSE_DEV) down
