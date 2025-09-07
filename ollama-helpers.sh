#!/bin/bash
#
# ollama-helpers.sh
#
# This library contains functions specific to installing, configuring,
# and interacting with the Ollama service and its API.
#
# It should be sourced by any script that needs to manage Ollama,
# after sourcing the main 'shared.sh' library.
#

# --- Ollama Service Helpers ---
# Variable to cache result of install check.
# Unset by default, can be "true" or "false" after the first run.
_OLLAMA_IS_INSTALLED=""

# Checks if ollama.service is known to systemd
_is_ollama_service_known() {
    # 'systemctl cat' is a direct way to check if a service exists
    # It will return a non-zero exit code if the service doesn't exist.
    # We redirect stdout and stderr to /dev/null to suppress all output.
    if systemctl cat ollama.service &>/dev/null; then
        return 0 # Found
    else
        return 1 # Not found
    fi
}

# Public-facing check if 'ollama.service' systemd service exists.
# Returns 0 if it exists, 1 otherwise.
check_ollama_systemd_service_exists() {
    check_systemd_service_exists "ollama.service"
}

# Checks if the Ollama CLI is installed and exits if it's not.
# Usage: check_ollama_installed [--silent]
#   --silent: If provided, success message will be cleared instead of printed.
check_ollama_installed() {
    local silent=false
    if [[ "$1" == "--silent" ]]; then
        silent=true
    fi

    # 1. Check only if status is not already cached
    if [[ -z "${_OLLAMA_IS_INSTALLED:-}" ]]; then
        if _check_command_exists "ollama"; then
            _OLLAMA_IS_INSTALLED="true"
        else
            _OLLAMA_IS_INSTALLED="false"
        fi
    fi

    # 2. Print messages and act based on cached status
    printMsgNoNewline "${T_INFO_ICON} Checking for Ollama installation... " >&2
    if [[ "${_OLLAMA_IS_INSTALLED}" == "true" ]]; then
        if $silent; then
            clear_current_line >&2
        else
            clear_current_line >&2
            printOkMsg "Ollama is ${T_BOLD}${C_GREEN}installed${T_RESET}" >&2
        fi
        return 0 # Success
    else
        echo >&2 # Newline before error message
        printErrMsg "Ollama is not installed." >&2
        printMsg "    ${T_INFO_ICON} Please run ${C_L_BLUE}./install-ollama.sh${T_RESET} to install it." >&2
        exit 1
    fi
}

# Waits for Ollama systemd service to become known, with retries.
# Useful when running script immediately after install.
# Exits if the service is not found after a few seconds.
wait_for_ollama_service() {
    if ! _is_systemd_system; then
        printMsg "${T_INFO_ICON} Not a systemd system. Skipping service discovery."
        return
    fi

    printMsgNoNewline "${T_INFO_ICON} Looking for Ollama service"
    local ollama_found=false
    for i in {1..5}; do
        printMsgNoNewline "${C_L_BLUE}.${T_RESET}"
        if _is_ollama_service_known; then
            ollama_found=true
            break
        fi
        sleep 1
    done

    echo # Newline after the dots

    if ! $ollama_found; then
        printErrMsg "Ollama service not found after 5 attempts. Please install it first with ./install-ollama.sh"
        exit 1
    fi

    clear_lines_up 1
    #printOkMsg "Ollama service found"

    # After finding the service, ensure it's running.
    if ! systemctl is-active --quiet ollama.service; then
        local current_state
        # Get the state (e.g., "inactive", "failed"). This command has a non-zero
        # exit code when not active, so `|| true` is needed to prevent `set -e` from exiting.
        current_state=$(systemctl is-active ollama.service || true)
        printMsg "    ${T_INFO_ICON} Service is not active (currently ${C_L_YELLOW}${current_state}${T_RESET}). Attempting to start it..."
        # This requires sudo. The calling script should either be run with sudo
        # or the user will be prompted for a password.
        if ! sudo systemctl start ollama.service; then
            show_logs_and_exit "Failed to start Ollama service."
        fi
        printMsg "    ${T_OK_ICON} Service started successfully."
    fi
}

# Verifies that the Ollama API is responsive, with a spinner. Exits on failure.
# This is useful as a precondition check in scripts that need to use the API.
verify_ollama_api_responsive() {
    local ollama_port=${OLLAMA_PORT:-11434}
    local ollama_url="http://localhost:${ollama_port}"

    # poll_service shows its own spinner and success message.
    # It returns 1 on timeout without printing an error, so we handle that here.
    if ! poll_service "$ollama_url" "Ollama API"; then
        # Only show systemd logs if we know it's a systemd failure.
        if _is_systemd_system && _is_ollama_service_known; then
            show_logs_and_exit "Ollama service is active, but the API is not responding at ${ollama_url}."
        else
            printErrMsg "Ollama API is not responding at ${ollama_url}."
            printMsg "    ${T_INFO_ICON} Please ensure Ollama is installed and running."
            exit 1
        fi
    fi
}

# Verifies that Ollama service is running and responsive.
verify_ollama_service() {
    printMsg "${T_INFO_ICON} Verifying Ollama service status..."

    if ! _is_systemd_system; then
        printMsg "    ${T_INFO_ICON} Not a systemd system, skipping check."
    elif ! _is_ollama_service_known; then
        printMsg "    ${T_INFO_ICON} Ollama service not found, skipping service check."
    else
        # Systemd enabled and service exists
        if ! systemctl is-active --quiet ollama.service; then
            show_logs_and_exit "Systemd reports Ollama service NOT active"
        fi
        clear_lines_up 1
        printMsg "${T_OK_ICON} Systemd Ollama service is ${C_L_GREEN}active${T_RESET}"
    fi

    # Regardless of systemd status, we check if the API is responsive.
    verify_ollama_api_responsive
}

