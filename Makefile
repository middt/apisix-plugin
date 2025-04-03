# Makefile for APISIX Plugin Development Environment

# Default command: Show help
.DEFAULT_GOAL := help

# Docker Compose command
COMPOSE = docker-compose

# Start services in detached mode
up:
	@echo "Starting APISIX and etcd services..."
	@$(COMPOSE) up -d
	@echo "Services started. APISIX available at http://localhost:9080, Dashboard at http://localhost:9000"

# Stop services
down:
	@echo "Stopping services..."
	@$(COMPOSE) down
	@echo "Services stopped."

# Stop and remove volumes (clean start)
clean:
	@echo "Stopping services and removing volumes..."
	@$(COMPOSE) down -v
	@echo "Environment cleaned."

# View logs for APISIX
logs-apisix:
	@echo "Tailing APISIX logs (Ctrl+C to stop)..."
	@$(COMPOSE) logs -f apisix

# View logs for etcd
logs-etcd:
	@echo "Tailing etcd logs (Ctrl+C to stop)..."
	@$(COMPOSE) logs -f etcd

# Reload APISIX (useful after changing plugin code)
reload:
	@echo "Reloading APISIX configuration..."
	@$(COMPOSE) exec apisix apisix reload
	@echo "APISIX reloaded."

# Enter APISIX container shell
shell-apisix:
	@echo "Entering APISIX container shell..."
	@$(COMPOSE) exec apisix /bin/bash

# Show help message
help:
	@echo "APISIX Plugin Development Environment Commands:"
	@echo "  make up          - Start services (APISIX, etcd)"
	@echo "  make down        - Stop services"
	@echo "  make clean       - Stop services and remove data volumes"
	@echo "  make logs-apisix - View APISIX logs"
	@echo "  make logs-etcd   - View etcd logs"
	@echo "  make reload      - Reload APISIX configuration (after plugin code changes)"
	@echo "  make shell-apisix- Enter the APISIX container's shell"

.PHONY: up down clean logs-apisix logs-etcd reload shell-apisix help 