# Makefile for the Ollama Scripts project.
# The help comments are based on https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html

.DEFAULT_GOAL := help
.PHONY: all build clean test help ollama-manager dist-ollama-manager run

# Color Definitions
C_BLUE := \033[34m
C_WHITE := \033[37m
T_RESET := \033[0m

# Define variables
SHELL := /bin/bash
SRC_DIR := src
DIST_DIR := dist
TEST_DIR := test
SCRIPTS := $(patsubst $(SRC_DIR)/%.sh,%,$(wildcard $(SRC_DIR)/*.sh))

BUILD_SCRIPT := ./build.sh

LIB_FILES := $(wildcard $(SRC_DIR)/lib/*.sh)
TEST_SCRIPTS := $(wildcard $(TEST_DIR)/test_*.sh)
 
##@ General

help: ##@ Show this help message
	@printf "$(C_BLUE)%-28s$(T_RESET) %s\n" "Target" "Description"
	@printf "%-28s %s\n" "------" "-----------"
	@grep -E '^[a-zA-Z_-]+:.*?##@ .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?##@ "}; {printf "\033[34m%-28s\033[0m %s\n", $$1, $$2}'

all: help ##@ Show help message (default if no goal is specified after help)

build: ##@ Build all distributable scripts
	@echo "Building all scripts from '$(SRC_DIR)' into '$(DIST_DIR)'..."
	@$(BUILD_SCRIPT)

clean: ##@ Remove the dist directory and other build artifacts
	@echo "Cleaning up..."
	@rm -rf $(DIST_DIR)

ollama-manager: ##@ Run the development version of the Ollama Manager TUI
	@echo "Running development Ollama Manager from '$(SRC_DIR)'..."
	@bash ./$(SRC_DIR)/ollama-manager.sh

dist-ollama-manager: build ##@ Build and run the distributable Ollama Manager TUI
	@echo "Running distributable Ollama Manager from '$(DIST_DIR)'..."
	@./$(DIST_DIR)/ollama-manager.sh

run: build ##@ Run a specific script (e.g., 'make run script=check-status')
	@if [ -z "$(script)" ]; then \
		echo "Usage: make run script=<script_name>"; \
		exit 1; \
	fi
	@./$(DIST_DIR)/$(script).sh

test: $(LIB_FILES) ##@ Run all tests
	@echo "Running tests..."
	@for test_script in $(TEST_SCRIPTS); do \
		echo; \
		printf "$(C_WHITE)--- Running $test_script ---$(T_RESET)\n"; \
		bash $$test_script; \
	done