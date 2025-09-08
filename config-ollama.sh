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

    local current_kv_type=$(get_env_var "$KV_CACHE_VAR" "$OLLAMA_ADVANCED_CONF")
    local kv_display
    if [[ -n "$current_kv_type" ]]; then
        kv_display="${KV_CACHE_DISPLAY[${current_kv_type}]:-${current_kv_type}}"
    else
        kv_display="${C_GRAY}(default)${T_RESET}"
    fi

    local current_models_dir=$(get_env_var "$OLLAMA_MODELS_VAR" "$OLLAMA_ADVANCED_CONF")
    local models_dir_display
    if [[ -n "$current_models_dir" ]]; then
        models_dir_display="${C_L_CYAN}${current_models_dir}${T_RESET}"
    else
        models_dir_display="${C_GRAY}(default: ~/.ollama/models)${T_RESET}"
    fi

    local current_context_length=$(get_env_var "$CONTEXT_LENGTH_VAR" "$OLLAMA_ADVANCED_CONF")
    local context_display
    if [[ -n "$current_context_length" ]]; then
        context_display="${C_L_BLUE}${current_context_length}${T_RESET}"
    else
        context_display="${C_GRAY}(default)${T_RESET}"
    fi

    local current_num_parallel=$(get_env_var "$NUM_PARALLEL_VAR" "$OLLAMA_ADVANCED_CONF")
    local parallel_display
    if [[ -n "$current_num_parallel" ]]; then
        parallel_display="${C_L_BLUE}${current_num_parallel}${T_RESET}"
    else
        parallel_display="${C_GRAY}(default)${T_RESET}"
    fi

    # Display
    printMsg "${T_ULINE}Current Configuration:${T_RESET}"
    printf "  %-20s : %b\n" "Network Exposure" "$network_status"
    printf "  %-20s : %b\n" "KV Cache Type" "$kv_display"
    printf "  %-20s : %b\n" "Models Directory" "$models_dir_display"
    printf "  %-20s : %b\n" "Context Length" "$context_display"
    printf "  %-20s : %b\n" "Parallel Requests" "$parallel_display"
}

#
# Fetches the current value of a given environment variable from the override file.
#
get_env_var() {
    local var_name="$1"
    local conf_file="$2"

    if [[ ! -f "$conf_file" ]]; then
        # No file, no value. Echo empty string to maintain behavior.
        echo ""
        return
    fi

    # Use awk to find the right line and extract the value.
    # -F'[="]': Sets field separators to '=' or '"'.
    # For a line like Environment="KEY=VALUE", the fields are:
    # $1: Environment, $2: <empty>, $3: KEY, $4: VALUE
    # We check for the exact key match and print the corresponding value.
    awk -F'[="]' -v var="$var_name" '
        $1 == "Environment" && $3 == var {
            print $4
            exit # Found it, stop processing.
        }
    ' "$conf_file"
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
    local -n pending_network_ref=$1

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

    case "$choice" in
        1|e|E)
            if [[ "$pending_network_ref" != "network" ]]; then
                pending_network_ref="network"
                return 0 # changed
            fi
            ;;
        2|r|R)
            if [[ "$pending_network_ref" != "localhost" ]]; then
                pending_network_ref="localhost"
                return 0 # changed
            fi
            ;;
        b|B|"$KEY_ESC")
            return 2
            ;;
        *)
            printWarnMsg "Invalid choice." && sleep 1
            ;;
    esac
    return 2
}

#
# Interactive menu to configure KV Cache Type.
#
configure_kv_cache() {
    local -n pending_kv_ref=$1
    local -n pending_flash_ref=$2

    clear
    printBanner "Configure KV Cache Type"
    local current_kv_type
    current_kv_type=$(get_env_var "$KV_CACHE_VAR" "$OLLAMA_ADVANCED_CONF")
    local display_value=""
    if [[ -n "$current_kv_type" ]]; then
        # If a value exists, look it up in the display map.
        # Fallback to the value itself if not found in the map.
        display_value="${KV_CACHE_DISPLAY[${current_kv_type}]:-${current_kv_type}}"
    fi
    printInfoMsg "Current ${KV_CACHE_VAR} is set to: ${display_value:-${C_GRAY}(default)${T_RESET}}"

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
 
    local new_value=""
    case $choice in
        1) new_value="q8_0" ;;
        2) new_value="f16" ;;
        3) new_value="q4_0" ;;
        r|R) new_value="" ;;
        b|B|"$KEY_ESC") return 2 ;;
        *) printWarnMsg "Invalid choice." && sleep 1; return 2 ;;
    esac

    if [[ "$pending_kv_ref" != "$new_value" ]]; then
        pending_kv_ref="$new_value"
        # Also set/unset flash attention
        if [[ -n "$new_value" ]]; then
            pending_flash_ref="1"
        else
            pending_flash_ref=""
        fi
        return 0 # changed
    fi
    return 2 # no change
}

