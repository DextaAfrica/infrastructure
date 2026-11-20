# ==============================================================================
# Dexta Africa Enterprise Production DevOps Command Engine
# High-End OCI Image Pull & Zero-Downtime Deployment Automation
# ==============================================================================

.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash

ENV_FILE := .env.prod
COMPOSE_PROD := docker compose -f docker-compose-prod.yml --env-file $(ENV_FILE)
COMPOSE_MAINT := docker compose -f docker-compose-prod.yml -f docker-compose-maintenance.yml --env-file $(ENV_FILE)

# Styling
CYAN := \033[0;36m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
RED := \033[0;31m
BOLD := \033[1m
NC := \033[0m

.PHONY: help
help: ## Show this formatted operational command reference
	@echo -e "\n$(CYAN)======================================================================$(NC)"
	@echo -e "$(CYAN)       Dexta Africa Enterprise Production Infrastructure CLI           $(NC)"
	@echo -e "$(CYAN)======================================================================$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(NC) %s\n", $$1, $$2}'
	@echo -e ""

# ------------------------------------------------------------------------------
# Core Deployment Lifecycle
# ------------------------------------------------------------------------------

.PHONY: deploy
deploy: ## Full automated production rollout with maintenance guard & health checks
	@$(MAKE) pull-infra
	@$(MAKE) maintenance-on
	@$(MAKE) pull-images
	@$(MAKE) run-migrations
	@$(MAKE) rollout-services
	@$(MAKE) wait-healthy
	@$(MAKE) maintenance-off
	@$(MAKE) prune-images
	@echo -e "$(GREEN)==> Deploy complete$(NC)"

.PHONY: pull-infra
pull-infra: ## Pull latest infrastructure configuration from Git
	@echo -e "$(BLUE)==> Pulling infra repository changes$(NC)"
	@if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then \
		git pull --ff-only || (git -C .. pull --ff-only 2>/dev/null || echo "Already up to date."); \
	else \
		echo "Skipping git pull (not a git working tree)."; \
	fi

.PHONY: maintenance-on
maintenance-on: ## Enable branded HTTP 503 maintenance gateway during deployments
	@echo -e "$(YELLOW)==> Enabling maintenance page$(NC)"
	@$(COMPOSE_MAINT) up -d --force-recreate maintenance

.PHONY: maintenance-off
maintenance-off: ## Disable and remove maintenance gateway
	@echo -e "$(BLUE)==> Disabling maintenance page$(NC)"
	@$(COMPOSE_MAINT) stop maintenance
	@$(COMPOSE_MAINT) rm -f maintenance

.PHONY: pull-images
pull-images: ## Pull latest verified OCI images from GitHub Container Registry
	@echo -e "$(BLUE)==> Pulling latest images$(NC)"
	@$(COMPOSE_PROD) pull api frontend admin

.PHONY: run-migrations
run-migrations: ## Execute one-shot database schema migrations
	@echo -e "$(BLUE)==> Running database migrations$(NC)"
	@$(COMPOSE_PROD) up migrate --exit-code-from migrate --abort-on-container-exit

.PHONY: rollout-services
rollout-services: ## Roll out updated containers (redis, api, frontend, admin)
	@echo -e "$(BLUE)==> Rolling out redis, api, frontend, admin$(NC)"
	@$(COMPOSE_PROD) up -d redis api frontend admin

.PHONY: wait-healthy
wait-healthy: ## Poll and verify all core services achieve healthy status (timeout 180s)
	@echo -e "$(BLUE)==> Waiting for api/frontend/admin to report healthy (timeout: 180s)$(NC)"
	@bash -c '\
		timeout=180; \
		elapsed=0; \
		services=("dexta_api" "dexta_frontend" "dexta_admin"); \
		while [ $$elapsed -lt $$timeout ]; do \
			all_healthy=true; \
			for s in "$${services[@]}"; do \
				status=$$(docker inspect --format="{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}" "$$s" 2>/dev/null || echo "missing"); \
				if [ "$$status" != "healthy" ] && [ "$$status" != "running" ]; then \
					all_healthy=false; \
					break; \
				fi; \
			done; \
			if [ "$$all_healthy" = true ]; then \
				echo -e "$(GREEN)==> All services healthy$(NC)"; \
				exit 0; \
			fi; \
			sleep 3; \
			elapsed=$$((elapsed + 3)); \
		done; \
		echo -e "$(RED)[ERROR] Timed out waiting for services to report healthy$(NC)"; \
		exit 1; \
	'

.PHONY: prune-images
prune-images: ## Remove old dangling and untagged images to reclaim disk space
	@echo -e "$(BLUE)==> Removing dangling images$(NC)"
	@docker image prune -f

# ------------------------------------------------------------------------------
# Monitoring & Operational Diagnostics
# ------------------------------------------------------------------------------

.PHONY: status
status: ## Display status of all production containers
	@echo -e "$(CYAN)Cluster Container Status:$(NC)"
	@$(COMPOSE_PROD) ps -a

.PHONY: logs
logs: ## Stream live logs across all containers (Ctrl+C to exit)
	@$(COMPOSE_PROD) logs -f --tail=100

.PHONY: logs-api
logs-api: ## Stream API logs
	@$(COMPOSE_PROD) logs -f --tail=100 api

.PHONY: logs-admin
logs-admin: ## Stream Admin Portal logs
	@$(COMPOSE_PROD) logs -f --tail=100 admin

.PHONY: logs-frontend
logs-frontend: ## Stream Frontend Web logs
	@$(COMPOSE_PROD) logs -f --tail=100 frontend

.PHONY: health
health: ## Run curl checks against API, Frontend, and Admin health endpoints
	@echo -e "$(CYAN)Health Probe Check:$(NC)"
	@curl -sS -o /dev/null -w "API (8080):       %{http_code}\n" http://127.0.0.1:8080/healthz || echo "API: DOWN"
	@curl -sS -o /dev/null -w "Frontend (3001):  %{http_code}\n" http://127.0.0.1:3001/api/health || echo "Frontend: DOWN"
	@curl -sS -o /dev/null -w "Admin (3000):     %{http_code}\n" http://127.0.0.1:3000/api/health || echo "Admin: DOWN"

.PHONY: rollback
rollback: ## Rollback images to a specific commit tag (Usage: make rollback tag=sha-xxxxxxx)
	@if [ -z "$(tag)" ]; then \
		echo -e "$(RED)Error: Please specify the target tag. Example: make rollback tag=sha-a1b2c3d$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(YELLOW)==> Rolling back to image tag $(tag)...$(NC)"
	@sed -i.bak -E 's/(API_IMAGE=.*:).*/\1$(tag)/; s/(FRONTEND_IMAGE=.*:).*/\1$(tag)/; s/(ADMIN_IMAGE=.*:).*/\1$(tag)/' $(ENV_FILE)
	@$(MAKE) deploy
