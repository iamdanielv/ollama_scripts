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

show_help() {
    printBanner "OpenWebUI Updater"
    printMsg "Pulls the latest Docker images for OpenWebUI."
    printMsg "If new images are downloaded, it will prompt to restart the service."

    printMsg "\n${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [-h]"

    printMsg "\n${T_ULINE}Options:${T_RESET}"
    printMsg "  ${C_L_BLUE}-h, --help${T_RESET}      Show this help message."
}

main() {
    if [[ -n "$1" ]]; then
        case "$1" in
            -h|--help) 
                show_help
                exit 0
                ;; 
            *)
                show_help
                printMsg "\n${T_ERR}Invalid option: $1${T_RESET}"
                exit 1
                ;; 
        esac
    fi

    printBanner "OpenWebUI Updater"

    printMsg "${T_INFO_ICON} Checking prerequisites..."

    check_docker_prerequisites
    local docker_compose_cmd
    docker_compose_cmd=$(get_docker_compose_cmd)

    # Ensure we are running in the script's directory so docker-compose can find its files.
    ensure_script_dir

    # The run_with_spinner function will handle output and status.
    # It stores the command's output in the global variable SPINNER_OUTPUT.
    # We split the docker_compose_cmd string into an array to handle "docker compose".
    local docker_compose_cmd_parts=($docker_compose_cmd)
    if ! run_with_spinner "Pulling latest OpenWebUI container images..." "${docker_compose_cmd_parts[@]}" pull; then
        # The error message is already printed by run_with_spinner.
        # Print the captured output on failure for debugging.
        if [[ -n "$SPINNER_OUTPUT" ]]; then
            echo -e "${C_GRAY}--- Start of Docker Compose Output ---${T_RESET}"
            echo "$SPINNER_OUTPUT" | sed 's/^/    /'
            echo -e "${C_GRAY}--- End of Docker Compose Output ---${T_RESET}"
        fi
        exit 1
    fi

    local pull_output
    pull_output="$SPINNER_OUTPUT"

    # Check if the output indicates a new image was downloaded.
    # Different versions of Docker Compose may have slightly different outputs.
    # We check for "Downloaded newer image" or "Download complete" to be safe,
    # as either indicates new layers were fetched.
    if echo "$pull_output" | grep -E -i -q 'Downloaded newer image|Download complete'; then
        printOkMsg "New OpenWebUI container images have been successfully downloaded."
        printMsgNoNewline "    ${T_QST_ICON} Would you like to restart the service now to apply the update? (y/N) "
        read -r response || true
        echo # Add a newline after user input
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            printMsg "\n    ${T_INFO_ICON} Restarting OpenWebUI..."
            "./start-openwebui.sh"
        else
            printMsg "\n    ${T_INFO_ICON} Update complete. You can restart the service later with: ${C_L_BLUE}./start-openwebui.sh${T_RESET}"
        fi
    else
        printOkMsg "All OpenWebUI images are already up-to-date."
    fi
}

# Run the main script logic
main "$@"
