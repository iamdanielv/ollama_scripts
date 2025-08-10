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

show_help() {
    printBanner "Ollama Service Restarter"
    printMsg "Stops, resets, and starts the Ollama systemd service."
    printMsg "This is useful if the service becomes unresponsive."

    printMsg "\n${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [-h]"

    printMsg "\n${T_ULINE}Options:${T_RESET}"
    printMsg "  ${C_L_BLUE}-h, --help${T_RESET}      Show this help message."
}

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
                printMsg "\n${T_ERR}Invalid option: $1${T_RESET}"
                exit 1
                ;; 
        esac
    fi

    load_project_env # Source openwebui/.env for custom ports

    ensure_root "This script requires root privileges for systemd and kernel modules." "$@"
    printBanner "Ollama Service Restarter"

    # printMsg "${T_INFO_ICON} Checking prerequisites..."

    check_ollama_installed

    # --- GPU Detection ---
    local IS_NVIDIA=false
    printMsgNoNewline "${T_INFO_ICON} Checking for NVIDIA GPU...  \t"
    if _check_command_exists "nvidia-smi"; then
        IS_NVIDIA=true
        printMsg "${T_OK_ICON} NVIDIA ${T_BOLD}${C_GREEN}GPU detected${T_RESET}"
    else
        printMsg "${T_INFO_ICON} No NVIDIA GPU found. Assuming CPU-only operation."
    fi

    # --- Stop Ollama Service ---
    printMsg "${T_INFO_ICON} Stopping Ollama service..."
    # We can just call the stop script directly
    "$(dirname "$0")/stop-ollama.sh"

    # --- Reset NVIDIA UVM (if applicable) ---
    if [ "$IS_NVIDIA" = true ]; then
        printMsg "${T_INFO_ICON} Resetting NVIDIA UVM kernel module..."
        printMsgNoNewline "    ${C_BLUE}Reloading 'nvidia_uvm' module...${T_RESET}\t"
        # Unload the module. Ignore error if not loaded.
        rmmod nvidia_uvm &>/dev/null || true
        # Reload the module.
        if modprobe nvidia_uvm; then
            printMsg "${T_OK_ICON} Module ${T_BOLD}${C_GREEN}reloaded${T_RESET}"
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
        printMsg "${T_OK_ICON} Service ${T_BOLD}${C_GREEN}started${T_RESET}"
    fi

    # --- Final Verification ---
    verify_ollama_service
    printOkMsg "Ollama has been ${T_BOLD}${C_GREEN}successfully restarted${T_RESET}"
}

main "$@"
