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

# Determine the absolute path of the directory containing this script.
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Source common utilities for colors and functions
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

# --- Script-specific Globals ---
OLLAMA_SERVICE_NAME="ollama"
OLLAMA_OVERRIDE_DIR="/etc/systemd/system/${OLLAMA_SERVICE_NAME}.service.d"
OLLAMA_ADVANCED_CONF="${OLLAMA_OVERRIDE_DIR}/20-advanced-settings.conf"

# Environment variable names
KV_CACHE_VAR="KV_CACHE_TYPE"
CONTEXT_LENGTH_VAR="OLLAMA_CONTEXT_LENGTH"
NUM_PARALLEL_VAR="OLLAMA_NUM_PARALLEL"

# Associative array to hold the colorized display strings for each option.
declare -A KV_CACHE_DISPLAY
KV_CACHE_DISPLAY=(
    [q8_0]="${C_L_GREEN}q8_0${T_RESET}"
    [f16]="${C_L_MAGENTA}f16${T_RESET}"
    [q4_0]="${C_L_BLUE}q4_0${T_RESET}"
)

# --- Function Definitions ---

#
# Fetches the current value of a given environment variable from the override file.
#
get_env_var() {
    local var_name="$1"
    local conf_file="$2"
    local current_value=""
    if [[ -f "${conf_file}" ]]; then
        # This pipeline finds the line, extracts the value, and removes quotes.
        # The sed command captures everything after the '=' that is not a quote. Handles optional quotes.
        current_value=$(grep -E "Environment=.*${var_name}=" "${conf_file}" | sed -E "s/.*${var_name}=\"?([^\"]*)\"?.*/\1/" | tr -d '"'\''')
    fi
    echo "${current_value}"
}

#
# Updates or adds an environment variable in the systemd override file.
# Removes the variable if the value is empty.
# Returns 0 on change, 1 on error, 2 on no change.
#
set_env_var() {
    local var_name="$1"
    local var_value="$2"
    local conf_file="$3"

    # Ensure override directory exists
    sudo mkdir -p "$(dirname "$conf_file")"

    local old_value
    old_value=$(get_env_var "$var_name" "$conf_file")

    if [[ "$old_value" == "$var_value" ]]; then
        return 2 # No change needed
    fi

    # Read existing environment variables from the file, excluding the one we're setting.
    local existing_vars=()
    if [[ -f "$conf_file" ]]; then
        mapfile -t existing_vars < <(grep "Environment=" "$conf_file" 2>/dev/null | grep -v "Environment=.*${var_name}=")
    fi

    # Build the new file content
    local new_content="[Service]\n"
    for var in "${existing_vars[@]}"; do
        new_content+="${var}\n"
    done

    # Add our new/updated variable, if a value is provided.
    if [[ -n "$var_value" ]]; then
        new_content+="Environment=\"${var_name}=${var_value}\"\n"
    fi

    # If the file would be empty (only [Service] and a newline), remove it. Otherwise, write it.
    if [[ "${#existing_vars[@]}" -eq 0 && -z "$var_value" ]]; then
        if [[ -f "$conf_file" ]]; then
            sudo rm -f "$conf_file"
        fi
    else
        printf "%b" "$new_content" | sudo tee "$conf_file" > /dev/null
    fi
    return 0 # Change was made
}

#
# Removes the dedicated override file for advanced settings.
#
remove_advanced_conf() {
    if [[ -f "${OLLAMA_ADVANCED_CONF}" ]]; then
        printInfoMsg "Removing ${OLLAMA_ADVANCED_CONF} to use Ollama defaults..."
        sudo rm -f "${OLLAMA_ADVANCED_CONF}"
        printOkMsg "Removed custom advanced configuration."
        return 0
    else
        printWarnMsg "Custom advanced configuration not found, no changes made."
        return 2
    fi
}

#
# Interactive menu to configure KV Cache Type.
#
configure_kv_cache() {
    clear
    printBanner "Configure KV Cache Type"
    local current_kv_type
    current_kv_type=$(get_env_var "$KV_CACHE_VAR" "$OLLAMA_ADVANCED_CONF")
    local display_value="${KV_CACHE_DISPLAY[${current_kv_type}]:-${current_kv_type}}"
    printInfoMsg "Current ${KV_CACHE_VAR} is set to: ${display_value:-'(default)'}"

    printMsg "\n${T_ULINE}Choose a KV_CACHE_TYPE:${T_RESET}"
    printMsg " ${T_BOLD}1)${T_RESET} ${KV_CACHE_DISPLAY[q8_0]} (recommended for most GPUs)"
    printMsg " ${T_BOLD}2)${T_RESET} ${KV_CACHE_DISPLAY[f16]} (for high-end GPUs with ample VRAM)"
    printMsg " ${T_BOLD}3)${T_RESET} ${KV_CACHE_DISPLAY[q4_0]} (for GPUs with limited VRAM)"
    printMsg " ${T_BOLD}r)${T_RESET} Remove custom KV_CACHE_TYPE (use Ollama default)${T_RESET}"
    printMsg " ${T_BOLD}b)${T_RESET} Back to main menu (or press ${C_L_YELLOW}ESC${T_RESET})\n"
    printMsgNoNewline " ${T_QST_ICON} Your choice: "

    local choice
    choice=$(read_single_char)
    clear_current_line

    local changed=2 # 2 = no change
    case $choice in
        1)
            set_env_var "$KV_CACHE_VAR" "q8_0" "$OLLAMA_ADVANCED_CONF"; changed=$?
            set_env_var "OLLAMA_FLASH_ATTENTION" "1" "$OLLAMA_ADVANCED_CONF" >/dev/null # Also set flash attention
            ;;
        2)
            set_env_var "$KV_CACHE_VAR" "f16" "$OLLAMA_ADVANCED_CONF"; changed=$?
            set_env_var "OLLAMA_FLASH_ATTENTION" "1" "$OLLAMA_ADVANCED_CONF" >/dev/null
            ;;
        3)
            set_env_var "$KV_CACHE_VAR" "q4_0" "$OLLAMA_ADVANCED_CONF"; changed=$?
            set_env_var "OLLAMA_FLASH_ATTENTION" "1" "$OLLAMA_ADVANCED_CONF" >/dev/null
            ;;
        r|R)
            set_env_var "$KV_CACHE_VAR" "" "$OLLAMA_ADVANCED_CONF"; changed=$?
            set_env_var "OLLAMA_FLASH_ATTENTION" "" "$OLLAMA_ADVANCED_CONF" >/dev/null
            ;;
        b|B|"$KEY_ESC") return 2 ;;
        *) printWarnMsg "Invalid choice." && sleep 1; return 2 ;;
    esac

    # Return 0 if a change was made, 2 if not.
    [[ $changed -ne 2 ]] && return 0 || return 2
}

#
# Interactive menu to configure Context Length.
#
configure_context_length() {
    clear
    printBanner "Configure Context Length"
    local current_length
    current_length=$(get_env_var "$CONTEXT_LENGTH_VAR" "$OLLAMA_ADVANCED_CONF")
    printInfoMsg "Current ${CONTEXT_LENGTH_VAR} is set to: ${C_L_BLUE}${current_length:-'(default)'}${T_RESET}"
    printMsg "\nOllama will use this much context from a model's context window."
    printMsg "A larger value requires more VRAM. Default is typically 2048."

    printMsg "\n${T_ULINE}Choose a common value or enter a custom one:${T_RESET}"
    printMsg " ${T_BOLD}1)${T_RESET} 2048 (Default for many models)"
    printMsg " ${T_BOLD}2)${T_RESET} 4096"
    printMsg " ${T_BOLD}3)${T_RESET} 8192"
    printMsg " ${T_BOLD}4)${T_RESET} 16384"
    printMsg " ${T_BOLD}c)${T_RESET} Enter a ${C_L_CYAN}(c)ustom${T_RESET} value"
    printMsg " ${T_BOLD}r)${T_RESET} ${C_L_YELLOW}(R)emove${T_RESET} setting (use Ollama default)"
    printMsg " ${T_BOLD}b)${T_RESET} Back to main menu (or press ${C_L_YELLOW}ESC${T_RESET})\n"
    printMsgNoNewline " ${T_QST_ICON} Your choice: "

    local choice
    choice=$(read_single_char)
    clear_current_line

    local length=""

    case $choice in
        1) length="2048" ;;
        2) length="4096" ;;
        3) length="8192" ;;
        4) length="16384" ;;
        c|C)
            # The menu is 9 lines tall. Clear it before prompting for custom input.
            clear_lines_up 9
            read -r -p "$(echo -e "${T_QST_ICON} Enter custom context length: ")" length
            if [[ -z "$length" ]]; then
                printWarnMsg "No value entered. No changes made."
                sleep 1
                return 2
            fi
            ;;
        r|R)
            # Setting length to empty string will remove it from the config.
            length=""
            ;;
        b|B|"$KEY_ESC") return 2 ;;
        *) printWarnMsg "Invalid choice." && sleep 1; return 2 ;;
    esac

    # This validation block is now common for all choices except 'back' and 'invalid'.
    # It also handles the case where 'length' is empty (for removal), which is valid.
    if [[ -n "$length" && ! "$length" =~ ^[0-9]+$ ]]; then
        printErrMsg "Invalid input. Please enter a positive number."
        sleep 2
        return 2
    fi

    set_env_var "$CONTEXT_LENGTH_VAR" "$length" "$OLLAMA_ADVANCED_CONF"
    local exit_code=$?
    # Return 0 if a change was made (exit code 0), 2 if not (exit code 2).
    [[ $exit_code -ne 2 ]] && return 0 || return 2
}

#
# Interactive prompt to configure Number of Parallel Requests.
#
configure_num_parallel() {
    clear
    printBanner "Configure Parallel Requests"
    local current_parallel
    current_parallel=$(get_env_var "$NUM_PARALLEL_VAR" "$OLLAMA_ADVANCED_CONF")
    printInfoMsg "Current ${NUM_PARALLEL_VAR} is set to: ${C_L_BLUE}${current_parallel:-'(default)'}${T_RESET}"
    printMsg "\nSets the number of parallel requests that can be processed at once."
    printMsg "Increasing this can improve throughput but significantly increases VRAM usage. Default is 1."
    printMsg "\nEnter a new number (e.g., 2), or press ${C_L_YELLOW}Enter${T_RESET} to unset and use the default."
    read -r -p "$(echo -e "${T_QST_ICON} New value: ")" num

    if [[ -n "$num" && ! "$num" =~ ^[0-9]+$ ]]; then
        printErrMsg "Invalid input. Please enter a positive number."
        sleep 2
        return 2
    fi

    set_env_var "$NUM_PARALLEL_VAR" "$num" "$OLLAMA_ADVANCED_CONF"
    local exit_code=$?
    [[ $exit_code -ne 2 ]] && return 0 || return 2
}

# --- Main Logic ---
main() {
    # Handle self-test
    if [[ "$1" == "-t" || "$1" == "--test" ]]; then
        # The "test" for this script is to ensure it can be called and that it
        # finds the shared libraries. The prereq checks are sufficient.
        prereq_checks "sudo" "systemctl" "grep" "sed"
        _test_passed "Self-test passed"
        exit 0
    fi

    prereq_checks "sudo" "systemctl"

    # --- Migration from old config file ---
    local old_conf_file="${OLLAMA_OVERRIDE_DIR}/20-kv-cache.conf"
    if [[ -f "$old_conf_file" && ! -f "$OLLAMA_ADVANCED_CONF" ]]; then
        printInfoMsg "Migrating old configuration file..."
        sudo mv "$old_conf_file" "$OLLAMA_ADVANCED_CONF"
        printOkMsg "Migrated to ${OLLAMA_ADVANCED_CONF}"
        sleep 1
    fi

    local changes_made=false
    while true; do
        clear
        printBanner "Ollama Advanced Configuration"

        # --- Detect and Display Current State ---
        local current_kv_type
        current_kv_type=$(get_env_var "$KV_CACHE_VAR" "$OLLAMA_ADVANCED_CONF")
        local current_context_length
        current_context_length=$(get_env_var "$CONTEXT_LENGTH_VAR" "$OLLAMA_ADVANCED_CONF")
        local current_num_parallel
        current_num_parallel=$(get_env_var "$NUM_PARALLEL_VAR" "$OLLAMA_ADVANCED_CONF")

        local kv_display="${KV_CACHE_DISPLAY[${current_kv_type}]:-${current_kv_type}}"

        printMsg "${T_ULINE}Current Settings:${T_RESET}"
        printf "  %-22s: %b\n" "KV Cache Type" "${kv_display:-${C_GRAY}(default)${T_RESET}}"
        printf "  %-22s: %b\n" "Context Length" "${C_L_BLUE}${current_context_length:-'(default)'}${T_RESET}"
        printf "  %-22s: %b\n" "Parallel Requests" "${C_L_BLUE}${current_num_parallel:-'(default)'}${T_RESET}"

        # --- Display Menu ---
        printMsg "\n${T_ULINE}Choose an option to configure:${T_RESET}"
        printMsg " ${T_BOLD}1)${T_RESET} KV Cache Type"
        printMsg " ${T_BOLD}2)${T_RESET} Context Length"
        printMsg " ${T_BOLD}3)${T_RESET} Parallel Requests"
        printMsg " ${T_BOLD}r)${T_RESET} Reset all advanced settings to default"
        printMsg " ${T_BOLD}q)${T_RESET} ${C_L_YELLOW}Save and Quit${T_RESET} (or press ${C_L_YELLOW}ESC${T_RESET})\n"
        printMsgNoNewline " ${T_QST_ICON} Your choice: "

        local choice
        choice=$(read_single_char)
        clear_current_line

        case $choice in
            1)
                configure_kv_cache
                if [[ $? -eq 0 ]]; then changes_made=true; fi
                ;;
            2)
                configure_context_length
                if [[ $? -eq 0 ]]; then changes_made=true; fi
                ;;
            3)
                configure_num_parallel
                if [[ $? -eq 0 ]]; then changes_made=true; fi
                ;;
            r|R)
                remove_advanced_conf
                if [[ $? -eq 0 ]]; then changes_made=true; fi
                sleep 1 # Give user time to see the message
                ;;
            q|Q|"$KEY_ESC")
                break # Exit the loop
                ;;
            *)
                printWarnMsg "Invalid choice. Please try again."
                sleep 1
                ;;
        esac
    done

    # --- Finalization ---
    if [[ "$changes_made" == "true" ]]; then
        printInfoMsg "Changes were made. Systemd daemon needs to be reloaded."
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
    else
        printOkMsg "Goodbye! No changes were made."
    fi
}

# --- Run ---
main "$@"
