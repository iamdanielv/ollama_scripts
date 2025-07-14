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

# --- Helper Functions ---
show_logs_and_exit() {
    local message="$1"
    printErrMsg "$message"
    printMsg "    ${T_INFO_ICON} Preview of system log:"
    # Indent the journalctl output for readability
    journalctl -u ollama.service -n 10 --no-pager | sed 's/^/    /'
    exit 1
}

printBanner "Ollama Service Restarter"

printMsg "${T_INFO_ICON} Checking prerequisites..."

# Check if Ollama is installed
if ! command -v ollama &> /dev/null; then
    printErrMsg "Ollama is not installed. Please run the installer first."
    exit 1
fi
printOkMsg "Ollama is installed."

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
    printErrMsg "This script must be run as root to manage systemd services."
    exit 1
fi
printOkMsg "Running with root privileges."

# --- GPU Detection ---
IS_NVIDIA=false
printMsgNoNewline "${C_BLUE}Checking for NVIDIA GPU...${T_RESET}\t"
if nvidia-smi &> /dev/null; then
    IS_NVIDIA=true
    printMsg "${T_OK_ICON} NVIDIA GPU detected."
else
    printMsg "${T_INFO_ICON} No NVIDIA GPU found. Running on CPU only."
fi

# --- Stop Ollama Service ---
printMsg "${T_INFO_ICON} Attempting to stop Ollama service..."
if systemctl is-active --quiet ollama.service; then
    printMsgNoNewline "    ${C_BLUE}Stopping Ollama service...${T_RESET}\t"
    if systemctl stop ollama.service; then
        printMsg "${T_OK_ICON} Stopped via systemctl."
    else
        printMsg "${T_WARN_ICON} systemctl stop failed. Trying pkill..."
        if pkill -f ollama; then
            sleep 2 # Give the process a moment to terminate
            printMsg "    ${T_OK_ICON} Stopped via pkill."
        else
            printErrMsg "Failed to stop Ollama service."
            exit 1
        fi
    fi
else
    printMsg "    ${T_INFO_ICON} Ollama service is not running."
fi

# --- Reset NVIDIA UVM (if applicable) ---
if [ "$IS_NVIDIA" = true ]; then
    printMsgNoNewline "${C_BLUE}Resetting NVIDIA UVM...${T_RESET}\t\t"
    # Unload the module. Ignore error if not loaded.
    rmmod nvidia_uvm &>/dev/null || true
    # Reload the module.
    if modprobe nvidia_uvm; then
        printMsg "${T_OK_ICON} OK"
    else
        printErrMsg "Failed to reset NVIDIA UVM."
        printMsg "    ${T_INFO_ICON} Check your NVIDIA driver installation."
        exit 1
    fi
fi

# --- Start Ollama Service ---
printMsgNoNewline "${C_BLUE}Starting Ollama service...${T_RESET}\t"
if ! systemctl start ollama.service; then
    show_logs_and_exit "Failed to start Ollama via systemctl."
else
    printMsg "${T_OK_ICON} OK"
fi

# --- Verify Service and API Status ---
printMsg "${T_INFO_ICON} Verifying Ollama service status..."

# 1. Check if the service is active with systemd
if ! systemctl is-active --quiet ollama.service; then
    show_logs_and_exit "Ollama service failed to activate according to systemd."
fi
printMsg "    ${T_OK_ICON} Systemd reports service is active."

# 2. Poll the API endpoint to ensure it's responsive
printMsgNoNewline "    ${C_BLUE}Waiting for API to respond ${T_RESET}"
for i in {1..15}; do
    if curl --silent --fail --head http://localhost:11434 &>/dev/null; then
        echo # Newline for the dots
        printMsg "    ${T_OK_ICON} API is responsive."
        printOkMsg "Ollama has been successfully restarted!"
        exit 0
    fi
    sleep 1
    printMsgNoNewline "${C_L_BLUE}.${T_RESET}"
done

echo # Newline after the dots
printMsg "    ${T_INFO_ICON} The service might still be starting up, or there could be an issue."
show_logs_and_exit "Ollama service is active, but the API is not responding at http://localhost:11434."
