#!/bin/bash

# Stops the Ollama service.

# Exit immediately if a command exits with a non-zero status.
set -e
# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -o pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
# --- Source the shared libraries ---
# shellcheck source=./shared.sh
if ! source "${SCRIPT_DIR}/shared.sh"; then
    echo "Error: Could not source shared.sh. Make sure it's in the same directory." >&2
    exit 1
fi

# shellcheck source=./ollama-helpers.sh
if ! source "${SCRIPT_DIR}/ollama-helpers.sh"; then
    echo "Error: Could not source ollama-helpers.sh. Make sure it's in the same directory." >&2
    exit 1
fi

# --- Script Functions ---

show_help() {
    printBanner "Ollama Service Stopper"
    printMsg "Stops the Ollama systemd service."

    printMsg "\n${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [-h]"

    printMsg "\n${T_ULINE}Options:${T_RESET}"
    printMsg "  ${C_L_BLUE}-h, --help${T_RESET}      Show this help message."
}

# --- Script Variables ---
SERVICE_NAME="ollama.service"

# --- Main Execution ---
main() {
    if [[ -n "$1" ]]; then
        case "$1" in
            -h|--help) 
                show_help
                exit 0
                ;; 
            *)
                show_help
                printErrMsg "\nInvalid option: $1"
                exit 1
                ;; 
        esac
    fi

    ensure_root "This script requires root privileges to stop the systemd service." "$@"
    printBanner "Ollama Service Stopper"

    if ! _is_ollama_service_known; then
        printWarnMsg "Ollama service (${SERVICE_NAME}) not found by systemd."
        printInfoMsg "Nothing to stop. Is Ollama installed correctly?"
        return 0 # Not an error, just nothing to do.
    fi

    # --- Stop Ollama Service ---
    # First, check if the service is already stopped.
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        printOkMsg "Ollama service is already stopped."
        return 0 # It's already in the desired state, success.
    fi

    printInfoMsg "Attempting to stop Ollama service..."
    # shellcheck disable=SC2086 # We are passing multiple arguments to the spinner function.
    run_with_spinner "Stopping Ollama service via systemctl..." sudo systemctl stop "$SERVICE_NAME"
    
    # Verification step: Check if the service is still active after the stop command.
    printMsgNoNewline "${T_INFO_ICON} Verifying service shutdown"
    for _ in {1..5}; do
        printMsgNoNewline "${C_L_BLUE}.${T_RESET}"
        if ! systemctl is-active --quiet "$SERVICE_NAME"; then
            clear_lines_up 2
            printOkMsg "Ollama service has been ${T_BOLD}${C_YELLOW}successfully stopped${T_RESET}"
            return 0 # Use return instead of exit to be reusable in other scripts
        fi
        sleep 1
    done

    # If the loop finishes and the service is still active, it's a hard failure.
    clear_lines_up 1
    printErrMsg "Failed to stop the Ollama service."
    printInfoMsg "    The service '${SERVICE_NAME}' is still reported as active by systemd."
    exit 1
}

# Run the main script logic, passing all arguments to it
main "$@"
