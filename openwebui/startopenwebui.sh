#!/bin/bash

# Start OpenWebUI using docker compose in detached mode

# Exit immediately if a command exits with a non-zero status.
set -e
# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -o pipefail

# Source common utilities for colors and functions
# shellcheck source=../shared.sh
if ! source "$(dirname "$0")/../shared.sh"; then
    echo "Error: Could not source shared.sh. Make sure it's in the parent directory." >&2
    exit 1
fi

# --- Helper Functions ---
show_docker_logs_and_exit() {
    local message="$1"
    printErrMsg "$message"
    printMsg "    ${T_INFO_ICON} Showing last 20 lines of container logs:"
    # Use tail to limit output and sed to indent. The command is determined dynamically.
    docker compose logs --tail=20 | sed 's/^/    /'
    exit 1
}

main() {
    printBanner "OpenWebUI Starter"

    printMsg "${T_INFO_ICON} Checking prerequisites..."

    check_docker_prerequisites
    local docker_compose_cmd
    docker_compose_cmd=$(get_docker_compose_cmd)

    # Ensure we are running in the script's directory so docker-compose.yml is found
    local SCRIPT_DIR
    SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
    if [[ "$PWD" != "$SCRIPT_DIR" ]]; then
        printMsg "${T_INFO_ICON} Changing to script directory: ${C_L_BLUE}${SCRIPT_DIR}${T_RESET}"
        cd "$SCRIPT_DIR"
    fi

    # Source .env file for configuration if it exists
    if [[ -f ".env" ]]; then
        printMsg "${T_INFO_ICON} Sourcing configuration from .env file."
        set -a
        source .env
        set +a
    fi

    local ollama_port=${OLLAMA_PORT:-11434}
    local ollama_url="http://localhost:${ollama_port}"

    # Check if Ollama is running, as it's a dependency for OpenWebUI
    printMsg "${T_INFO_ICON} Checking if Ollama service is running..."
    # Give Ollama a moment to respond if it was just started.
    if ! poll_service "$ollama_url" "Ollama" 10; then
        printErrMsg "Ollama service is not responding at ${ollama_url}."
        printMsg "    ${T_INFO_ICON} Please ensure Ollama is running before starting OpenWebUI."
        printMsg "    ${T_INFO_ICON} You can try running: ${C_L_BLUE}../restartollama.sh${T_RESET}"
        exit 1
    fi
    # The success message is already printed by poll_service_responsive.

    printMsg "${T_INFO_ICON} Starting OpenWebUI containers in detached mode..."
    if ! $docker_compose_cmd up -d; then
        show_docker_logs_and_exit "Failed to start OpenWebUI containers."
    fi

    local webui_port=${OPEN_WEBUI_PORT:-3000}
    local webui_url="http://localhost:${webui_port}"

    if ! poll_service "$webui_url" "OpenWebUI" 30; then
        show_docker_logs_and_exit "OpenWebUI containers are running, but the UI is not responding at ${webui_url}."
    fi

    printOkMsg "OpenWebUI started successfully!"
    printMsg "    🌐 Access it at: ${C_L_BLUE}${webui_url}${T_RESET}"
}

# Run the main script logic
main "$@"
