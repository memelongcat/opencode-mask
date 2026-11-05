SHELL := /usr/bin/env bash

DOCKER_COMPOSE_DIR=docker-compose
VOLUMES_DIR=volumes/opencode
ACP_DIR=opencode-acp

all: compose_rebuild acp_install_script

# --- operations with docker compose ---

.PHONY: compose_env
compose_env:
	@if [ ! -f $(DOCKER_COMPOSE_DIR)/.env ]; then \
		cp $(DOCKER_COMPOSE_DIR)/.env.example $(DOCKER_COMPOSE_DIR)/.env; \
		echo "Created $(DOCKER_COMPOSE_DIR)/.env from .env.example"; \
	fi

.PHONY: prepare_volumes
prepare_volumes:
	@if [ ! -d $(VOLUMES_DIR) ]; then \
		mkdir -p $(VOLUMES_DIR); \
		echo "Created $(VOLUMES_DIR)"; \
	fi

.PHONY: compose_stop
compose_stop: compose_env
	cd $(DOCKER_COMPOSE_DIR); docker compose stop $(ARGS)

.PHONY: compose_down
compose_down: compose_env
	cd $(DOCKER_COMPOSE_DIR); docker compose down $(ARGS)

.PHONY: compose_reset
compose_reset: compose_env
	cd $(DOCKER_COMPOSE_DIR); docker compose down --volumes $(ARGS)

.PHONY: compose_up
compose_up: compose_env prepare_volumes compose_stop
	cd $(DOCKER_COMPOSE_DIR); docker compose up -d $(ARGS)

.PHONY: compose_rebuild
compose_rebuild: compose_env prepare_volumes
	cd $(DOCKER_COMPOSE_DIR); docker compose -f docker-compose.build.yml build $(ARGS)

.PHONY: compose_up_rebuild
compose_up_rebuild: compose_env prepare_volumes compose_stop
	cd $(DOCKER_COMPOSE_DIR); docker compose -f docker-compose.build.yml build
	cd $(DOCKER_COMPOSE_DIR); docker compose up -d $(ARGS)

# --- operations with acp ---

.PHONY: acp_env
acp_env:
	@if [ ! -f $(ACP_DIR)/.acp.env ]; then \
		cp $(ACP_DIR)/.acp.env.example $(ACP_DIR)/.acp.env; \
		echo "Created $(ACP_DIR)/.acp.env from .acp.env.example"; \
	fi

.PHONY: acp_install_script
acp_install_script: acp_env
	cd $(ACP_DIR); cp opencode-docker-acp.sh ~/.local/bin/opencode-docker-acp.sh

.PHONY: acp_uninstall_script
acp_uninstall_script:
	rm ~/.local/bin/opencode-docker-acp.sh