# Fetches raw JSON of installed models from Ollama API.
# The JSON is printed to stdout. It performs basic validation on the response.
# Returns 1 on any failure (e.g., API down, invalid JSON).
# Does NOT print error messages, allowing the caller to handle errors.
# Usage:
#   local models_json
#   if ! models_json=$(get_ollama_models_json); then
#       printErrMsg "Failed to get models."
#       return 1
#   fi
get_ollama_models_json() {
    local ollama_port=${OLLAMA_PORT:-11434}
    local ollama_url="http://localhost:${ollama_port}"
    local models_json=""

    if ! models_json=$(curl --silent --fail --max-time 10 "${ollama_url}/api/tags"); then
        return 1
    fi

    # Check if response is valid JSON and contains 'models' key
    if ! echo "$models_json" | jq -e '.models' > /dev/null; then
        return 1
    fi

    echo "$models_json"
}

# Parses model JSON from Ollama API and returns a tab-separated list of
# model details, sorted by name.
# Expects the full JSON string as first argument.
# Returns an empty string if JSON is invalid or contains no models.
# Output format: name\tsize_gb\tmodified_date
_parse_models_to_tsv() {
    local models_json="$1"

    # 1. Validate that input is valid JSON and has .models array.
    # The -e flag makes jq exit with a non-zero status if the filter produces `false` or `null`.
    if ! echo "$models_json" | jq -e '.models | (type == "array")' > /dev/null 2>&1; then
        # Invalid JSON or .models is not an array. Return empty.
        echo ""
        return
    fi

    # 2. This jq filter sorts models by name, then extracts name, size (converted to GB
    # and rounded to 2 decimal places), and date part of modified timestamp.
    # The output is tab-separated to handle model names that might contain spaces.
    echo "$models_json" | jq -r '.models | sort_by(.name)[] | "\(.name)\t\(.size / 1e9 | (. * 100 | floor) / 100)\t\(.modified_at | .[:10])"'
}

# Prints formatted table of models with details from API JSON.
# Expects full JSON string as first argument.
# Handles invalid/malformed JSON and empty model lists gracefully.
# Usage: print_ollama_models_table "$models_json"
print_ollama_models_table() {
    local models_json="$1"

    # 1. Check if input is valid JSON with a .models array.
    # This prevents misleading "no models" messages for malformed data.
    if ! echo "$models_json" | jq -e '.models | (type == "array")' > /dev/null 2>&1; then
        printErrMsg "Received invalid or malformed model data."
        return 1
    fi

    # 2. Parse JSON into a processable format (TSV)
    local models_tsv
    models_tsv=$(_parse_models_to_tsv "$models_json")

    # 3. Check if there are any models
    if [[ -z "$models_tsv" ]]; then
        printWarnMsg "No local models found."
        return 0
    fi

    # --- Build TSV with header and colors ---
    local full_tsv=""
    # Header
    full_tsv+="#\tNAME\tSIZE\tMODIFIED\n"

    # Body
    local i=1
    # iterate over TSV data
    while IFS=$'\t' read -r name size_gb modified; do
        # Determine background color for size
        # < 3GB: Green (Small), 3-6GB: Blue (Medium), 6-9GB: Yellow (Large), >= 9GB: Red (Extra Large)
        local size_bg_color="${C_GREEN}" # Default to Small
        local size_gb_int=${size_gb%.*}

        if [[ "$size_gb_int" -ge 9 ]]; then size_bg_color="${C_RED}";        # Extra Large
        elif [[ "$size_gb_int" -ge 6 ]]; then size_bg_color="${C_YELLOW}";   # Large
        elif [[ "$size_gb_int" -ge 3 ]]; then size_bg_color="${C_BLUE}";     # Medium
        fi

        local colored_name="${C_L_CYAN}${name}${T_RESET}"
        local colored_size="${T_BOLD}${size_bg_color}${size_gb} GB${T_RESET}"
        local colored_modified="${C_MAGENTA}${modified}${T_RESET}"

        full_tsv+="${i}\t${colored_name}\t${colored_size}\t${colored_modified}\n"
        ((i++))
    done <<< "$models_tsv" # Use a "here string" for cleaner input to loop

    # --- Print table ---
    # First, format the entire table in memory to get consistent column widths.
    local formatted_table
    formatted_table=$(echo -e "${full_tsv}" | format_tsv_as_table "  " "1 3")

    # Then, split the formatted output into header and body to insert a divider.
    local formatted_header
    formatted_header=$(echo "$formatted_table" | head -n 1)
    local formatted_body
    formatted_body=$(echo "$formatted_table" | tail -n +2)

    printMsg "${formatted_header}"
    printMsg "${C_BLUE}${DIV}${T_RESET}"
    printMsgNoNewline "${formatted_body}"
    printMsg "${C_BLUE}${DIV}${T_RESET}"
}

# Fetches model list from Ollama API and returns JSON.
# Usage:
#   if models_json=$(fetch_models_with_spinner "Fetching list..."); then
#       # use models_json
#   fi
# Arguments:
#   $1 - The description to show in the spinner.
# Returns:
#   JSON string on success. Returns with exit code 1 on failure.
fetch_models_with_spinner() {
    local desc="$1"
    if run_with_spinner "$desc" get_ollama_models_json; then
        echo "$SPINNER_OUTPUT"
    else
        return 1 # Spinner prints a generic error.
    fi
}

