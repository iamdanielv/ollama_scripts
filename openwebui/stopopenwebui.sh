#!/bin/bash

# Stop OpenWebUI using docker compose

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

main() {
    printBanner "OpenWebUI Stopper"

    printMsg "${T_INFO_ICON} Checking prerequisites..."

    # Check for Docker
    if ! command -v docker &>/dev/null; then
        printErrMsg "Docker is not installed. Cannot stop containers if Docker isn't installed."
        exit 1
    fi
    printOkMsg "Docker is installed."

    # Check for Docker Compose (v2 plugin or v1 standalone)
    local docker_compose_cmd
    if command -v docker &>/dev/null && docker compose version &>/dev/null; then
        printOkMsg "Docker Compose v2 (plugin) is available."
        docker_compose_cmd="docker compose"
    elif command -v docker-compose &>/dev/null; then
        printOkMsg "Docker Compose v1 (standalone) is available."
        docker_compose_cmd="docker-compose"
    else
        printErrMsg "Docker Compose is not installed. Cannot stop containers."
        exit 1
    fi

    # Ensure we are running in the script's directory so docker-compose.yml is found
    local SCRIPT_DIR
    SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
    if [[ "$PWD" != "$SCRIPT_DIR" ]]; then
        printMsg "${T_INFO_ICON} Changing to script directory: ${C_L_BLUE}${SCRIPT_DIR}${T_RESET}"
        cd "$SCRIPT_DIR"
    fi

    printMsg "${T_INFO_ICON} Stopping OpenWebUI containers..."
    if ! $docker_compose_cmd down; then
        printErrMsg "Failed to stop OpenWebUI containers."
        printMsg "    ${T_INFO_ICON} You can check the status with 'docker ps'."
        exit 1
    fi

    printOkMsg "OpenWebUI containers have been successfully stopped."
}

# Run the main script logic
main "$@"