#!/bin/bash
#
# config-ollama.sh
#
# This script provides a unified, interactive, and non-interactive way to
# configure both basic network settings and advanced performance-tuning
# options for Ollama.
#
# It manages settings by creating or modifying systemd override files.
#
# Non-interactive flags are available for scripting and automation.
#
# Usage:
#   ./config-ollama.sh
#   ./config-ollama.sh --help
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

# --- Script Globals ---
readonly STATUS_NETWORK="network"
readonly STATUS_LOCALHOST="localhost"

OLLAMA_SERVICE_NAME="ollama"
OLLAMA_OVERRIDE_DIR="/etc/systemd/system/${OLLAMA_SERVICE_NAME}.service.d"
OLLAMA_ADVANCED_CONF="${OLLAMA_OVERRIDE_DIR}/20-advanced-settings.conf"

# Environment variable names
KV_CACHE_VAR="KV_CACHE_TYPE"
CONTEXT_LENGTH_VAR="OLLAMA_CONTEXT_LENGTH"
NUM_PARALLEL_VAR="OLLAMA_NUM_PARALLEL"
OLLAMA_MODELS_VAR="OLLAMA_MODELS"

# Associative array to hold the colorized display strings for each option.
declare -A KV_CACHE_DISPLAY
KV_CACHE_DISPLAY=(
    [q8_0]="${C_L_GREEN}q8_0${T_RESET}"
    [f16]="${C_L_MAGENTA}f16${T_RESET}"
    [q4_0]="${C_L_BLUE}q4_0${T_RESET}"
)

# --- Function Definitions ---

show_help() {
    printBanner "Ollama Configuration Script"
    printMsg "A unified script to manage Ollama network and performance settings."
    printMsg "If run without flags, it enters an interactive configuration menu.\n"

    printMsg "${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [options]\n"

    printMsg "${T_ULINE}Options:${T_RESET}"
    printMsg "  ${C_L_BLUE}-h, --help${T_RESET}            Show this help message."
    printMsg "  ${C_L_BLUE}-s, --status${T_RESET}          View the current configuration and exit."
    printMsg "  ${C_L_BLUE}-t, --test${T_RESET}            Run prerequisite checks and exit.\n"

    printMsg "${T_ULINE}Network Configuration:${T_RESET}"
    printMsg "  ${C_L_BLUE}-e, --expose${T_RESET}          Expose Ollama to the network (listens on 0.0.0.0)."
    printMsg "  ${C_L_BLUE}-r, --restrict${T_RESET}        Restrict Ollama to localhost (listens on 127.0.0.1).\n"

    printMsg "${T_ULINE}Advanced Configuration:${T_RESET}"
    printMsg "  ${C_L_CYAN}--kv-cache [type]${T_RESET}     Set KV_CACHE_TYPE (e.g., q8_0, f16, q4_0)."
    printMsg "  ${C_L_CYAN}--context-length [n]${T_RESET}  Set OLLAMA_CONTEXT_LENGTH (e.g., 4096)."
    printMsg "  ${C_L_CYAN}--num-parallel [n]${T_RESET}    Set OLLAMA_NUM_PARALLEL (e.g., 2)."
    printMsg "  ${C_L_CYAN}--models-dir [path]${T_RESET}     Set OLLAMA_MODELS directory (e.g., /mnt/models)."
    printMsg "  ${C_L_CYAN}--reset-advanced${T_RESET}      Remove all advanced settings and use Ollama defaults."
    printMsg "  ${C_L_CYAN}--restart${T_RESET}             Automatically restart the Ollama service after applying changes.\n"

    printMsg "${T_ULINE}Examples:${T_RESET}"
    printMsg "  ${C_GRAY}# Run the interactive configuration menu${T_RESET}"
    printMsg "  $(basename "$0")"
    printMsg "  ${C_GRAY}# Expose Ollama, set context length, and restart the service${T_RESET}"
    printMsg "  sudo $(basename "$0") --expose --context-length 8192 --restart"
    printMsg "  ${C_GRAY}# Reset all advanced settings to their defaults${T_RESET}"
    printMsg "  sudo $(basename "$0") --reset-advanced"
}

