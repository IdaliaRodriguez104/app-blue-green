# Makefile — Operational commands for Blue/Green deployment
# Usage: make <target>

COMPOSE_DIR    := $(shell pwd)
UPSTREAM_CONF  := $(COMPOSE_DIR)/nginx/conf.d/upstream.conf
NGINX_CONTAINER := nginx-proxy

.PHONY: help up down status switch-blue switch-green health-blue health-green logs-blue logs-green logs-nginx

help:
	@echo "Blue/Green Deployment — Available commands:"
	@echo ""
	@echo "  make up            Start all containers"
	@echo "  make down          Stop all containers"
	@echo "  make status        Show container status + active environment"
	@echo "  make switch-blue   Manually switch traffic to blue"
	@echo "  make switch-green  Manually switch traffic to green"
	@echo "  make health-blue   Run health check against blue (port 8081)"
	@echo "  make health-green  Run health check against green (port 8082)"
	@echo "  make logs-blue     Tail blue container logs"
	@echo "  make logs-green    Tail green container logs"
	@echo "  make logs-nginx    Tail nginx proxy logs"

up:
	docker-compose up -d
	@echo "✅ All containers started"

down:
	docker-compose down
	@echo "✅ All containers stopped"

status:
	@echo "=== Container Status ==="
	@docker-compose ps
	@echo ""
	@echo "=== Active Environment ==="
	@grep "server app-" $(UPSTREAM_CONF) | grep -v "#" || echo "(unknown)"
	@echo ""
	@echo "=== env.json ==="
	@cat ./assets/env.json 2>/dev/null || echo "(not found)"

switch-blue:
	@echo "🔀 Switching traffic to BLUE..."
	@sed -i 's/server app-green:80;/server app-blue:80;/' $(UPSTREAM_CONF)
	@sed -i 's/# ACTIVE_ENV=green/# ACTIVE_ENV=blue/' $(UPSTREAM_CONF)
	@docker exec $(NGINX_CONTAINER) nginx -t
	@docker exec $(NGINX_CONTAINER) nginx -s reload
	@echo "✅ Traffic switched to BLUE"

switch-green:
	@echo "🔀 Switching traffic to GREEN..."
	@sed -i 's/server app-blue:80;/server app-green:80;/' $(UPSTREAM_CONF)
	@sed -i 's/# ACTIVE_ENV=blue/# ACTIVE_ENV=green/' $(UPSTREAM_CONF)
	@docker exec $(NGINX_CONTAINER) nginx -t
	@docker exec $(NGINX_CONTAINER) nginx -s reload
	@echo "✅ Traffic switched to GREEN"

health-blue:
	@bash scripts/health-check.sh blue 8081

health-green:
	@bash scripts/health-check.sh green 8082

logs-blue:
	docker logs -f app-blue

logs-green:
	docker logs -f app-green

logs-nginx:
	docker logs -f nginx-proxy
