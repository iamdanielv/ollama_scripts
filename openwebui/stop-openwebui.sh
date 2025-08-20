#!/bin/bash

# Stop OpenWebUI using docker compose

# --- Source the shared libraries ---
# shellcheck source=../shared.sh
if ! source "$(dirname "$0")/../shared.sh"; then
    echo "Error: Could not source shared.sh. Make sure it's in the parent directory." >&2
    exit 1
fi

# shellcheck source=../ollama-helpers.sh
if ! source "$(dirname "$0")/../ollama-helpers.sh"; then
    echo "Error: Could not source ollama-helpers.sh. Make sure it's in the parent directory." >&2
    exit 1
fi

# --- Script Functions ---

show_help() {
    printBanner "OpenWebUI Stopper"
    printMsg "Stops the OpenWebUI Docker containers."

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

    printBanner "OpenWebUI Stopper"

    printMsg "${T_INFO_ICON} Checking prerequisites..."
    check_docker_prerequisites

    printMsg "${T_INFO_ICON} Stopping OpenWebUI containers..."
    if ! run_webui_compose down; then
        printErrMsg "Failed to stop OpenWebUI containers."
        printMsg "    ${T_INFO_ICON} You can check the status with 'docker ps'."
        exit 1
    fi

    printOkMsg "OpenWebUI containers have been successfully stopped."
}

# Run the main script logic
main "$@"
