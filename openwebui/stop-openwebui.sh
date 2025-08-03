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

    check_docker_prerequisites
    local docker_compose_cmd
    docker_compose_cmd=$(get_docker_compose_cmd)

    # Ensure we are running in the script's directory so docker-compose can find its files.
    ensure_script_dir

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