#
# Interactive menu to configure Context Length.
#
configure_context_length() {
    local -n pending_length_ref=$1

    clear
    printBanner "Configure Context Length"
    local current_length
    current_length=$(get_env_var "$CONTEXT_LENGTH_VAR" "$OLLAMA_ADVANCED_CONF")
    local length_display
    if [[ -n "$current_length" ]]; then
        length_display="${C_L_BLUE}${current_length}${T_RESET}"
    else
        length_display="${C_GRAY}(default)${T_RESET}"
    fi
    printInfoMsg "Current ${CONTEXT_LENGTH_VAR} is set to: ${length_display}"
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

    if [[ "$pending_length_ref" != "$length" ]]; then
        pending_length_ref="$length"
        return 0 # changed
    fi
    return 2 # no change
}

#
# Interactive menu to configure Number of Parallel Requests.
#
configure_num_parallel() {
    local -n pending_parallel_ref=$1
    clear
    printBanner "Configure Parallel Requests"
    local current_parallel
    current_parallel=$(get_env_var "$NUM_PARALLEL_VAR" "$OLLAMA_ADVANCED_CONF")
    local parallel_display
    if [[ -n "$current_parallel" ]]; then
        parallel_display="${C_L_BLUE}${current_parallel}${T_RESET}"
    else
        parallel_display="${C_GRAY}(default)${T_RESET}"
    fi
    printInfoMsg "Current ${NUM_PARALLEL_VAR} is set to: ${parallel_display}"
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
    if [[ "$pending_parallel_ref" != "$num" ]]; then
        pending_parallel_ref="$num"
        return 0 # changed
    fi
    return 2 # no change
}

#
# Interactive menu to configure the Ollama models directory.
#
configure_models_dir() {
    local -n pending_dir_ref=$1
    clear
    printBanner "Configure Models Directory"
    local current_dir
    current_dir=$(get_env_var "$OLLAMA_MODELS_VAR" "$OLLAMA_ADVANCED_CONF")
    local dir_display
    if [[ -n "$current_dir" ]]; then
        dir_display="${C_L_CYAN}${current_dir}${T_RESET}"
    else
        dir_display="${C_GRAY}(default: ~/.ollama/models)${T_RESET}"
    fi
    printInfoMsg "Current ${OLLAMA_MODELS_VAR} is set to: ${dir_display}"
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

    if [[ "$pending_dir_ref" != "$models_path" ]]; then
        pending_dir_ref="$models_path"
        return 0 # changed
    fi
    return 2 # no change
}

# --- Main Logic ---
main() {
    # If the test flag is passed, run prerequisite checks and exit.
    if [[ "$1" == "-t" || "$1" == "--test" ]]; then
        run_tests "$@"
        # run_tests will exit with the appropriate code.
    fi

    _main_logic "$@"
}