print_all_status() {
    # Fetch all current settings
    local network_status
    if check_network_exposure; then
        network_status="${C_L_YELLOW}EXPOSED to network (0.0.0.0)${T_RESET}"
    else
        network_status="${C_L_BLUE}RESTRICTED to localhost (127.0.0.1)${T_RESET}"
    fi
    local current_kv_type
    current_kv_type=$(get_env_var "$KV_CACHE_VAR" "$OLLAMA_ADVANCED_CONF")
    local current_context_length
    current_context_length=$(get_env_var "$CONTEXT_LENGTH_VAR" "$OLLAMA_ADVANCED_CONF")
    local current_num_parallel
    current_num_parallel=$(get_env_var "$NUM_PARALLEL_VAR" "$OLLAMA_ADVANCED_CONF")
    local current_models_dir
    current_models_dir=$(get_env_var "$OLLAMA_MODELS_VAR" "$OLLAMA_ADVANCED_CONF")
    local kv_display="${KV_CACHE_DISPLAY[${current_kv_type}]:-${current_kv_type}}"

    # Display
    printMsg "${T_ULINE}Current Configuration:${T_RESET}"
    printf "  %-20s : %b\n" "Network Exposure" "$network_status"
    printf "  %-20s : %b\n" "KV Cache Type" "${kv_display:-${C_GRAY}(default)${T_RESET}}"
    printf "  %-20s : %b\n" "Models Directory" "${C_L_CYAN}${current_models_dir:-'(default: ~/.ollama/models)'}${T_RESET}"
    printf "  %-20s : %b\n" "Context Length" "${C_L_BLUE}${current_context_length:-'(default)'}${T_RESET}"
    printf "  %-20s : %b\n" "Parallel Requests" "${C_L_BLUE}${current_num_parallel:-'(default)'}${T_RESET}"
}

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
# Resets all advanced settings by removing the dedicated override file.
#
reset_all_advanced_settings() {
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
# Interactive menu to configure Network Exposure.
#
configure_network_exposure() {
    clear
    printBanner "Configure Network Exposure"
    
    local is_exposed
    is_exposed=$(check_network_exposure)

    printMsgNoNewline "${T_BOLD}Current Status:${T_RESET}"
    if $is_exposed; then
        printMsg " ${C_L_YELLOW}EXPOSED to the network${T_RESET} (listening on 0.0.0.0)."
    else
        printMsg " ${C_L_BLUE}RESTRICTED to localhost${T_RESET} (listening on 127.0.0.1)."
    fi

    printMsg "\n${T_ULINE}Choose an option:${T_RESET}"
    printMsg "  ${T_BOLD}1, e)${T_RESET} ${C_L_YELLOW}(E)xpose to Network${T_RESET} (allow connections from other devices/containers)"
    printMsg "  ${T_BOLD}2, r)${T_RESET} ${C_L_BLUE}(R)estrict to Localhost${T_RESET} (default, more secure)"
    printMsg "     ${T_BOLD}b)${T_RESET} Back to main menu (or press ${C_L_YELLOW}ESC${T_RESET})\n"
    printMsgNoNewline " ${T_QST_ICON} Your choice: "
    local choice
    choice=$(read_single_char)
    clear_current_line

    local changed=2 # 2 = no change
    case "$choice" in
        1|e|E)
            ensure_root "Root privileges are required to modify systemd configuration."
            expose_to_network; changed=$?
            ;;
        2|r|R)
            ensure_root "Root privileges are required to modify systemd configuration."
            restrict_to_localhost; changed=$?
            ;;
        b|B|"$KEY_ESC")
            return 2
            ;;
        *)
            printWarnMsg "Invalid choice." && sleep 1
            return 2
            ;;
    esac

    # Return 0 if a change was made, 2 if not.
    if [[ $changed -ne 2 ]]; then
        verify_ollama_service &>/dev/null # Verify but hide output
        return 0
    fi
    return 2
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
            ensure_root "Root privileges are required to modify systemd configuration."
            set_env_var "$KV_CACHE_VAR" "q8_0" "$OLLAMA_ADVANCED_CONF"; changed=$?
            set_env_var "OLLAMA_FLASH_ATTENTION" "1" "$OLLAMA_ADVANCED_CONF" >/dev/null # Also set flash attention
            ;;
        2)
            ensure_root "Root privileges are required to modify systemd configuration."
            set_env_var "$KV_CACHE_VAR" "f16" "$OLLAMA_ADVANCED_CONF"; changed=$?
            set_env_var "OLLAMA_FLASH_ATTENTION" "1" "$OLLAMA_ADVANCED_CONF" >/dev/null
            ;;
        3)
            ensure_root "Root privileges are required to modify systemd configuration."
            set_env_var "$KV_CACHE_VAR" "q4_0" "$OLLAMA_ADVANCED_CONF"; changed=$?
            set_env_var "OLLAMA_FLASH_ATTENTION" "1" "$OLLAMA_ADVANCED_CONF" >/dev/null
            ;;
        r|R)
            ensure_root "Root privileges are required to modify systemd configuration."
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

    ensure_root "Root privileges are required to modify systemd configuration."
    set_env_var "$CONTEXT_LENGTH_VAR" "$length" "$OLLAMA_ADVANCED_CONF"
    local exit_code=$?
    # Return 0 if a change was made (exit code 0), 2 if not (exit code 2).
    [[ $exit_code -ne 2 ]] && return 0 || return 2
}

