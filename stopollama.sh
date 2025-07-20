#!/bin/bash

# Stops the Ollama service.

# Exit immediately if a command exits with a non-zero status.
set -e
# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -o pipefail

# Source common utilities for colors and functions
# shellcheck source=./shared.sh
if ! source "$(dirname "$0")/shared.sh"; then
    echo "Error: Could not source shared.sh. Make sure it's in the same directory." >&2
    exit 1
fi

# --- Script Variables ---
SERVICE_NAME="ollama.service"
PROCESS_NAME="ollama"

# --- Main Execution ---
main() {
    # Check if the script is run as root, and re-run with sudo if not.
    if [[ $EUID -ne 0 ]]; then
        printMsg "${T_INFO_ICON} This script requires root privileges to stop the systemd service."
        printMsg "    ${C_L_BLUE}Attempting to re-run with sudo...${T_RESET}"
        # Re-execute the script with sudo, passing all original arguments
        exec sudo bash "$0" "$@"
    fi

    printBanner "Ollama Service Stopper"

    printMsg "${T_INFO_ICON} Checking prerequisites..."

    # Check if Ollama is installed
    if ! command -v ollama &> /dev/null; then
        printErrMsg "Ollama is not installed. Cannot stop a service that isn't installed."
        exit 1
    fi
    printOkMsg "Ollama is installed."

    # --- Stop Ollama Service ---
    printMsg "${T_INFO_ICON} Attempting to stop Ollama service..."
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        printMsgNoNewline "    ${C_BLUE}Executing 'systemctl stop'...${T_RESET}\t"
        if systemctl stop "$SERVICE_NAME"; then
            printMsg "${T_OK_ICON} Stopped via systemctl."
        else
            printMsg "    ${T_WARN_ICON} 'systemctl stop' failed. This can happen if the service is stuck."
            printMsgNoNewline "    ${C_L_BLUE}Attempting fallback with 'pkill'...${T_RESET}\t"
            if pkill -f "$PROCESS_NAME"; then
                sleep 2 # Give the process a moment to terminate
                printMsg "${T_OK_ICON} Stopped via pkill."
            else
                printErrMsg "Failed to stop Ollama service with both systemctl and pkill."
                exit 1
            fi
        fi
    else
        printMsg "    ${T_INFO_ICON} Ollama service is already stopped."
    fi

    printOkMsg "Ollama service has been successfully stopped."
}

# Run the main script logic, passing all arguments to it
main "$@"