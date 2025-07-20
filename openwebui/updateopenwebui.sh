#!/bin/bash

# Pull the latest container images for OpenWebUI

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
    printBanner "OpenWebUI Updater"

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

    printMsg "${T_INFO_ICON} Pulling latest OpenWebUI container images..."
    if ! $docker_compose_cmd pull; then
        printErrMsg "Failed to pull OpenWebUI container images."
        exit 1
    fi

    printOkMsg "OpenWebUI container images have been successfully updated."
    printMsg "    ${T_INFO_ICON} You can now restart the service with: ${C_L_BLUE}./startopenwebui.sh${T_RESET}"
}

# Run the main script logic
main "$@"