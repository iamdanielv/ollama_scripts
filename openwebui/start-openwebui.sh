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

    # Ensure we are running in the script's directory so docker-compose can find its files.
    ensure_script_dir

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
        printMsg "    ${T_INFO_ICON} You can try running: ${C_L_BLUE}../restart-ollama.sh${T_RESET}"
        exit 1
    fi
    # The success message is already printed by poll_service.

    # Check if Ollama is exposed to the network, which is required for Docker to connect.
    printMsg "${T_INFO_ICON} Checking Ollama network configuration for Docker access..."
    if ! _is_systemd_system; then
        printMsg "    ${T_INFO_ICON} Could not auto-detect network config (not a systemd system)."
    elif ! _is_ollama_service_known; then
        printMsg "    ${T_INFO_ICON} Could not auto-detect network config (Ollama service not found)."
    else
        if ! check_network_exposure; then
            printMsg "    ${T_WARN_ICON} ${C_L_YELLOW}Warning: Ollama is only listening on localhost.${T_RESET}"
            printMsg "    ${T_INFO_ICON} OpenWebUI (in Docker) may not be able to connect to it."
            printMsg "    ${T_INFO_ICON} If you have issues, run ${C_L_BLUE}../config-ollama-net.sh${T_RESET} to expose Ollama."
        else
            printMsg "    ${T_OK_ICON} Ollama is exposed to the network."
        fi
    fi

    local docker_compose_cmd_parts=($docker_compose_cmd)
    if ! run_with_spinner "Starting OpenWebUI containers" "${docker_compose_cmd_parts[@]}" up -d; then
        # The error message is already printed by run_with_spinner.
        # Print the captured output on failure for debugging.
        if [[ -n "$SPINNER_OUTPUT" ]]; then
            echo -e "${C_GRAY}--- Start of Docker Compose Output ---${T_RESET}"
            echo "$SPINNER_OUTPUT" | sed 's/^/    /'
            echo -e "${C_GRAY}--- End of Docker Compose Output ---${T_RESET}"
        fi
        exit 1
    fi

    local webui_port=${OPEN_WEBUI_PORT:-3000}
    local webui_url="http://localhost:${webui_port}"

    if ! poll_service "$webui_url" "OpenWebUI UI" 60; then
        show_docker_logs_and_exit "OpenWebUI containers are running, but the UI is not responding at ${webui_url}."
    fi

    printOkMsg "OpenWebUI started successfully!"
    printMsg "    🌐 Access it at: ${C_L_BLUE}${webui_url}${T_RESET}"
}

# Run the main script logic
main "$@"
