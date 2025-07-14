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
    # Use tail to limit output and sed to indent
    docker compose logs --tail=20 | sed 's/^/    /'
    exit 1
}

printBanner "OpenWebUI Starter"

printMsg "${T_INFO_ICON} Checking prerequisites..."

# Check if Docker and Docker Compose are installed
if ! command -v docker &>/dev/null; then
    printErrMsg "Docker is not installed. Please install Docker to continue."
    exit 1
fi
printOkMsg "Docker is installed."

if ! docker compose version &>/dev/null; then
    printErrMsg "Docker Compose is not installed or not available in the PATH."
    exit 1
fi
printOkMsg "Docker Compose is available."

# Ensure we are running in the script's directory so docker-compose.yml is found
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
if [[ "$PWD" != "$SCRIPT_DIR" ]]; then
    printMsg "${T_INFO_ICON} Changing to script directory: ${C_L_BLUE}${SCRIPT_DIR}${T_RESET}"
    cd "$SCRIPT_DIR"
fi

printMsg "${T_INFO_ICON} Starting OpenWebUI containers in detached mode..."
if ! docker compose up -d; then
    show_docker_logs_and_exit "Failed to start OpenWebUI containers."
fi

printMsg "${T_INFO_ICON} Verifying OpenWebUI service status..."
printMsgNoNewline "    ${C_BLUE}Waiting for Web UI to respond ${T_RESET}"
for i in {1..30}; do
    sleep 1
    if curl --silent --fail --head http://localhost:3000 &>/dev/null; then
        echo # Newline for the dots
        printMsg "    ${T_OK_ICON} Web UI is responsive."
        printOkMsg "OpenWebUI started successfully!"
        printMsg "    🌐 Access it at: ${C_L_BLUE}http://localhost:3000${T_RESET}"
        exit 0
    fi

    printMsgNoNewline "${C_L_BLUE}.${T_RESET}"
done

echo # Newline after the dots
show_docker_logs_and_exit "OpenWebUI containers are running, but the UI is not responding."
