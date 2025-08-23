#!/bin/bash

# Sometimes on wake from sleep, the ollama service will go into an inconsistent state.
# This script will stop, reset, and start Ollama using systemd.

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
                printErrMsg "\nInvalid option: $1"
                exit 1
                ;; 
        esac
    fi

    load_project_env "${SCRIPT_DIR}/.env"

    ensure_root "This script requires root privileges for systemd and kernel modules." "$@"
    printBanner "Ollama Service Restarter"

    # printMsg "${T_INFO_ICON} Checking prerequisites..."

    check_ollama_installed

    # --- GPU Detection ---
    local IS_NVIDIA=false
    printMsgNoNewline "${T_INFO_ICON} Checking for NVIDIA GPU...  \t"
    if _check_command_exists "nvidia-smi"; then
        clear_current_line
        IS_NVIDIA=true
        printOkMsg "NVIDIA ${T_BOLD}${C_GREEN}GPU detected${T_RESET}"
    else
        clear_current_line
        printInfoMsg "No NVIDIA GPU found. Assuming CPU-only operation."
    fi

    # --- Stop Ollama Service ---
    # Call the stop script directly. It handles its own output and banners.
    "${SCRIPT_DIR}/stop-ollama.sh"

    # --- Reset NVIDIA UVM (if applicable) ---
    if [[ "$IS_NVIDIA" == "true" ]]; then
        printMsgNoNewline "${T_INFO_ICON} Reloading ${C_L_BLUE}'nvidia_uvm'${T_RESET} module...\t"
        # Unload the module. Ignore error if not loaded.
        rmmod nvidia_uvm &>/dev/null || true
        # Reload the module.
        if modprobe nvidia_uvm; then
            clear_current_line
            printOkMsg "Module ${T_BOLD}${C_GREEN}reloaded${T_RESET}"
        else
            printErrMsg "Failed to reset NVIDIA UVM."
            printInfoMsg "    Check your NVIDIA driver installation."
            exit 1
        fi
    fi

    # --- Start Ollama Service ---
    printMsgNoNewline "${T_INFO_ICON} Starting ${C_L_BLUE}Ollama service${T_RESET}...  \t"
    if ! systemctl start ollama.service; then
        show_logs_and_exit "Failed to start Ollama via systemctl."
    else
        clear_current_line
        printOkMsg "Service ${T_BOLD}${C_GREEN}started${T_RESET}"
    fi

    # --- Final Verification ---
    verify_ollama_service
    printOkMsg "Ollama has been ${T_BOLD}${C_GREEN}successfully restarted${T_RESET}"
}

main "$@"
