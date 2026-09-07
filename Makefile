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

# Argument passthrough for any target
PASS_ARGS ?= 

# Set the default goal to 'help' so that running 'make' by itself shows the help menu
.DEFAULT_GOAL := help

# Phony targets are not real files
.PHONY: help install config status models run diagnose test restart stop logs \
        webui-start webui-stop webui-update manager benchmark \
        config-status config-expose config-restrict status-watch \
        models-list models-pull models-update models-delete \
        install-version diagnose-file

help: ##@ ✨ Show this help message
	@printf "\n$(C_BOLD)Ollama & OpenWebUI Management Scripts$(C_RESET)\n\n"
	@printf "$(C_BOLD)%-18s %s$(C_RESET)\n" "Target" "Description"; \
	awk 'BEGIN {FS = ":.*?##@ "} \
		/^##@ - / { \
			print ""; \
			printf "$(C_BOLD)$(C_MAGENTA)%s$(C_RESET)\n", substr($$0, 7); \
			next \
		} \
		/^[a-zA-Z0-9_-]+:.*?##@/ { printf "$(C_CYAN)%-18s$(C_RESET) %s\n", $$1, $$2 }' \
		$(MAKEFILE_LIST)

##@ - Ollama 🤖 Management 
manager: ##@ Ollama Manager 🚀
	@$(SRC_DIR)/ollama-manager.sh $(PASS_ARGS)

install: ##@ Install 📦 or update Ollama
	@$(SRC_DIR)/install-ollama.sh $(PASS_ARGS)

install-version: ##@ Check Ollama version
	@$(SRC_DIR)/install-ollama.sh --version $(PASS_ARGS)

config: ##@ Configure ⚙️  Ollama settings (interactive)
	@$(SRC_DIR)/config-ollama.sh $(PASS_ARGS)

config-status: ##@ View current Ollama configuration
	@$(SRC_DIR)/config-ollama.sh --status $(PASS_ARGS)

config-expose: ##@ Expose Ollama to the network (0.0.0.0)
	@$(SRC_DIR)/config-ollama.sh --expose $(PASS_ARGS)

config-restrict: ##@ Restrict Ollama to localhost (127.0.0.1)
	@$(SRC_DIR)/config-ollama.sh --restrict $(PASS_ARGS)

status: ##@ Check service status
	@$(SRC_DIR)/check-status.sh $(PASS_ARGS)

status-watch: ##@ Watch service status (live refresh)
	@$(SRC_DIR)/check-status.sh --watch $(PASS_ARGS)

models: ##@ Manage local models (interactive)
	@$(SRC_DIR)/manage-models.sh $(PASS_ARGS)

models-list: ##@ List installed models
	@$(SRC_DIR)/manage-models.sh --list $(PASS_ARGS)

models-pull: ##@ Pull a new model
	@$(SRC_DIR)/manage-models.sh --pull $(PASS_ARGS)

models-update: ##@ Update all local models
	@$(SRC_DIR)/manage-models.sh --update-all $(PASS_ARGS)

models-delete: ##@ Delete a local model
	@$(SRC_DIR)/manage-models.sh --delete $(PASS_ARGS)

run: ##@ Run a local model
	@$(SRC_DIR)/run-model.sh $(PASS_ARGS)

diagnose: ##@ Generate a diagnostic report 🩺
	@$(SRC_DIR)/diagnose.sh $(PASS_ARGS)

diagnose-file: ##@ Save diagnostic report to a file
	@$(SRC_DIR)/diagnose.sh --output $(PASS_ARGS)

test: ##@ Run all script self-tests
	@$(SRC_DIR)/test-all.sh $(PASS_ARGS)

##@ - Ollama Service Management
restart: ##@ Restart the Ollama service
	@$(SRC_DIR)/restart-ollama.sh $(PASS_ARGS)

stop: ##@ Stop 🛑 the Ollama service
	@$(SRC_DIR)/stop-ollama.sh $(PASS_ARGS)

logs: ##@ View Ollama service logs 📜 (tail -f)
	@$(SRC_DIR)/logs-ollama.sh -f $(PASS_ARGS)

##@ - OpenWebUI 🌐 Service Management
webui-start: ##@ Start the OpenWebUI service
	@$(WEBUI_DIR)/start-openwebui.sh $(PASS_ARGS)

webui-stop: ##@ Stop the OpenWebUI service
	@$(WEBUI_DIR)/stop-openwebui.sh $(PASS_ARGS)

webui-update: ##@ Update the OpenWebUI service
	@$(WEBUI_DIR)/update-openwebui.sh $(PASS_ARGS)

benchmark: ##@ Run model performance benchmarks
	@echo "Running benchmark script..."
	@bash $(SRC_DIR)/benchmark.sh $(PASS_ARGS)
