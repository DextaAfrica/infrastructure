# ==============================================================================
# Dexta Africa Enterprise Production DevOps Command Center
# ==============================================================================

.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash

COMPOSE_FILE := docker-compose.yml
COMPOSE_DEV_FILE := docker-compose.dev.yml
COMPOSE := docker compose -f $(COMPOSE_FILE)
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
# Core Deployment & Lifecycle Targets
# ------------------------------------------------------------------------------

.PHONY: setup
setup: ## Initialize directories, .env template, and service repositories
	@echo -e "$(BLUE)==>$(NC) Running infrastructure setup..."
	@if [ ! -f .env ]; then cp .env.example .env && echo -e "$(GREEN)[OK]$(NC) Created .env from .env.example (please edit with secrets)"; fi
	@mkdir -p backups/db docker/nginx/ssl docker/nginx/maintenance services
	@./scripts/setup-services.sh

.PHONY: deploy
deploy: ## Full production cluster deployment (build, migrate, SSL, start)
	@./scripts/deploy.sh

.PHONY: update
update: ## Rolling zero/minimal-downtime update (pull git, build, migrate, reload)
	@./scripts/update.sh

.PHONY: start
start: ## Start all production containers in the background and verify health
	@echo -e "$(BLUE)==>$(NC) Starting Dexta Africa cluster services..."
	@$(COMPOSE) up -d
	@echo -e "$(GREEN)[OK]$(NC) All services launched. Run 'make status' to verify health."

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

# ------------------------------------------------------------------------------
# Telemetry, Monitoring & Diagnostics
# ------------------------------------------------------------------------------

.PHONY: status
status: ## Display detailed status, container health, ports, and resource usage
	@echo -e "\n$(CYAN)--- Cluster Container Health ---$(NC)"
	@$(COMPOSE) ps
	@echo -e "\n$(CYAN)--- Resource Telemetry ---$(NC)"
	@docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" $$(docker compose -f $(COMPOSE_FILE) ps -q) 2>/dev/null || true
	@echo -e "\n$(CYAN)--- Maintenance Mode Status ---$(NC)"
	@./scripts/maintenance.sh status

.PHONY: logs
logs: ## Stream unified cluster logs (Usage: make logs or make logs service=backend)
	@if [ -n "$(service)" ]; then \
		$(COMPOSE) logs -f --tail=100 $(service); \
	else \
		$(COMPOSE) logs -f --tail=50; \
	fi

# ------------------------------------------------------------------------------
# Maintenance Mode Controls
# ------------------------------------------------------------------------------

.PHONY: maintenance-on
maintenance-on: ## Activate branded maintenance page on edge routers (returns HTTP 503)
	@./scripts/maintenance.sh on

.PHONY: maintenance-off
maintenance-off: ## Deactivate maintenance page and restore normal live traffic
	@./scripts/maintenance.sh off

.PHONY: maintenance-status
maintenance-status: ## Check current maintenance mode state
	@./scripts/maintenance.sh status

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
# Security & SSL
# ------------------------------------------------------------------------------

.PHONY: ssl
ssl: ## Provision or renew Let's Encrypt SSL certificates via Certbot
	@./scripts/init-ssl.sh

# ------------------------------------------------------------------------------
# Maintenance, Cleanup & Dev
# ------------------------------------------------------------------------------

.PHONY: prune
prune: ## Safely remove unused Docker build caches, dangling images, and stopped containers
	@echo -e "$(YELLOW)==>$(NC) Cleaning up unused Docker resources..."
	@docker image prune -f
	@docker builder prune -f --keep-storage 5GB
	@echo -e "$(GREEN)[OK]$(NC) Cleanup complete."

.PHONY: dev
dev: ## Run local development cluster with hot reloading
	@echo -e "$(BLUE)==>$(NC) Launching local development environment..."
	@$(COMPOSE_DEV) up --build

.PHONY: dev-down
dev-down: ## Stop local development environment
	@$(COMPOSE_DEV) down