#
# Interactive menu to configure Number of Parallel Requests.
#
configure_num_parallel() {
    clear
    printBanner "Configure Parallel Requests"
    local current_parallel
    current_parallel=$(get_env_var "$NUM_PARALLEL_VAR" "$OLLAMA_ADVANCED_CONF")
    printInfoMsg "Current ${NUM_PARALLEL_VAR} is set to: ${C_L_BLUE}${current_parallel:-'(default)'}${T_RESET}"
    printMsg "\nSets the number of parallel requests that can be processed at once."
    printMsg "Increasing this can improve throughput but significantly increases VRAM usage. Default is 1."

    printMsg "\n${T_ULINE}Choose a value or enter a custom one:${T_RESET}"
    printMsg " ${T_BOLD}1)${T_RESET} 1 (Default)"
    printMsg " ${T_BOLD}2)${T_RESET} 2"
    printMsg " ${T_BOLD}3)${T_RESET} 3"
    printMsg " ${T_BOLD}4)${T_RESET} 4"
    printMsg " ${T_BOLD}c)${T_RESET} Enter a ${C_L_CYAN}(c)ustom${T_RESET} value"
    printMsg " ${T_BOLD}r)${T_RESET} ${C_L_YELLOW}(R)emove${T_RESET} setting (use Ollama default)"
    printMsg " ${T_BOLD}b)${T_RESET} Back to main menu (or press ${C_L_YELLOW}ESC${T_RESET})\n"
    printMsgNoNewline " ${T_QST_ICON} Your choice: "

    local choice
    choice=$(read_single_char)
    clear_current_line

    local num=""
    case $choice in
        1) num="1" ;;
        2) num="2" ;;
        3) num="3" ;;
        4) num="4" ;;
        c|C)
            clear_lines_up 9
            read -r -p "$(echo -e "${T_QST_ICON} Enter custom number of parallel requests: ")" num
            if [[ -z "$num" ]]; then
                printWarnMsg "No value entered. No changes made."
                sleep 1
                return 2
            fi
            ;;
        r|R) num="" ;;
        b|B|"$KEY_ESC") return 2 ;;
        *) printWarnMsg "Invalid choice." && sleep 1; return 2 ;;
    esac
    
    if [[ -n "$num" && ! "$num" =~ ^[0-9]+$ ]]; then
        printErrMsg "Invalid input. Please enter a positive number."
        sleep 2
        return 2
    fi
    ensure_root "Root privileges are required to modify systemd configuration."
    set_env_var "$NUM_PARALLEL_VAR" "$num" "$OLLAMA_ADVANCED_CONF"
    local exit_code=$?
    [[ $exit_code -ne 2 ]] && return 0 || return 2
}

