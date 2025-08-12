#!/bin/bash
#
# config-ollama-advanced.sh
#
# This script provides an interactive way to configure advanced Ollama settings,
# such as the Key/Value (KV) cache type. This is intended for users who want
# to fine-tune Ollama's performance.
#
# The script will detect the current configuration and allow the user to
# enable, disable, or change settings in a dedicated systemd override file.
#
# Usage:
#   ./config-ollama-advanced.sh
#

# --- Boilerplate and Setup ---
#set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$0")")"
# shellcheck source=shared.sh
source "shared.sh"

# --- Script-specific Globals ---
OLLAMA_SERVICE_NAME="ollama"
OLLAMA_OVERRIDE_DIR="/etc/systemd/system/${OLLAMA_SERVICE_NAME}.service.d"
OLLAMA_KV_CACHE_CONF="${OLLAMA_OVERRIDE_DIR}/20-kv-cache.conf"
KV_CACHE_VAR="KV_CACHE_TYPE"

# Associative array to hold the colorized display strings for each option.
declare -A KV_CACHE_DISPLAY
KV_CACHE_DISPLAY=(
    [q8_0]="${C_L_GREEN}q8_0${T_RESET}"
    [f16]="${C_L_MAGENTA}f16${T_RESET}"
    [q4_0]="${C_L_BLUE}q4_0${T_RESET}"
)
readonly -A KV_CACHE_DISPLAY # Make the array read-only after assignment

# --- Function Definitions ---

#
# Fetches the current value of the KV_CACHE_TYPE from the dedicated override file.
#
get_current_kv_type() {
    local current_value=""
    if [[ -f "${OLLAMA_KV_CACHE_CONF}" ]]; then
        # This pipeline finds the line, extracts the value, and removes quotes.
        # The sed command captures everything after the '=' that is not a quote.
        current_value=$(grep -E "Environment=.*${KV_CACHE_VAR}=" "${OLLAMA_KV_CACHE_CONF}" | sed -E "s/.*${KV_CACHE_VAR}=([^\"\"]*).*/\1/" | tr -d '"'\''')
    fi
    echo "${current_value}"
}

#
# Creates or updates the systemd override file to set the KV_CACHE_TYPE.
#
set_kv_cache_type() {
    local var_value="$1"

    printInfoMsg "Ensuring override directory exists..."
    sudo mkdir -p "${OLLAMA_OVERRIDE_DIR}"
    clear_lines_up 1
    printInfoMsg "Setting ${KV_CACHE_VAR} to '${var_value}'..."
    printf "[Service]\nEnvironment=\"OLLAMA_FLASH_ATTENTION=1\"\nEnvironment=\"%s=%s\"\n" "${KV_CACHE_VAR}" "${var_value}" | sudo tee "${OLLAMA_KV_CACHE_CONF}" > /dev/null

    printOkMsg "Set ${KV_CACHE_VAR} in ${OLLAMA_KV_CACHE_CONF}"
}

#
# Removes the dedicated override file for the KV_CACHE_TYPE.
#
remove_kv_cache_conf() {
    if [[ -f "${OLLAMA_KV_CACHE_CONF}" ]]; then
        printInfoMsg "Removing ${OLLAMA_KV_CACHE_CONF} to use Ollama default..."
        sudo rm -f "${OLLAMA_KV_CACHE_CONF}"
        printOkMsg "Removed custom KV cache configuration."
    else
        printWarnMsg "Custom KV cache configuration not found, no changes made."
    fi
}

# --- Main Logic ---
main() {
    # Handle self-test
    if [[ "$1" == "-t" || "$1" == "--test" ]]; then
        # The "test" for this script is to ensure it can be called and that it
        # finds the shared libraries. The prereq checks are sufficient.
        prereq_checks "sudo" "systemctl" "grep" "sed"
        printOkMsg "Self-test passed."
        exit 0
    fi

    prereq_checks "sudo" "systemctl"

    printBanner "Ollama Advanced Configuration: KV Cache"
    
    # --- Detect Current State ---
    local current_kv_type
    current_kv_type=$(get_current_kv_type)

    if [[ -n "${current_kv_type}" ]]; then
        # Look up the full colorized string. Default to plain if not in our list.
        local display_value="${KV_CACHE_DISPLAY[${current_kv_type}]:-${current_kv_type}}"
        printInfoMsg "Current ${KV_CACHE_VAR} is set to: ${display_value}"
    else
        printInfoMsg "Current ${KV_CACHE_VAR} is not explicitly set."
        printMsg "    Ollama is using its default setting."
    fi

    printMsg "\n${T_ULINE}Choose a KV_CACHE_TYPE:${T_RESET}"
    printMsg " ${T_BOLD}1)${T_RESET} ${KV_CACHE_DISPLAY[q8_0]} (recommended for most GPUs)"
    printMsg " ${T_BOLD}2)${T_RESET} ${KV_CACHE_DISPLAY[f16]} (for high-end GPUs with ample VRAM)"
    printMsg " ${T_BOLD}3)${T_RESET} ${KV_CACHE_DISPLAY[q4_0]} (for GPUs with limited VRAM)"
    printMsg " ${T_BOLD}r)${T_RESET} Remove custom KV_CACHE_TYPE (use Ollama default)${T_RESET}"
    printMsg " ${T_BOLD}q)${T_RESET} ${C_L_YELLOW}Quit${T_RESET} without changing (or press ${C_L_YELLOW}ESC${T_RESET})\n"
    printMsgNoNewline " ${T_QST_ICON} Your choice: "

    # Read a single character, handling ESC and arrow keys.
    local choice=$(read_single_char)

    # Clear the prompt line for cleaner output before printing status messages.
    clear_current_line

    case $choice in
        1)
            set_kv_cache_type "q8_0"
            ;;
        2)
            set_kv_cache_type "f16"
            ;;
        3)
            set_kv_cache_type "q4_0"
            ;;
        r|R)
            remove_kv_cache_conf
            ;;
        q|Q|"$KEY_ESC")
            printOkMsg "Goodbye! No changes made."
            exit 0
            ;;
        *)
            printWarnMsg "Invalid choice. No changes made."
            exit 0
            ;;
    esac

    # --- Final Instructions ---
    run_with_spinner "Reloading systemd daemon..." sudo systemctl daemon-reload
    printInfoMsg "You must restart the Ollama service for the new settings to apply."
    if prompt_yes_no "Do you want to restart the Ollama service now?" "y"; then
        clear_lines_up 1
        run_with_spinner "Restarting Ollama service..." sudo systemctl restart "${OLLAMA_SERVICE_NAME}"
        verify_ollama_service
    else
        printInfoMsg "Please run './restart-ollama.sh' later to apply the changes."
    fi
    
    printOkMsg "Advanced configuration complete."
}

# --- Run ---
main "$@"
