# Makefile for Ollama & OpenWebUI Management Scripts

# Color Definitions
C_BOLD    := \033[1m
C_ULINE   := \033[4m
C_MAGENTA := \033[35m
C_CYAN    := \033[36m
C_RESET   := \033[0m

# Use bash for all shell commands
SHELL := /bin/bash

# Define script directories
SRC_DIR := ./src
WEBUI_DIR := ./openwebui

# Set the default goal to 'help' so that running 'make' by itself shows the help menu
.DEFAULT_GOAL := help

# Phony targets are not real files
.PHONY: help install config status models run diagnose test restart stop logs webui-start webui-stop webui-update manager benchmark

help: ##@ ✨ Show this help message
	@printf "\n$(C_BOLD)Ollama & OpenWebUI Management Scripts$(C_RESET)\n\n"
	@printf "$(C_BOLD)%-15s %s$(C_RESET)\n" "Target" "Description"; \
	awk 'BEGIN {FS = ":.*?##@ "} \
		/^##@ - / { \
			print ""; \
			printf "$(C_BOLD)$(C_MAGENTA)%s$(C_RESET)\n", substr($$0, 7); \
			next \
		} \
		/^[a-zA-Z0-9_-]+:.*?##@/ { printf "$(C_CYAN)%-15s$(C_RESET) %s\n", $$1, $$2 }' \
		$(MAKEFILE_LIST)

##@ - Ollama 🤖 Management 
manager: ##@ Ollama Manager 🚀
	@$(SRC_DIR)/ollama-manager.sh

install: ##@ Install 📦 or update Ollama
	@$(SRC_DIR)/install-ollama.sh

config: ##@ Configure ⚙️  Ollama settings
	@$(SRC_DIR)/config-ollama.sh

status: ##@ Check service status
	@$(SRC_DIR)/check-status.sh

models: ##@ Manage local models
	@$(SRC_DIR)/manage-models.sh

run: ##@ Run a local model
	@$(SRC_DIR)/run-model.sh

diagnose: ##@ Generate a diagnostic report 🩺
	@$(SRC_DIR)/diagnose.sh

test: ##@ Run all script self-tests
	@$(SRC_DIR)/test-all.sh

##@ - Ollama Service Management
restart: ##@ Restart the Ollama service
	@$(SRC_DIR)/restart-ollama.sh

stop: ##@ Stop 🛑 the Ollama service
	@$(SRC_DIR)/stop-ollama.sh

logs: ##@ View Ollama service logs 📜
	@$(SRC_DIR)/logs-ollama.sh -f

##@ - OpenWebUI 🌐 Service Management
webui-start: ##@ Start the OpenWebUI service
	@$(WEBUI_DIR)/start-openwebui.sh

webui-stop: ##@ Stop the OpenWebUI service
	@$(WEBUI_DIR)/stop-openwebui.sh

webui-update: ##@ Update the OpenWebUI service
	@$(WEBUI_DIR)/update-openwebui.sh

benchmark:
	@echo "Running benchmark script..."
	@$(SRC_DIR)/benchmark.sh