# Fetches and displays a formatted table of all installed Ollama models.
# Handles all prerequisite checks and user feedback.
# This is intended for non-interactive use where the full process is needed at once.
# Usage: display_installed_models
display_installed_models() {
    printBanner "Installed Ollama Models"

    # 1. Check prerequisites, these exit on failure
    check_jq_installed --silent
    verify_ollama_api_responsive

    # 2. Fetch model data
    local models_json
    if ! models_json=$(fetch_models_with_spinner "Fetching model list..."); then
        printInfoMsg "Could not retrieve model list from Ollama API"
        return 1
    fi

    clear_lines_up 1 # remove "Fetching model..."

    # 3. Display table
    print_ollama_models_table "$models_json"
}

# (Private) The core logic of pulling a model, after the name is known.
# This function is not interactive.
# Usage: _execute_pull <model_name>
_execute_pull() {
    local model_name="$1"
    printInfoMsg "Starting to pull model: ${C_L_BLUE}${model_name}${T_RESET}"
    printMsg "This may take a while depending on the model size and your network speed..."

    # Use ollama pull for its nice progress bar output.
    # The command streams progress, so we can't use the spinner.
    if ollama pull "$model_name"; then
        printOkMsg "Successfully pulled model: ${C_L_BLUE}${model_name}${T_RESET}"
        return 0
    else
        printErrMsg "Failed to pull model: ${C_L_BLUE}${model_name}${T_RESET}"
        printInfoMsg "Please check the model name and your network connection."
        return 1
    fi
}

# --- Model Management Actions ---

# Pulls a new model from the Ollama registry.
# This function is interactive and will prompt for a model name if not provided.
# Usage: pull_model [model_name]
pull_model() {
    local model_name="$1"

    # 1. If no model name is passed as an argument, prompt the user.
    if [[ -z "$model_name" ]]; then
        read -r -p "$(echo -e "${T_QST_ICON} Name of model to pull (e.g., llama3): ")" model_name
        if [[ -z "$model_name" ]]; then
            printErrMsg "No model name entered. Aborting."
            return 1
        fi
    fi

    _execute_pull "$model_name"
}