#
# Interactive menu to configure the Ollama models directory.
#
configure_models_dir() {
    clear
    printBanner "Configure Models Directory"
    local current_dir
    current_dir=$(get_env_var "$OLLAMA_MODELS_VAR" "$OLLAMA_ADVANCED_CONF")
    printInfoMsg "Current ${OLLAMA_MODELS_VAR} is set to: ${C_L_CYAN}${current_dir:-'(default: ~/.ollama/models)'}${T_RESET}"
    printMsg "\nThis sets the directory where Ollama stores models and manifests."
    printMsg "Useful for storing models on a separate, larger drive."

    printMsg "\n${T_ULINE}Choose an option:${T_RESET}"
    printMsg " ${T_BOLD}c)${T_RESET} Enter a ${C_L_CYAN}(c)ustom${T_RESET} path"
    printMsg " ${T_BOLD}r)${T_RESET} ${C_L_YELLOW}(R)emove${T_RESET} setting (use Ollama default)"
    printMsg " ${T_BOLD}b)${T_RESET} Back to main menu (or press ${C_L_YELLOW}ESC${T_RESET})\n"
    printMsgNoNewline " ${T_QST_ICON} Your choice: "

    local choice
    choice=$(read_single_char)
    clear_current_line

    local models_path=""
    case $choice in
        c|C)
            clear_lines_up 6
            read -r -e -p "$(echo -e "${T_QST_ICON} Enter custom models directory path: ")" models_path
            # Expand tilde to home directory
            models_path="${models_path/#\~/$HOME}"

            if [[ -z "$models_path" ]]; then
                printWarnMsg "No path entered. No changes made."
                sleep 1.5
                return 2
            fi

            # Basic validation: check if it's an absolute path
            if [[ "$models_path" != /* ]]; then
                printErrMsg "Invalid path. Please enter an absolute path (e.g., /mnt/models)."
                sleep 2
                return 2
            fi

            # Offer to create the directory
            if [[ ! -d "$models_path" ]]; then
                if prompt_yes_no "Directory '${models_path}' does not exist. Create it now?" "y"; then
                    sudo mkdir -p "$models_path" && sudo chown -R "$(whoami)":"$(whoami)" "$models_path"
                    printOkMsg "Directory created."
                fi
            fi
            ;;
        r|R) models_path="" ;; # Setting to empty removes it
        b|B|"$KEY_ESC") return 2 ;;
        *) printWarnMsg "Invalid choice." && sleep 1; return 2 ;;
    esac

    ensure_root "Root privileges are required to modify systemd configuration."
    set_env_var "$OLLAMA_MODELS_VAR" "$models_path" "$OLLAMA_ADVANCED_CONF"
    [[ $? -ne 2 ]] && return 0 || return 2
}

# --- Main Logic ---
main() {
    # If the test flag is passed, run prerequisite checks and exit.
    if [[ "$1" == "-t" || "$1" == "--test" ]]; then
        run_tests
        # run_tests will exit with the appropriate code.
    fi

    _main_logic "$@"
}

run_interactive_menu() {
    local changes_made=false
    while true; do
        clear
        printBanner "Ollama Interactive Configuration"

        print_all_status

        # --- Display Menu ---
        printMsg "\n${T_ULINE}Choose an option to configure:${T_RESET}"
        printMsg " ${T_BOLD}1)${T_RESET} Network Exposure"
        printMsg " ${T_BOLD}2)${T_RESET} KV Cache Type"
        printMsg " ${T_BOLD}3)${T_RESET} Context Length"
        printMsg " ${T_BOLD}4)${T_RESET} Parallel Requests"
        printMsg " ${T_BOLD}5)${T_RESET} Models Directory"
        printMsg " ${T_BOLD}r)${T_RESET} ${C_L_YELLOW}Reset all advanced settings to default${T_RESET}"
        printMsg " ${T_BOLD}q)${T_RESET} ${C_L_YELLOW}Save and Quit${T_RESET} (or press ${C_L_YELLOW}ESC${T_RESET})\n"
        printMsgNoNewline " ${T_QST_ICON} Your choice: "

        local choice
        choice=$(read_single_char)
        clear_current_line

        case $choice in
            1)
                configure_network_exposure
                if [[ $? -eq 0 ]]; then changes_made=true; fi
                ;;
            2)
                configure_kv_cache
                if [[ $? -eq 0 ]]; then changes_made=true; fi
                ;;
            3)
                configure_context_length
                if [[ $? -eq 0 ]]; then changes_made=true; fi
                ;;
            4)
                configure_num_parallel
                if [[ $? -eq 0 ]]; then changes_made=true; fi
                ;;
            5)
                configure_models_dir
                if [[ $? -eq 0 ]]; then changes_made=true; fi
                ;;
            r|R)
                ensure_root "Root privileges are required to remove configuration files."
                reset_all_advanced_settings
                if [[ $? -eq 0 ]]; then changes_made=true; fi
                sleep 1.5 # Give user time to see the message
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
    finalize_changes "$changes_made" "true" "false" # is_interactive=true, auto_restart=false
}

_main_logic() {
    prereq_checks "sudo" "systemctl" "grep" "sed"

    # --- Migration from old config file ---
    local old_conf_file="${OLLAMA_OVERRIDE_DIR}/20-kv-cache.conf"
    if [[ -f "$old_conf_file" && ! -f "$OLLAMA_ADVANCED_CONF" ]]; then
        printInfoMsg "Migrating old configuration file..."
        sudo mv "$old_conf_file" "$OLLAMA_ADVANCED_CONF"
        printOkMsg "Migrated to ${OLLAMA_ADVANCED_CONF}"
        sleep 1
    fi

    # If no arguments are provided, run the interactive menu.
    if [[ $# -eq 0 ]]; then
        run_interactive_menu
        return 0
    fi

    # --- Non-Interactive Argument Handling ---
    local changes_made=false
    local auto_restart=false
    while [[ $# -gt 0 ]]; do
        local command="$1"
        case "$command" in
            -h|--help)
                show_help
                return 0
                ;;
            -s|--status)
                print_all_status
                return 0
                ;;
            -e|--expose)
                ensure_root "Root privileges are required to modify systemd configuration." "$command"
                expose_to_network
                if [[ $? -eq 0 ]]; then changes_made=true; fi
                shift
                ;;
            -r|--restrict)
                ensure_root "Root privileges are required to modify systemd configuration." "$command"
                restrict_to_localhost
                if [[ $? -eq 0 ]]; then changes_made=true; fi
                shift
                ;;
            --kv-cache)
                ensure_root "Root privileges are required to modify systemd configuration." "$command"
                if [[ -z "$2" || "$2" =~ ^- ]]; then printErrMsg "Error: '$1' requires a value (e.g., q8_0, f16)." >&2; return 1; fi
                set_env_var "$KV_CACHE_VAR" "$2" "$OLLAMA_ADVANCED_CONF"
                if [[ $? -eq 0 ]]; then changes_made=true; fi
                # Also set flash attention when setting kv_cache
                set_env_var "OLLAMA_FLASH_ATTENTION" "1" "$OLLAMA_ADVANCED_CONF" >/dev/null
                shift 2
                ;;
            --context-length)
                ensure_root "Root privileges are required to modify systemd configuration." "$command"
                if [[ -z "$2" || ! "$2" =~ ^[0-9]+$ ]]; then printErrMsg "Error: '$1' requires a numeric value." >&2; return 1; fi
                set_env_var "$CONTEXT_LENGTH_VAR" "$2" "$OLLAMA_ADVANCED_CONF"
                if [[ $? -eq 0 ]]; then changes_made=true; fi
                shift 2
                ;;
            --num-parallel)
                ensure_root "Root privileges are required to modify systemd configuration." "$command"
                if [[ -z "$2" || ! "$2" =~ ^[0-9]+$ ]]; then printErrMsg "Error: '$1' requires a numeric value." >&2; return 1; fi
                set_env_var "$NUM_PARALLEL_VAR" "$2" "$OLLAMA_ADVANCED_CONF"
                if [[ $? -eq 0 ]]; then changes_made=true; fi
                shift 2
                ;;
            --models-dir)
                ensure_root "Root privileges are required to modify systemd configuration." "$command"
                if [[ -z "$2" || "$2" =~ ^- ]]; then printErrMsg "Error: '$1' requires a path." >&2; return 1; fi
                local models_path="$2"
                models_path="${models_path/#\~/$HOME}" # Expand tilde
                if [[ "$models_path" != /* ]]; then printErrMsg "Error: Path for '$1' must be absolute." >&2; return 1; fi
                set_env_var "$OLLAMA_MODELS_VAR" "$models_path" "$OLLAMA_ADVANCED_CONF"
                if [[ $? -eq 0 ]]; then changes_made=true; fi
                shift 2
                ;;
            --reset-advanced)
                ensure_root "Root privileges are required to remove configuration files." "$command"
                reset_all_advanced_settings
                if [[ $? -eq 0 ]]; then changes_made=true; fi
                shift
                ;;
            --restart)
                auto_restart=true
                shift
                ;;
            *)
                show_help
                printErrMsg "\nInvalid option: $command" >&2
                return 1
                ;;
        esac
    done

    finalize_changes "$changes_made" "false" "$auto_restart" # is_interactive=false
}

#
# Handles the final steps after a configuration change: reloading the daemon
# and optionally restarting the service.
#
finalize_changes() {
    local changes_made="$1"
    local is_interactive="$2"
    local auto_restart="$3"

    if [[ "$changes_made" != "true" ]]; then
        if [[ "$is_interactive" == "true" ]]; then
            printOkMsg "Goodbye! No changes were made."
        else
            printInfoMsg "No changes were made to the configuration."
        fi
        return
    fi

    printInfoMsg "Configuration changed. Reloading systemd daemon..."
    run_with_spinner "Reloading systemd daemon..." sudo systemctl daemon-reload
    printOkMsg "Daemon reloaded."

    local should_restart=false
    if [[ "$is_interactive" == "true" ]]; then
        printInfoMsg "\nYou must restart the Ollama service for the new settings to apply."
        if prompt_yes_no "Do you want to restart the Ollama service now?" "y"; then
            clear_lines_up 1 # Clear the y/n prompt
            should_restart=true
        fi
    elif [[ "$auto_restart" == "true" ]]; then
        should_restart=true
    fi

    if [[ "$should_restart" == "true" ]]; then
        local restart_script="${SCRIPT_DIR}/restart-ollama.sh"
        if [[ -x "$restart_script" ]]; then
            printInfoMsg "Invoking '${restart_script##*/}' to apply changes..."
            # This script handles its own sudo check and output.
            "$restart_script"
            # The restart script already does verification, so we don't need to.
            printOkMsg "Configuration applied and service restarted."
        else
            printWarnMsg "Could not find or execute '${restart_script##*/}'. Falling back to systemctl."
            run_with_spinner "Restarting Ollama service..." sudo systemctl restart "${OLLAMA_SERVICE_NAME}"
            verify_ollama_service # Manual verification needed here.
            printOkMsg "Configuration applied and service restarted."
        fi
    else
        # If we're not restarting, give the user the next step.
        printInfoMsg "\nRun './restart-ollama.sh' or 'sudo systemctl restart ollama' to apply changes."
    fi
}