run_interactive_menu() {
    # --- State Variables ---
    local current_network_status pending_network_status
    local current_kv_type pending_kv_type
    local current_flash_attention pending_flash_attention
    local current_context_length pending_context_length
    local current_num_parallel pending_num_parallel
    local current_models_dir pending_models_dir

    # --- Helper to load all current and pending states from the system ---
    _load_states() {
        if check_network_exposure; then current_network_status="network"; else current_network_status="localhost"; fi
        current_kv_type=$(get_env_var "$KV_CACHE_VAR" "$OLLAMA_ADVANCED_CONF")
        current_flash_attention=$(get_env_var "OLLAMA_FLASH_ATTENTION" "$OLLAMA_ADVANCED_CONF")
        current_context_length=$(get_env_var "$CONTEXT_LENGTH_VAR" "$OLLAMA_ADVANCED_CONF")
        current_num_parallel=$(get_env_var "$NUM_PARALLEL_VAR" "$OLLAMA_ADVANCED_CONF")
        current_models_dir=$(get_env_var "$OLLAMA_MODELS_VAR" "$OLLAMA_ADVANCED_CONF")

        pending_network_status="$current_network_status"
        pending_kv_type="$current_kv_type"
        pending_flash_attention="$current_flash_attention"
        pending_context_length="$current_context_length"
        pending_num_parallel="$current_num_parallel"
        pending_models_dir="$current_models_dir"
    }

    # --- Helper to check for pending changes ---
    _has_pending_changes() {
        if [[ "$current_network_status" != "$pending_network_status" || \
              "$current_kv_type" != "$pending_kv_type" || \
              "$current_flash_attention" != "$pending_flash_attention" || \
              "$current_context_length" != "$pending_context_length" || \
              "$current_num_parallel" != "$pending_num_parallel" || \
              "$current_models_dir" != "$pending_models_dir" ]]; then
            return 0 # 0 is true in shell
        else
            return 1 # 1 is false
        fi
    }

    _load_states # Initial load

    local menu_height=14 # banner(2) + header(1) + options(5) + spacer(1) + actions(4) + prompt(1)
    local redraw_full_menu=true

    while true; do
        if [[ "$redraw_full_menu" == "true" ]]; then
            clear
            redraw_full_menu=false
        else
            # This is the flicker-free part
            move_cursor_up "$menu_height"
        fi

        printBanner "Ollama Interactive Configuration"

        # --- Display Logic ---
        local network_display
        if [[ "$current_network_status" == "network" ]]; then network_display="${C_L_YELLOW}EXPOSED${T_RESET}"; else network_display="${C_L_BLUE}RESTRICTED${T_RESET}"; fi
        if [[ "$current_network_status" != "$pending_network_status" ]]; then
            local pending_net_display
            if [[ "$pending_network_status" == "network" ]]; then pending_net_display="${C_L_YELLOW}EXPOSED${T_RESET}"; else pending_net_display="${C_L_BLUE}RESTRICTED${T_RESET}"; fi
            network_display+=" ${C_WHITE}→${T_RESET} ${pending_net_display}"
        fi

        local kv_display
        if [[ -n "$pending_kv_type" ]]; then kv_display="${KV_CACHE_DISPLAY[${pending_kv_type}]:-${pending_kv_type}}"; else kv_display="${C_GRAY}(default)${T_RESET}"; fi
        if [[ "$current_kv_type" != "$pending_kv_type" ]]; then
            local current_kv_display
            if [[ -n "$current_kv_type" ]]; then current_kv_display="${KV_CACHE_DISPLAY[${current_kv_type}]:-${current_kv_type}}"; else current_kv_display="${C_GRAY}(default)${T_RESET}"; fi
            kv_display="${current_kv_display} ${C_WHITE}→${T_RESET} ${kv_display}"
        fi

        local context_display
        if [[ -n "$pending_context_length" ]]; then context_display="${C_L_BLUE}${pending_context_length}${T_RESET}"; else context_display="${C_GRAY}(default)${T_RESET}"; fi
        if [[ "$current_context_length" != "$pending_context_length" ]]; then
            local current_ctx_display
            if [[ -n "$current_context_length" ]]; then current_ctx_display="${C_L_BLUE}${current_context_length}${T_RESET}"; else current_ctx_display="${C_GRAY}(default)${T_RESET}"; fi
            context_display="${current_ctx_display} ${C_WHITE}→${T_RESET} ${context_display}"
        fi

        local parallel_display
        if [[ -n "$pending_num_parallel" ]]; then parallel_display="${C_L_BLUE}${pending_num_parallel}${T_RESET}"; else parallel_display="${C_GRAY}(default)${T_RESET}"; fi
        if [[ "$current_num_parallel" != "$pending_num_parallel" ]]; then
            local current_par_display
            if [[ -n "$current_num_parallel" ]]; then current_par_display="${C_L_BLUE}${current_num_parallel}${T_RESET}"; else current_par_display="${C_GRAY}(default)${T_RESET}"; fi
            parallel_display="${current_par_display} ${C_WHITE}→${T_RESET} ${parallel_display}"
        fi

        local models_dir_display
        if [[ -n "$pending_models_dir" ]]; then models_dir_display="${C_L_CYAN}${pending_models_dir}${T_RESET}"; else models_dir_display="${C_GRAY}(default)${T_RESET}"; fi
        if [[ "$current_models_dir" != "$pending_models_dir" ]]; then
            local current_dir_display
            if [[ -n "$current_models_dir" ]]; then current_dir_display="${C_L_CYAN}${current_models_dir}${T_RESET}"; else current_dir_display="${C_GRAY}(default)${T_RESET}"; fi
            models_dir_display="${current_dir_display} ${C_WHITE}→${T_RESET} ${models_dir_display}"
        fi

        # --- Display Menu ---
        printMsg "${T_ULINE}Choose an option to configure:${T_RESET}"
        printf " ${T_BOLD}1)${T_RESET} %-25s - %b\n" "Network Exposure" "$network_display"
        printf " ${T_BOLD}2)${T_RESET} %-25s - %b\n" "KV Cache Type" "$kv_display"
        printf " ${T_BOLD}3)${T_RESET} %-25s - %b\n" "Context Length" "$context_display"
        printf " ${T_BOLD}4)${T_RESET} %-25s - %b\n" "Parallel Requests" "$parallel_display"
        printf " ${T_BOLD}5)${T_RESET} %-25s - %b\n" "Models Directory" "$models_dir_display"
        printMsg ""
        printMsg " ${T_BOLD}r)${T_RESET} Reset all advanced settings to default"
        printMsg " ${T_BOLD}c)${T_RESET} ${C_L_YELLOW}Cancel/Discard${T_RESET} all pending changes"
        printMsg " ${T_BOLD}s)${T_RESET} ${C_L_GREEN}Save changes and Quit${T_RESET}"
        printMsg " ${T_BOLD}q)${T_RESET} Quit without saving (or press ${C_L_YELLOW}ESC${T_RESET})\n"
        printMsgNoNewline " ${T_QST_ICON} Your choice: "

        local choice
        choice=$(read_single_char)
        clear_current_line

        case $choice in
            1)
                configure_network_exposure pending_network_status
                # Sub-menu clears the screen, so we need a full redraw on the next loop.
                redraw_full_menu=true
                ;;
            2)
                configure_kv_cache pending_kv_type pending_flash_attention
                redraw_full_menu=true
                ;;
            3)
                configure_context_length pending_context_length
                redraw_full_menu=true
                ;;
            4)
                configure_num_parallel pending_num_parallel
                redraw_full_menu=true
                ;;
            5)
                configure_models_dir pending_models_dir
                redraw_full_menu=true
                ;;
            r|R)
                pending_kv_type=""
                pending_flash_attention=""
                pending_context_length=""
                pending_num_parallel=""
                pending_models_dir=""
                ;;
            c|C)
                printInfoMsg "Discarding pending changes..."
                _load_states # Reloads current state and resets pending state
                sleep 1
                # Clear the message before redrawing
                clear_lines_up 1
                ;;
            s|S)
                apply_staged_changes "$pending_network_status" "$pending_kv_type" "$pending_flash_attention" "$pending_context_length" "$pending_num_parallel" "$pending_models_dir"
                break # Exit the loop
                ;;
            q|Q|"$KEY_ESC")
                if _has_pending_changes; then
                    # Go to top of menu and clear everything to show the prompt cleanly
                    move_cursor_up "$menu_height"
                    tput ed

                    if prompt_yes_no "You have unsaved changes. Quit without saving?" "n"; then
                        # User said yes.
                        printInfoMsg "Quitting without saving changes."
                        break
                    else
                        # User said no or cancelled. We need to redraw the menu.
                        redraw_full_menu=true
                    fi
                else
                    printInfoMsg "Quitting without saving changes."
                    break # Exit the loop
                fi
                ;;
            *)
                printWarnMsg "Invalid choice. Please try again."
                sleep 1
                # Clear the message before redrawing
                clear_lines_up 1
                ;;
        esac
    done
}

