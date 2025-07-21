#!/bin/bash

# Sometimes on wake from sleep, the ollama service will go into an inconsistent state.
# This script will stop, reset, and start Ollama using systemd.

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

# --- Main Execution ---

main() {
    ensure_root "This script requires root privileges for systemd and kernel modules." "$@"
    printBanner "Ollama Service Restarter"

    printMsg "${T_INFO_ICON} Checking prerequisites..."

    check_ollama_installed

    # --- GPU Detection ---
    local IS_NVIDIA=false
    printMsg "${T_INFO_ICON} Checking for NVIDIA GPU..."
    if nvidia-smi &> /dev/null; then
        IS_NVIDIA=true
        printMsg "    ${T_OK_ICON} NVIDIA GPU detected."
    else
        printMsg "    ${T_INFO_ICON} No NVIDIA GPU found. Assuming CPU-only operation."
    fi

    # --- Stop Ollama Service ---
    printMsg "${T_INFO_ICON} Stopping Ollama service..."
    # We can just call the stop script directly
    "$(dirname "$0")/stopollama.sh"

    # --- Reset NVIDIA UVM (if applicable) ---
    if [ "$IS_NVIDIA" = true ]; then
        printMsg "${T_INFO_ICON} Resetting NVIDIA UVM kernel module..."
        printMsgNoNewline "    ${C_BLUE}Reloading 'nvidia_uvm' module...${T_RESET}\t"
        # Unload the module. Ignore error if not loaded.
        rmmod nvidia_uvm &>/dev/null || true
        # Reload the module.
        if modprobe nvidia_uvm; then
            printMsg "${T_OK_ICON} Module reloaded."
        else
            printErrMsg "Failed to reset NVIDIA UVM."
            printMsg "    ${T_INFO_ICON} Check your NVIDIA driver installation."
            exit 1
        fi
    fi

    # --- Start Ollama Service ---
    printMsg "${T_INFO_ICON} Starting Ollama service..."
    printMsgNoNewline "    ${C_BLUE}Executing 'systemctl start'...${T_RESET}\t"
    if ! systemctl start ollama.service; then
        show_logs_and_exit "Failed to start Ollama via systemctl."
    else
        printMsg "${T_OK_ICON} Service started."
    fi

    # --- Final Verification ---
    verify_ollama_service
    printOkMsg "Ollama has been successfully restarted!"
}

main "$@"
