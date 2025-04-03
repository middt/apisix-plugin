# Makefile for APISIX Plugin Development Environment

# Default command: Show help
.DEFAULT_GOAL := help

# Docker Compose command
COMPOSE = docker compose

# Start services in detached mode
up:
	@echo "Starting APISIX, etcd, Dashboard, and Redpanda services..."
	@$(COMPOSE) up -d
	@echo "Services started:"
	@echo "  - APISIX Proxy: http://localhost:9080"
	@echo "  - APISIX Admin API: http://localhost:9180"
	@echo "  - APISIX Dashboard: http://localhost:9000"

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

# View logs for APISIX Dashboard
logs-dashboard:
	@echo "Tailing APISIX Dashboard logs (Ctrl+C to stop)..."
	@$(COMPOSE) logs -f apisix-dashboard

# View logs for Redpanda
logs-redpanda:
	@echo "Tailing Redpanda logs (Ctrl+C to stop)..."
	@$(COMPOSE) logs -f redpanda

# Reload APISIX (useful after changing plugin code)
reload:
	@echo "Reloading APISIX configuration..."
	@$(COMPOSE) exec apisix apisix reload
	@echo "APISIX reloaded."

# Enter APISIX container shell
shell-apisix:
	@echo "Entering APISIX container shell..."
	@$(COMPOSE) exec apisix /bin/bash

# Enter Dashboard container shell
shell-dashboard:
	@echo "Entering APISIX Dashboard container shell..."
	@$(COMPOSE) exec apisix-dashboard /bin/bash

# Create the API route with path rewriting
create-route:
	@echo "Creating API route with path rewriting..."
	@curl -i -X PUT "http://localhost:9180/apisix/admin/routes/3" \
		-H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" \
		-H "Content-Type: application/json" \
		-d '{
			"uri": "/api/get",
			"plugins": {
				"hello-world": {
					"message": "Hello from rewritten path!"
				},
				"proxy-rewrite": {
					"uri": "/get"
				}
			},
			"upstream": {
				"type": "roundrobin",
				"nodes": {
					"httpbin.org:80": 1
				}
			}
		}'

# Test the API route with path rewriting
test-api:
	@echo "Testing API route with path rewriting..."
	@curl -i http://localhost:9080/api/get

# Create route and test it in one command
setup-and-test: create-route test-api

# Show help message
help:
	@echo "APISIX Plugin Development Environment Commands:"
	@echo "  make up             - Start all services"
	@echo "  make down           - Stop services"
	@echo "  make clean          - Stop services and remove data volumes"
	@echo "  make logs-apisix    - View APISIX logs"
	@echo "  make logs-etcd      - View etcd logs"
	@echo "  make logs-dashboard - View APISIX Dashboard logs"
	@echo "  make logs-redpanda  - View Redpanda logs"
	@echo "  make reload         - Reload APISIX configuration (after plugin code changes)"
	@echo "  make shell-apisix   - Enter the APISIX container's shell"
	@echo "  make shell-dashboard- Enter the Dashboard container's shell"
	@echo "  make create-route   - Create the API route with path rewriting"
	@echo "  make test-api       - Test the API route with path rewriting"
	@echo "  make setup-and-test - Create route and test it in one command"

.PHONY: up down clean logs-apisix logs-etcd logs-dashboard logs-redpanda reload shell-apisix shell-dashboard create-route test-api setup-and-test help 