# --- Test Suite ---

# A function to run internal self-tests for the script's logic.
run_tests() {
    printBanner "Running Self-Tests for config-ollama.sh"
    initialize_test_suite

    # --- Mock Dependencies ---
    # Mock all functions with external dependencies or that modify system state.
    ensure_root() { :; }
    prereq_checks() { :; }
    finalize_changes() { MOCK_FINALIZE_CALLED_WITH_RESTART="$3"; }
    print_all_status() { MOCK_STATUS_CALLED=true; }
    expose_to_network() { MOCK_EXPOSE_CALLED=true; return "${MOCK_CHANGE_EXIT_CODE:-0}"; }
    restrict_to_localhost() { MOCK_RESTRICT_CALLED=true; return "${MOCK_CHANGE_EXIT_CODE:-0}"; }
    set_env_var() { MOCK_SET_ENV_VARS+=("$1=$2"); return "${MOCK_CHANGE_EXIT_CODE:-0}"; }
    reset_all_advanced_settings() { MOCK_RESET_CALLED=true; return "${MOCK_CHANGE_EXIT_CODE:-0}"; }

    export -f ensure_root prereq_checks finalize_changes print_all_status \
               expose_to_network restrict_to_localhost set_env_var reset_all_advanced_settings

    # --- Test Cases ---

    # Helper to reset mock state before each test section
    reset_mocks() {
        MOCK_FINALIZE_CALLED_WITH_RESTART=""
        MOCK_STATUS_CALLED=false
        MOCK_EXPOSE_CALLED=false
        MOCK_RESTRICT_CALLED=false
        MOCK_RESET_CALLED=false
        unset MOCK_SET_ENV_VARS
        declare -a MOCK_SET_ENV_VARS=()
    }

    printTestSectionHeader "Testing --status flag"
    reset_mocks
    _main_logic --status &>/dev/null
    _run_string_test "$MOCK_STATUS_CALLED" "true" "Calls print_all_status"

    printTestSectionHeader "Testing Network Flags"
    reset_mocks
    _main_logic --expose &>/dev/null
    _run_string_test "$MOCK_EXPOSE_CALLED" "true" "--expose calls expose_to_network"
    
    reset_mocks
    _main_logic --restrict &>/dev/null
    _run_string_test "$MOCK_RESTRICT_CALLED" "true" "--restrict calls restrict_to_localhost"

    printTestSectionHeader "Testing Advanced Flags"
    reset_mocks
    _main_logic --kv-cache q8_0 &>/dev/null
    _run_string_test "${MOCK_SET_ENV_VARS[0]}" "KV_CACHE_TYPE=q8_0" "--kv-cache sets KV_CACHE_TYPE"
    _run_string_test "${MOCK_SET_ENV_VARS[1]}" "OLLAMA_FLASH_ATTENTION=1" "--kv-cache also sets OLLAMA_FLASH_ATTENTION"
    _run_test '_main_logic --kv-cache &>/dev/null' 1 "--kv-cache fails without a value"

    reset_mocks
    _main_logic --context-length 4096 &>/dev/null
    _run_string_test "${MOCK_SET_ENV_VARS[0]}" "OLLAMA_CONTEXT_LENGTH=4096" "--context-length sets OLLAMA_CONTEXT_LENGTH"
    _run_test '_main_logic --context-length abc &>/dev/null' 1 "--context-length fails with non-numeric value"

    reset_mocks
    _main_logic --num-parallel 2 &>/dev/null
    _run_string_test "${MOCK_SET_ENV_VARS[0]}" "OLLAMA_NUM_PARALLEL=2" "--num-parallel sets OLLAMA_NUM_PARALLEL"

    reset_mocks
    _main_logic --models-dir /mnt/models &>/dev/null
    _run_string_test "${MOCK_SET_ENV_VARS[0]}" "OLLAMA_MODELS=/mnt/models" "--models-dir sets OLLAMA_MODELS"
    _run_test '_main_logic --models-dir relative/path &>/dev/null' 1 "--models-dir fails with relative path"

    printTestSectionHeader "Testing Control Flags"
    reset_mocks
    _main_logic --reset-advanced &>/dev/null
    _run_string_test "$MOCK_RESET_CALLED" "true" "--reset-advanced calls reset_all_advanced_settings"

    reset_mocks
    _main_logic --expose --restart &>/dev/null
    _run_string_test "$MOCK_FINALIZE_CALLED_WITH_RESTART" "true" "--restart flag is passed to finalize_changes"

    printTestSectionHeader "Testing Combined and Invalid Flags"
    reset_mocks
    _main_logic --expose --context-length 8192 &>/dev/null
    _run_string_test "$MOCK_EXPOSE_CALLED" "true" "Combined: Calls expose_to_network"
    _run_string_test "${MOCK_SET_ENV_VARS[0]}" "OLLAMA_CONTEXT_LENGTH=8192" "Combined: Sets OLLAMA_CONTEXT_LENGTH"
    _run_test '_main_logic --invalid-flag &>/dev/null' 1 "Handles an invalid flag"

    print_test_summary "ensure_root" "prereq_checks" "finalize_changes" "print_all_status" "expose_to_network" "restrict_to_localhost" "set_env_var" "reset_all_advanced_settings"
}
# --- Run ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