#
# Writes the advanced configuration file from scratch based on pending values.
#
_write_advanced_config() {
    local kv_type="$1"
    local flash_attention="$2"
    local context_len="$3"
    local num_parallel="$4"
    local models_dir="$5"

    local conf_file="$OLLAMA_ADVANCED_CONF"
    local content="[Service]\n"
    local has_content=false

    if [[ -n "$kv_type" ]]; then
        content+="Environment=\"${KV_CACHE_VAR}=${kv_type}\"\n"
        has_content=true
    fi
    if [[ -n "$flash_attention" ]]; then
        content+="Environment=\"OLLAMA_FLASH_ATTENTION=${flash_attention}\"\n"
        has_content=true
    fi
    if [[ -n "$context_len" ]]; then
        content+="Environment=\"${CONTEXT_LENGTH_VAR}=${context_len}\"\n"
        has_content=true
    fi
    if [[ -n "$num_parallel" ]]; then
        content+="Environment=\"${NUM_PARALLEL_VAR}=${num_parallel}\"\n"
        has_content=true
    fi
    if [[ -n "$models_dir" ]]; then
        content+="Environment=\"${OLLAMA_MODELS_VAR}=${models_dir}\"\n"
        has_content=true
    fi

    if [[ "$has_content" == "true" ]]; then
        printf "%b" "$content" | sudo tee "$conf_file" > /dev/null
    else
        if [[ -f "$conf_file" ]]; then
            sudo rm -f "$conf_file"
        fi
    fi
}