# (Private) Performs the actual 'ollama pull' for a list of models.
# This is a helper for the interactive manager and non-interactive flags.
# Usage: _perform_model_updates "model1" "model2" ...
_perform_model_updates() {
    local models_to_update=("$@")

    if [[ ${#models_to_update[@]} -eq 0 ]]; then
        printWarnMsg "No models specified for update."
        return 0
    fi

    printInfoMsg "The following models will be updated: ${C_L_BLUE}${models_to_update[*]}${T_RESET}"
    if ! prompt_yes_no "Are you sure you want to update these ${#models_to_update[@]} model(s)?" "n"; then
        printInfoMsg "Update cancelled."
        return 2 # 2 means user cancelled, no state change
    fi

    local -a failed_model_names=()
    for model_name in "${models_to_update[@]}"; do
        printMsg "\n${C_BLUE}${DIV}${T_RESET}"
        printInfoMsg "Updating model: ${C_L_BLUE}${model_name}${T_RESET}"
        if ! ollama pull "$model_name"; then
            printErrMsg "Failed to update model: ${C_L_BLUE}${model_name}${T_RESET}"
            failed_model_names+=("$model_name")
        fi
    done
    printMsg "${C_BLUE}${DIV}${T_RESET}"

    if [[ ${#failed_model_names[@]} -gt 0 ]]; then
        local failed_count=${#failed_model_names[@]}
        printWarnMsg "Finished updating, but ${failed_count} model(s) failed to update."
        printMsg "    ${T_ERR_ICON} Failed models: ${C_L_RED}${failed_model_names[*]}${T_RESET}"
        return 1
    else
        printOkMsg "Finished updating models successfully."
        return 0
    fi
}

# (Private) Performs the actual 'ollama rm' for a list of models.
# This is a raw helper that does not prompt; the caller is responsible for confirmation.
# Usage: _perform_model_deletions "model1" "model2" ...
_perform_model_deletions() {
    local models_to_delete=("$@")
    local ollama_port=${OLLAMA_PORT:-11434}
    local delete_url="http://localhost:${ollama_port}/api/delete"

    if [[ ${#models_to_delete[@]} -eq 0 ]]; then
        printWarnMsg "No models specified for deletion."
        return 0
    fi

    local -a failed_model_names=()
    for model_name in "${models_to_delete[@]}"; do
        printMsg "\n${C_BLUE}${DIV}${T_RESET}"
        local payload; payload=$(jq -n --arg name "$model_name" '{name: $name}')
        local desc="Deleting model ${C_L_RED}${model_name}${T_RESET}"
        if ! run_with_spinner "${desc}" curl --silent --show-error --fail -X DELETE -d "$payload" "$delete_url"; then
            failed_model_names+=("$model_name")
        fi
    done
    printMsg "${C_BLUE}${DIV}${T_RESET}"

    if [[ ${#failed_model_names[@]} -gt 0 ]]; then
        printWarnMsg "Finished deleting, but ${#failed_model_names[@]} model(s) failed."
        printMsg "    ${T_ERR_ICON} Failed models: ${C_L_RED}${failed_model_names[*]}${T_RESET}"
        return 1
    else
        printOkMsg "Finished deleting models successfully."
        return 0
    fi
}

# The core of the interactive model management UI.
# This function provides a full-screen, list-based interface where users can
# navigate, select, and perform actions (pull, delete, update) on models.
# It encapsulates the entire interactive session.
#
# ## Usage:
#   interactive_model_manager "$models_json"
#
# ## Arguments:
#  $1 - The initial JSON string of models from the Ollama API.
#
interactive_model_manager() {
    local models_json="$1"

    # --- State Variables ---
    local -a model_names model_sizes model_dates formatted_sizes bg_colors
    local -a selected_options=()
    local current_option=0
    local num_options=0

    # --- Helper: Parse model data ---
    # Repopulates all model-related arrays from a JSON string.
    _parse_model_data() {
        local json_data="$1"
        # Clear old data
        model_names=()
        model_sizes=()
        model_dates=()
        formatted_sizes=()
        bg_colors=()

        # Use the existing helper to parse the data into our local arrays
        if ! _parse_model_data_for_menu "$json_data" "false" model_names \
            model_sizes model_dates formatted_sizes bg_colors; then
            num_options=0
            return 1 # No models found
        fi

        num_options=${#model_names[@]}
        # Reset selections
        selected_options=()
        for ((i=0; i<num_options; i++)); do selected_options[i]=0; done
        # Ensure current_option is within bounds
        if (( current_option >= num_options )); then
            current_option=$(( num_options > 0 ? num_options - 1 : 0 ))
        fi
        return 0
    }

    # --- Helper: Redraw the entire screen ---
    _redraw_screen() {
        clear
        printBanner "Ollama Interactive Model Manager"
        if [[ $num_options -eq 0 ]]; then
            printWarnMsg "No local models found."
        else
            # Use the existing table renderer, but in multi-select mode to show checkboxes
            _render_model_list_table "Local Models" "multi" "$current_option" \
                model_names model_dates formatted_sizes bg_colors selected_options
        fi

        # Custom help footer for this manager
        local help_nav="  ${C_L_GRAY}Navigation:${T_RESET} ${C_L_MAGENTA}↑↓${C_WHITE} Move | ${C_L_MAGENTA}SPACE${C_WHITE} Select | ${C_L_YELLOW}(Q)uit${T_RESET}"
        local help_actions="  ${C_L_GRAY}Actions:${T_RESET}    ${C_L_GREEN}(N)ew Model${C_WHITE} | ${C_L_RED}(D)elete${C_WHITE} | ${C_MAGENTA}(U)pdate/Pull${T_RESET}"
        printMsg "${help_nav}"
        printMsg "${help_actions}"
        printMsg "${C_BLUE}${DIV}${T_RESET}"
    }

    # --- Helper: A special version of pull_model for this UI ---
    # This function replaces the help text with a prompt, avoiding a full screen clear.
    _interactive_pull_model_inline() {
        # The help text is 3 lines tall.
        # We move the cursor up and clear from there to the end of the screen.
        move_cursor_up 3
        tput ed

        local model_name=""
        local prompt_str=" ${T_QST_ICON} Name of model to pull (e.g., llama3): "
        printMsgNoNewline "$prompt_str"

        # Show cursor for input
        tput cnorm

        local key
        local cancelled=false
        while true; do
            key=$(read_single_char </dev/tty)

            if [[ "$key" == "$KEY_ENTER" ]]; then
                break
            elif [[ "$key" == "$KEY_ESC" ]]; then
                cancelled=true
                break
            elif [[ "$key" == "$KEY_BACKSPACE" ]]; then
                if [[ -n "$model_name" ]]; then
                    # Remove last character from variable
                    model_name=${model_name%?}
                    # Move cursor left, print space, move cursor left again
                    echo -ne "\b \b"
                fi
            else
                # Append printable characters. Filter out control sequences.
                if [[ ${#key} -eq 1 ]]; then
                    model_name+="$key"
                    echo -n "$key"
                fi
            fi
        done

        # Hide cursor again for the pull process
        tput civis

        # After loop, the cursor is on the same line. Add a newline for spacing.
        echo
        printMsg "${C_BLUE}${DIV}${T_RESET}"

        # Now, clean up the prompt area before the real pull starts.
        move_cursor_up 2 # Move up past the DIV and the prompt line.
        tput ed # Clear it all.

        if [[ "$cancelled" == "true" || -z "$model_name" ]]; then
            printWarnMsg "No model name entered or pull cancelled. No action taken."
            sleep 1.5
            return 1 # Indicates no action was taken
        fi

        # Call the core pull logic. It will print its own status messages.
        if ! _execute_pull "$model_name"; then
            read -n 1 -s -r -p "$(echo -e "\n${T_INFO_ICON} Press any key to continue...")"
        fi
        return 0 # Indicates an action was attempted.
    }

    # --- Helper: Refresh model data from API ---
    _refresh_models() {
        local new_json
        if new_json=$(fetch_models_with_spinner "Refreshing model list..."); then
            models_json="$new_json"
            _parse_model_data "$models_json"
        else
            # On failure, pause so user can see the error from the spinner
            read -n 1 -s -r -p "$(echo -e "\n${T_INFO_ICON} Press any key to continue...")"
        fi
    }

    # --- Initial Setup ---
    _parse_model_data "$models_json"

    # --- Main Interactive Loop ---
    tput civis
    trap 'tput cnorm; script_interrupt_handler' INT TERM

    while true; do
        _redraw_screen

        local key
        key=$(read_single_char </dev/tty)

        case "$key" in
            "$KEY_UP"|"k")
                if (( num_options > 0 )); then
                    current_option=$(( (current_option - 1 + num_options) % num_options ))
                fi
                ;;
            "$KEY_DOWN"|"j")
                if (( num_options > 0 )); then
                    current_option=$(( (current_option + 1) % num_options ))
                fi
                ;;
            ' ')
                if (( num_options > 0 )); then
                    selected_options[current_option]=$(( 1 - selected_options[current_option] ))
                fi
                ;;
            'n'|'N')
                _interactive_pull_model_inline
                _refresh_models
                ;;
            'd'|'D')
                local -a to_delete=()
                for i in "${!selected_options[@]}"; do
                    if [[ ${selected_options[i]} -eq 1 ]]; then
                        to_delete+=("${model_names[i]}")
                    fi
                done
                # If no models are selected via checkbox, use the currently highlighted one.
                if [[ ${#to_delete[@]} -eq 0 && $num_options -gt 0 ]]; then
                    to_delete=("${model_names[current_option]}")
                fi

                if [[ ${#to_delete[@]} -gt 0 ]]; then
                    clear
                    printInfoMsg "The following models will be deleted: ${C_L_RED}${to_delete[*]}${T_RESET}"
                    if prompt_yes_no "Are you sure you want to delete these ${#to_delete[@]} models?" "n"; then
                        _perform_model_deletions "${to_delete[@]}"
                        _refresh_models
                    fi
                else
                    printWarnMsg "No models to delete." && sleep 1
                fi
                ;;            
            'u'|'U'|'p'|'P')
                local -a to_update=()
                for i in "${!selected_options[@]}"; do
                    if [[ ${selected_options[i]} -eq 1 ]]; then
                        to_update+=("${model_names[i]}")
                    fi
                done
                if [[ ${#to_update[@]} -eq 0 && $num_options -gt 0 ]]; then
                    to_update=("${model_names[current_option]}")
                fi

                if [[ ${#to_update[@]} -gt 0 ]]; then
                    clear
                    # The update function has its own prompt, so we call it directly.
                    _perform_model_updates "${to_update[@]}"
                    _refresh_models
                else
                    printWarnMsg "No models to update." && sleep 1
                fi
                ;;
            'q'|'Q'|"$KEY_ESC")
                break
                ;;
        esac
    done

    # --- Cleanup ---
    tput cnorm
    trap - INT TERM
    clear
    printOkMsg "Exited Model Manager."
}

# --- Interactive Model Helpers ---

# Private helper to parse model JSON for interactive menus.
# Populates the provided nameref arrays.
# Usage: _parse_model_data_for_menu "$models_json" "$with_all" names_ref sizes_ref dates_ref formatted_sizes_ref bg_colors_ref
_parse_model_data_for_menu() {
    local models_json="$1"
    local with_all_option="$2"
    local -n names_ref="$3"
    local -n sizes_ref="$4"
    local -n dates_ref="$5"
    local -n formatted_sizes_ref="$6"
    local -n bg_colors_ref="$7"
    
    # Parse models into arrays. Sorting is done by jq.
    mapfile -t names_ref < <(echo "$models_json" | jq -r '.models | sort_by(.name)[] | .name')
    mapfile -t sizes_ref < <(echo "$models_json" | jq -r '.models | sort_by(.name)[] | .size')
    mapfile -t dates_ref < <(echo "$models_json" | jq -r '.models | sort_by(.name)[] | .modified_at | .[:10]')

    # Pre-calculate formatted sizes and colors to avoid doing it in the render loop
    for size_bytes in "${sizes_ref[@]}"; do
        local size_gb; size_gb=$(awk -v size="$size_bytes" 'BEGIN { printf "%.2f GB", size / 1e9 }')
        formatted_sizes_ref+=("$size_gb")
        local size_gb_int=${size_gb%.*}
        if [[ "$size_gb_int" -ge 9 ]]; then bg_colors_ref+=("${C_RED}");
        elif [[ "$size_gb_int" -ge 6 ]]; then bg_colors_ref+=("${C_YELLOW}");
        elif [[ "$size_gb_int" -ge 3 ]]; then bg_colors_ref+=("${C_BLUE}");
        else bg_colors_ref+=("${C_GREEN}"); fi
    done

    if [[ ${#names_ref[@]} -eq 0 ]]; then
        return 1
    fi

    # Add "All" option if requested
    if [[ "$with_all_option" == "true" ]]; then
        names_ref=("All" "${names_ref[@]}")
        sizes_ref=("" "${sizes_ref[@]}")
        dates_ref=("" "${dates_ref[@]}")
        formatted_sizes_ref=("" "${formatted_sizes_ref[@]}")
        bg_colors_ref=("" "${bg_colors_ref[@]}")
    fi
    return 0
}

# Private helper to render the interactive model selection table.
# This is a pure display function that handles both single and multi-select modes.
# Usage: _render_model_list_table "Prompt" mode current_opt_idx names_ref dates_ref formatted_sizes_ref bg_colors_ref [selected_ref]
_render_model_list_table() {
    local prompt="$1"
    local mode="$2"
    local current_option="$3"
    local -n names_ref="$4"
    local -n dates_ref="$5"
    local -n formatted_sizes_ref="$6"
    local -n bg_colors_ref="$7"
    # The 'selected' array is only passed in multi-select mode.
    local -a _dummy_selected_ref=() # Dummy array for single-select mode
    local -n selected_ref="${8:-_dummy_selected_ref}"
    local output=""

    local with_all_option=false
    if [[ "$mode" == "multi" && "${names_ref[0]}" == "All" ]]; then
        with_all_option=true
    fi

    # --- Header ---
    # Adjust header padding based on mode
    local header_padding="%-1s"
    if [[ "$mode" == "multi" ]]; then header_padding="%-3s"; fi
    output+=$(printf " ${header_padding} %-40s %10s  %-15s" "" "NAME" "SIZE" "MODIFIED")
    output+="\n${C_BLUE}${DIV}${T_RESET}\n"

    # --- Body ---
    for i in "${!names_ref[@]}"; do
        local pointer=" "; local highlight_start=""; local highlight_end=""
        if [[ $i -eq $current_option ]]; then
            pointer="${T_BOLD}${C_L_MAGENTA}❯${T_RESET}"; highlight_start="${T_REVERSE}"; highlight_end="${T_RESET}";
        fi

        local line_prefix=""
        if [[ "$mode" == "multi" ]]; then
            local checkbox="[ ]"
            if [[ ${selected_ref[i]} -eq 1 ]]; then checkbox="${highlight_start}${C_GREEN}${T_BOLD}[✓]"; fi
            line_prefix=$(printf "%-3s " "${checkbox}")
        else
            line_prefix="  " # Two spaces for alignment with multi-select's pointer
        fi

        local line_body name modified formatted_size
        local size_format modified_format

        if [[ "$with_all_option" == "true" && $i -eq 0 ]]; then
            # handle the "All" entry
            name="${T_BOLD}${names_ref[i]}"
            modified=""
            formatted_size=""
            size_format="%10s"
            modified_format="%-15s${T_RESET}"
        else
            name="${names_ref[i]}"
            modified="${dates_ref[i]}"
            formatted_size="${formatted_sizes_ref[i]}"
            size_format="${bg_colors_ref[i]}%10s${T_RESET}"
            modified_format="${C_MAGENTA}%-15s${T_RESET}"
        fi
        line_body=$(printf "%-40s ${size_format}  ${modified_format}" "$name" "$formatted_size" "$modified")
        output+="${pointer}${line_prefix}${highlight_start}${line_body}${highlight_end}${T_CLEAR_LINE}\n"
    done

    # --- Table Footer ---
    output+="${C_BLUE}${DIV}${T_RESET}\n"

    # Final combined print
    echo -ne "$output" >/dev/tty
}

# Private helper to handle the logic of toggling an item in the multi-select menu.
# Modifies the selected_options array by reference.
# Usage: _handle_multi_select_toggle with_all_flag current_opt_idx num_options selected_arr_ref
_handle_multi_select_toggle() {
    local with_all_option="$1"
    local current_option="$2"
    local num_options="$3"
    local -n selected_ref="$4"

    # Toggle the current option
    selected_ref[current_option]=$(( 1 - selected_ref[current_option] ))

    # Handle "All" option logic
    if [[ "$with_all_option" == "true" ]]; then
        if [[ $current_option -eq 0 ]]; then
            # If "All" is toggled, set all other options to the same state
            local all_state=${selected_ref[0]}
            for ((j=1; j<num_options; j++)); do selected_ref[j]=$all_state; done
        else
            # If an individual item is toggled, check if all are now selected
            # to update the "All" checkbox state.
            local all_selected=1
            for ((j=1; j<num_options; j++)); do
                if [[ ${selected_ref[j]} -eq 0 ]]; then
                    all_selected=0
                    break
                fi
            done
            selected_ref[0]=$all_selected
        fi
    fi
}

# Private helper to process the final selections from the multi-select menu.
# Prints selected model names to stdout and returns an appropriate exit code.
# Usage: _process_multi_select_output with_all_flag names_arr_ref selected_arr_ref
_process_multi_select_output() {
    local with_all_option="$1"
    local -n names_ref="$2"
    local -n selected_ref="$3"
    local num_options=${#names_ref[@]}

    local has_selection=0
    # If "All" was an option and it was selected, output all model names.
    if [[ "$with_all_option" == "true" && ${selected_ref[0]} -eq 1 ]]; then
        for ((i=1; i<num_options; i++)); do
            echo "${names_ref[i]}"
        done
        has_selection=1
    else
        # Otherwise, iterate through the selections and output the chosen ones.
        local start_index=0
        if [[ "$with_all_option" == "true" ]]; then
            start_index=1 # Skip the "All" option itself
        fi
        for ((i=start_index; i<num_options; i++)); do
            if [[ ${selected_ref[i]} -eq 1 ]]; then
                has_selection=1
                echo "${names_ref[i]}"
            fi
        done
    fi

    if [[ $has_selection -eq 1 ]]; then return 0; else return 1; fi
}

# (Private) Generic interactive model list. Handles both single and multi-select.
# This is the new core function that consolidates the logic.
# Usage: _interactive_list_models <mode> <prompt> <models_json> [with_all_flag]
_interactive_list_models() {
    local mode="$1" # "single" or "multi"
    local prompt="$2"
    local models_json="$3"
    local with_all_option=false
    # The 'with_all' flag is only relevant for multi-select mode.
    if [[ "$mode" == "multi" && "$4" == "true" ]]; then
        with_all_option=true
    fi

    # 1. Parse model data from JSON into arrays
    local -a model_names model_sizes model_dates formatted_sizes bg_colors
    if ! _parse_model_data_for_menu "$models_json" "$with_all_option" model_names \
        model_sizes model_dates formatted_sizes bg_colors; then
        return 1 # No models found
    fi
    local num_options=${#model_names[@]}

    # 2. Initialize state
    local current_option=0
    local -a selected_options=()
    if [[ "$mode" == "multi" ]]; then
        for ((i=0; i<num_options; i++)); do selected_options[i]=0; done
    fi

    # --- Helper to print the footer for this menu ---
    _print_footer() {
        local help_text="  ${C_L_MAGENTA}↑↓${C_WHITE}(Move)"
        if [[ "$mode" == "multi" ]]; then
            help_text+=" | ${C_L_MAGENTA}SPACE${C_WHITE}(Select)"
        fi
        if [[ "$mode" == "multi" && "$with_all_option" == "true" ]]; then
            help_text+=" | ${C_L_GREEN}(A)ll${C_WHITE}(Toggle)"
        fi
        help_text+=" | ${C_L_MAGENTA}ENTER${C_WHITE}(Confirm) | ${C_L_YELLOW}Q/ESC${C_WHITE}(Cancel)${T_RESET}"
        
        # The table renderer already printed its bottom divider, which acts as our top divider.
        echo -e "${help_text}" >/dev/tty
        echo -e "${C_BLUE}${DIV}${T_RESET}" >/dev/tty
    }

    # 3. Set up interactive environment
    stty -echo
    printMsgNoNewline "${T_CURSOR_HIDE}" >/dev/tty
    trap 'printMsgNoNewline "${T_CURSOR_SHOW}" >/dev/tty; stty echo' EXIT

    # Calculate menu height for cursor control. It's the number of options plus the surrounding chrome.
    # Banner(1) + Header(1) + Div(1) + N lines + Div(1) + Help(1) + Div(1) = N + 6
    local menu_height=$((num_options + 7)) # Using 7 is safe for both banner types.
    printBanner "$prompt" >/dev/tty
    # The prompt argument to _render_model_list_table is now unused, but harmless to keep.
    _render_model_list_table "$prompt" "$mode" "$current_option" model_names model_dates formatted_sizes bg_colors selected_options
    _print_footer

    # 4. Main interactive loop
    local key
    while true; do
        key=$(read_single_char </dev/tty)
        local state_changed=false

        case "$key" in
            "$KEY_UP"|"k")
                current_option=$(( (current_option - 1 + num_options) % num_options ))
                state_changed=true
                ;;
            "$KEY_DOWN"|"j")
                current_option=$(( (current_option + 1) % num_options ))
                state_changed=true
                ;;
            ' '|"h"|"l")
                if [[ "$mode" == "multi" ]]; then
                    _handle_multi_select_toggle "$with_all_option" "$current_option" "$num_options" selected_options
                    state_changed=true
                fi
                ;;
            "a"|"A")
                if [[ "$mode" == "multi" && "$with_all_option" == "true" ]]; then
                    _handle_multi_select_toggle "$with_all_option" "0" "$num_options" selected_options
                    state_changed=true
                fi
                ;;
            "$KEY_ENTER")
                break # Exit loop to process selections
                ;;
            "$KEY_ESC"|"q")
                clear_lines_up "$menu_height" >/dev/tty
                return 1
                ;;
            *)
                continue # Ignore other keys and loop without redrawing
                ;;
        esac
        if [[ "$state_changed" == "true" ]]; then
            move_cursor_up "$menu_height" >/dev/tty
            printBanner "$prompt" >/dev/tty
            _render_model_list_table "$prompt" "$mode" "$current_option" model_names model_dates formatted_sizes bg_colors selected_options
            _print_footer
        fi
    done

    # 5. Clean up screen and process output
    clear_lines_up "$menu_height" >/dev/tty # This already uses ANSI codes

    if [[ "$mode" == "multi" ]]; then
        _process_multi_select_output "$with_all_option" model_names selected_options
        return $?
    else # single mode
        echo "${model_names[current_option]}"
        return 0
    fi
}

# Renders an interactive, multi-selectable table of Ollama models.
# It combines the display of `print_ollama_models_table` with the interactivity
# of `interactive_multi_select_menu`.
#
# ## Usage:
#   local menu_output
#   menu_output=$(interactive_multi_select_list_models "Select Models:" "$models_json" [--with-all])
#   local exit_code=$?
#
# ## Arguments:
#  $1 - The prompt to display to the user.
#  $2 - The JSON string of models from the Ollama API.
#  $3 - (Optional) "--with-all" to include a "Select All" option.
#
# ## Returns:
#  On success (Enter pressed with selections):
#    - Prints the names of the selected models to stdout, one per line.
#    - Returns with exit code 0.
#  On cancellation (ESC or q pressed) or no selection:
#    - Prints nothing to stdout.
#    - Returns with exit code 1.
interactive_multi_select_list_models() {
    if ! [[ -t 0 ]]; then
        printErrMsg "Not an interactive session." >&2
        return 1
    fi

    local prompt="$1"
    local models_json="$2"
    local with_all_option=false
    [[ "$3" == "--with-all" ]] && with_all_option=true

    # Call the new consolidated function
    _interactive_list_models "multi" "$prompt" "$models_json" "$with_all_option"
}

# Renders an interactive, single-selectable table of Ollama models.
#
# ## Usage:
#   local selected_model
#   selected_model=$(interactive_single_select_list_models "Select a model:" "$models_json")
#   local exit_code=$?
#
# ## Arguments:
#  $1 - The prompt to display to the user.
#  $2 - The JSON string of models from the Ollama API.
#
# ## Returns:
#  On success (Enter pressed):
#    - Prints the name of the selected model to stdout.
#    - Returns with exit code 0.
#  On cancellation (ESC or q pressed):
#    - Prints nothing to stdout.
#    - Returns with exit code 1.
interactive_single_select_list_models() {
    if ! [[ -t 0 ]]; then
        printErrMsg "Not an interactive session." >&2
        return 1
    fi

    local prompt="$1"
    local models_json="$2"

    # Call the new consolidated function
    _interactive_list_models "single" "$prompt" "$models_json"
}

# --- Ollama Network Configuration Helpers ---

# Checks if Ollama is exposed to network.
# Returns 0 if exposed, 1 if not
check_network_exposure() {
    local current_host_config
    # Query systemd for Environment variables for service.
    # Redirect stderr to hide "property not set" messages if override doesn't exist.
    current_host_config=$(systemctl show --no-pager --property=Environment ollama 2>/dev/null || echo "")
    if echo "$current_host_config" | grep -q "OLLAMA_HOST=0.0.0.0"; then
        return 0 # exposed
    else
        return 1 # NOT exposed
    fi
}

# (Private) Reloads systemd and restarts Ollama. Exits on failure.
# This is a common final step after changing systemd configuration.
# Usage: _reload_and_restart_ollama "description of action"
_reload_and_restart_ollama() {
    local action_description="$1" # e.g., "applying network override"
    printMsg "${T_INFO_ICON} Reloading systemd daemon and restarting Ollama service..."
    if ! sudo systemctl daemon-reload || ! sudo systemctl restart ollama; then
        show_logs_and_exit "Failed to restart Ollama service after ${action_description}."
    fi
}

# Applies systemd override to expose Ollama to network.
# Requires sudo to run commands.
# Returns:
#   0 - on successful change.
#   1 - on error creating override file.
#   2 - if no change was needed (already exposed).
expose_to_network() {
    if check_network_exposure; then
        printMsg "${T_INFO_ICON} No change needed."
        printMsg "${T_OK_ICON} Ollama is already ${C_L_YELLOW}EXPOSED to network${T_RESET} (listening on 0.0.0.0)."
        return 2 # no change was needed
    fi

    local override_dir="/etc/systemd/system/ollama.service.d"
    local override_file="${override_dir}/10-expose-network.conf"

    printMsg "${T_INFO_ICON} Creating systemd override to expose Ollama to network..."

    if ! sudo mkdir -p "$override_dir"; then
        printErrMsg "Failed to create override directory: $override_dir"
        return 1
    fi

    # Use a heredoc to safely write multi-line configuration file
    # The `<<-` strips leading tabs, allowing heredoc to be indented.
    if ! sudo tee "$override_file" >/dev/null <<-EOF
		[Service]
		Environment="OLLAMA_HOST=0.0.0.0"
	EOF
    then
        printErrMsg "Failed to write override file: $override_file"
        return 1
    fi

    _reload_and_restart_ollama "applying network override"
    printOkMsg "Ollama has been exposed to network and restarted."
    return 0
}

# Removes systemd override to restrict Ollama to localhost.
# Requires sudo to run commands.
# Returns:
#   0 - on successful change.
#   2 - if no change was needed (already restricted).
restrict_to_localhost() {
    if ! check_network_exposure; then
        printMsg "${T_INFO_ICON} No change needed."
        printMsg "${T_INFO_ICON} Ollama is already ${C_L_BLUE}RESTRICTED to localhost${T_RESET} (listening on 127.0.0.1)."
        return 2 # 2 means no change was needed
    fi

    local override_file="/etc/systemd/system/ollama.service.d/10-expose-network.conf"
    printMsg "${T_INFO_ICON} Removing systemd override to restrict Ollama to localhost..."

    if [[ ! -f "$override_file" ]]; then
        printMsg "${T_INFO_ICON} Override file not found. No changes needed."
    else
        sudo rm -f "$override_file"
    fi

    _reload_and_restart_ollama "removing network override"
    printOkMsg "Ollama has been restricted to localhost and was restarted."
    return 0
}

# --- GPU Helpers ---

# Prints a formatted summary of NVIDIA GPU status.
# Does nothing if nvidia-smi is not found.
# Usage: print_gpu_status [indent_prefix]
#   indent_prefix: Optional string to prepend to each output line (e.g., "  ").
print_gpu_status() {
    local indent="${1:-}"
    # Only run if nvidia-smi is available
    if ! _check_command_exists "nvidia-smi"; then
        return
    fi

    # Use a timeout to prevent the script from hanging if nvidia-smi is slow
    # nvidia-smi has a bug where querying driver_version and cuda_version can fail.
    # We'll get them separately for robustness.
    local driver_version cuda_version
    driver_version=$(timeout 5 nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits | head -n 1)
    cuda_version=$(timeout 5 nvidia-smi | grep -oP 'CUDA Version: \K[^ ]+' | head -n 1)

    printMsg "${indent}${T_INFO_ICON} Driver:   ${C_L_BLUE}${driver_version:-N/A}${T_RESET} (CUDA: ${C_L_BLUE}${cuda_version:-N/A}${T_RESET})"

    local smi_output
    smi_output=$(timeout 5 nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu,temperature.gpu --format=csv,noheader,nounits)

    if [[ -z "$smi_output" ]]; then
        printMsg "${indent}${T_ERR_ICON}${T_ERR} Could not retrieve GPU information from nvidia-smi.${T_RESET}"
        return
    fi

    # The query command will output one line per GPU. We'll process each one.
    local gpu_index=0
    while IFS=',' read -r gpu_name mem_used mem_total gpu_util temp_gpu; do
        # Trim leading/trailing whitespace that might sneak in
        gpu_name=$(echo "$gpu_name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        mem_used=$(echo "$mem_used" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        mem_total=$(echo "$mem_total" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        gpu_util=$(echo "$gpu_util" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        temp_gpu=$(echo "$temp_gpu" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

        printMsg "${indent}${T_OK_ICON} GPU ${gpu_index}:    ${C_L_CYAN}${gpu_name}${T_RESET}"
        printMsg "${indent}      - Memory: ${C_L_YELLOW}${mem_used} MiB / ${mem_total} MiB${T_RESET}"
        printMsg "${indent}      - Usage:  ${C_L_YELLOW}${gpu_util}%${T_RESET} (Temp: ${C_L_YELLOW}${temp_gpu}°C${T_RESET})"
        ((gpu_index++))
    done <<< "$smi_output"
}