#
# Compares current vs pending states and applies changes to the system.
#
apply_staged_changes() {
    local p_network="$1"
    local p_kv_type="$2"
    local p_flash="$3"
    local p_context="$4"
    local p_parallel="$5"
    local p_models_dir="$6"

    local any_change_made=false

    # --- Check Network Change ---
    local current_network
    if check_network_exposure; then current_network="network"; else current_network="localhost"; fi
    if [[ "$current_network" != "$p_network" ]]; then
        ensure_root "Root privileges are required to modify systemd configuration."
        printInfoMsg "Applying network configuration..."
        local override_dir="/etc/systemd/system/ollama.service.d"
        local override_file="${override_dir}/10-expose-network.conf"
        if [[ "$p_network" == "network" ]]; then
            sudo mkdir -p "$override_dir"
            echo -e '[Service]\nEnvironment="OLLAMA_HOST=0.0.0.0"' | sudo tee "$override_file" >/dev/null
        else # restrict
            sudo rm -f "$override_file"
        fi
        any_change_made=true
    fi

    # --- Check Advanced Settings Change ---
    local current_kv_type=$(get_env_var "$KV_CACHE_VAR" "$OLLAMA_ADVANCED_CONF")
    local current_flash=$(get_env_var "OLLAMA_FLASH_ATTENTION" "$OLLAMA_ADVANCED_CONF")
    local current_context=$(get_env_var "$CONTEXT_LENGTH_VAR" "$OLLAMA_ADVANCED_CONF")
    local current_parallel=$(get_env_var "$NUM_PARALLEL_VAR" "$OLLAMA_ADVANCED_CONF")
    local current_models_dir=$(get_env_var "$OLLAMA_MODELS_VAR" "$OLLAMA_ADVANCED_CONF")

    if [[ "$current_kv_type" != "$p_kv_type" || \
          "$current_flash" != "$p_flash" || \
          "$current_context" != "$p_context" || \
          "$current_parallel" != "$p_parallel" || \
          "$current_models_dir" != "$p_models_dir" ]]; then
        ensure_root "Root privileges are required to modify systemd configuration."
        printInfoMsg "Applying advanced configuration..."
        _write_advanced_config "$p_kv_type" "$p_flash" "$p_context" "$p_parallel" "$p_models_dir"
        any_change_made=true
    fi

    finalize_changes "$any_change_made" "true" "false"
}

_main_logic() {
    prereq_checks "sudo" "systemctl" "grep" "sed" "awk"

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

    # For non-interactive mode, we also stage changes.
    # Initialize pending state from current state.
    local pending_network_status pending_kv_type pending_flash_attention
    local pending_context_length pending_num_parallel pending_models_dir

    if check_network_exposure; then pending_network_status="network"; else pending_network_status="localhost"; fi
    pending_kv_type=$(get_env_var "$KV_CACHE_VAR" "$OLLAMA_ADVANCED_CONF")
    pending_flash_attention=$(get_env_var "OLLAMA_FLASH_ATTENTION" "$OLLAMA_ADVANCED_CONF")
    pending_context_length=$(get_env_var "$CONTEXT_LENGTH_VAR" "$OLLAMA_ADVANCED_CONF")
    pending_num_parallel=$(get_env_var "$NUM_PARALLEL_VAR" "$OLLAMA_ADVANCED_CONF")
    pending_models_dir=$(get_env_var "$OLLAMA_MODELS_VAR" "$OLLAMA_ADVANCED_CONF")


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
                pending_network_status="network"
                shift
                ;;
            -r|--restrict)
                pending_network_status="localhost"
                shift
                ;;
            --kv-cache)
                if [[ -z "$2" || "$2" =~ ^- ]]; then printErrMsg "Error: '$1' requires a value (e.g., q8_0, f16)." >&2; return 1; fi
                pending_kv_type="$2"
                pending_flash_attention="1"
                shift 2
                ;;
            --context-length)
                if [[ -z "$2" || ! "$2" =~ ^[0-9]+$ ]]; then printErrMsg "Error: '$1' requires a numeric value." >&2; return 1; fi
                pending_context_length="$2"
                shift 2
                ;;
            --num-parallel)
                if [[ -z "$2" || ! "$2" =~ ^[0-9]+$ ]]; then printErrMsg "Error: '$1' requires a numeric value." >&2; return 1; fi
                pending_num_parallel="$2"
                shift 2
                ;;
            --models-dir)
                if [[ -z "$2" || "$2" =~ ^- ]]; then printErrMsg "Error: '$1' requires a path." >&2; return 1; fi
                local models_path="$2"
                models_path="${models_path/#\~/$HOME}" # Expand tilde
                if [[ "$models_path" != /* ]]; then printErrMsg "Error: Path for '$1' must be absolute." >&2; return 1; fi
                pending_models_dir="$models_path"
                shift 2
                ;;
            --reset-advanced)
                pending_kv_type=""
                pending_flash_attention=""
                pending_context_length=""
                pending_num_parallel=""
                pending_models_dir=""
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

    apply_staged_changes "$pending_network_status" "$pending_kv_type" "$pending_flash_attention" "$pending_context_length" "$pending_num_parallel" "$pending_models_dir"
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
            printOkMsg "No changes to save. Goodbye!"
        else
            printInfoMsg "No changes were made to the configuration."
        fi
        return
    fi

    local should_restart=false
    # Reload systemd daemon to pick up file changes before restarting.
    printInfoMsg "Reloading systemd daemon..."
    sudo systemctl daemon-reload

    if [[ "$is_interactive" == "true" ]]; then
        printInfoMsg "You must restart the Ollama service for the new settings to apply."
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
    initialize_test_suite "$@"

    # --- Mock Dependencies ---
    # Mock all functions with external dependencies or that modify system state.
    ensure_root() { :; }
    prereq_checks() { :; }
    finalize_changes() { MOCK_FINALIZE_CALLED_WITH_RESTART="$3"; }
    print_all_status() { MOCK_STATUS_CALLED=true; }
    expose_to_network() { MOCK_EXPOSE_CALLED=true; return "${MOCK_CHANGE_EXIT_CODE:-0}"; }
    restrict_to_localhost() { MOCK_RESTRICT_CALLED=true; return "${MOCK_CHANGE_EXIT_CODE:-0}"; }
    reset_all_advanced_settings() { MOCK_RESET_CALLED=true; return "${MOCK_CHANGE_EXIT_CODE:-0}"; }
    apply_staged_changes() { MOCK_APPLY_CALLED=true; }

    export -f ensure_root prereq_checks finalize_changes print_all_status \
               expose_to_network restrict_to_localhost reset_all_advanced_settings apply_staged_changes

    # --- Test Cases ---

    # Helper to reset mock state before each test section
    reset_mocks() {
        MOCK_FINALIZE_CALLED_WITH_RESTART=""
        MOCK_STATUS_CALLED=false
        MOCK_EXPOSE_CALLED=false
        MOCK_RESTRICT_CALLED=false
        MOCK_RESET_CALLED=false
        MOCK_APPLY_CALLED=false
    }

    printTestSectionHeader "Testing --status flag"
    reset_mocks
    _main_logic --status &>/dev/null
    _run_string_test "$MOCK_STATUS_CALLED" "true" "Calls print_all_status"

    printTestSectionHeader "Testing flag parsing and application"
    reset_mocks
    _main_logic --expose --context-length 8192 &>/dev/null
    _run_string_test "$MOCK_APPLY_CALLED" "true" "Calls apply_staged_changes for non-interactive flags"

    _run_test '_main_logic --kv-cache &>/dev/null' 1 "--kv-cache fails without a value"
    _run_test '_main_logic --context-length abc &>/dev/null' 1 "--context-length fails with non-numeric value"
    _run_test '_main_logic --models-dir relative/path &>/dev/null' 1 "--models-dir fails with relative path"

    _run_test '_main_logic --invalid-flag &>/dev/null' 1 "Handles an invalid flag"

    print_test_summary "ensure_root" "prereq_checks" "finalize_changes" "print_all_status" \
        "expose_to_network" "restrict_to_localhost" "reset_all_advanced_settings" \
        "apply_staged_changes"
}
# --- Run ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
