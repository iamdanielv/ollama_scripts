#!/bin/bash

# This library should be sourced by other scripts, not executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and should be sourced, not executed." >&2
    exit 1
fi

# Source the shared library, which in turn sources the TUI library.
# shellcheck source=./lib/shared.lib.sh
if ! source "$(dirname "${BASH_SOURCE[0]}")/shared.lib.sh"; then
    echo "Error: Could not source shared.lib.sh. Make sure it's in the 'src/lib' directory." >&2
    exit 1
fi

# --- Ollama API & Service Helpers ---

# Checks if the 'ollama' command is available.
# Usage: check_ollama_installed [--silent]
#   --silent: If provided, the success message will be cleared instead of printed.
check_ollama_installed() {
    local silent=false
    if [[ "$1" == "--silent" ]]; then
        silent=true
    fi

    printMsgNoNewline "${T_INFO_ICON} Checking for ollama... " >&2
    if ! _check_command_exists "ollama"; then
        echo >&2 # Newline before error message
        printErrMsg "'ollama' command not found. The Ollama CLI is required." >&2
        printMsg "    ${T_INFO_ICON} Please install it from ${C_L_BLUE}https://ollama.com${T_RESET} and ensure it's in your PATH." >&2
        exit 1
    fi

    if $silent; then
        clear_current_line >&2
    else
        printOkMsg "Ollama is installed." >&2
    fi
}

# Checks if ollama.service is known to systemd by calling the generic helper.
_is_ollama_service_known() {
    _is_systemd_service_known "ollama.service"
}

# Public-facing check if 'ollama.service' systemd service exists.
# Returns 0 if it exists, 1 otherwise.
check_ollama_systemd_service_exists() {
    if ! _is_systemd_system || ! _is_ollama_service_known; then
        return 1
    fi
    return 0
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
    if ! poll_service "$ollama_url" "Ollama API" 15; then
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

# Verifies that the Ollama API is responsive.
# It uses curl to ping the API endpoint.
# Exits with an error if the API is not reachable.
verify_ollama_api_responsive_simple() {
    printMsgNoNewline "${T_INFO_ICON} Checking Ollama API status... "
    # Use a short timeout to avoid long waits.
    # The -f flag makes curl fail with a non-zero exit code on server errors (4xx, 5xx).
    if ! curl --silent --fail --head --max-time 3 http://localhost:11434 &>/dev/null; then
        clear_current_line
        printErrMsg "Ollama API is not responsive."
        if check_systemd_service_exists "ollama.service"; then
            printMsg "    ${T_INFO_ICON} The 'ollama.service' exists. You can try starting it with:"
            printMsg "        ${C_L_BLUE}sudo systemctl start ollama.service${T_RESET}"
            show_logs_and_exit "    Service might be in a failed state. Check the logs for more details."
        else
            printMsg "    ${T_INFO_ICON} Please ensure the Ollama application is running."
            exit 1
        fi
    fi
    printOkMsg "Ollama API is responsive."
}

# Fetches the list of local models from the Ollama API in JSON format.
# The output is printed to stdout.
# Returns 0 on success, 1 on failure.
# Usage:
#   local models_json
#   if ! models_json=$(get_ollama_models_json); then
#       # Handle error
#   fi
get_ollama_models_json() {
    local models_json
    # The -f flag makes curl fail with a non-zero exit code on server errors.
    if ! models_json=$(curl --silent --fail http://localhost:11434/api/tags); then
        printErrMsg "Failed to fetch models from Ollama API."
        return 1
    fi
    echo "$models_json"
    return 0
}

# (Private) Parses model data from JSON into bash arrays for the menu.
# This function uses jq for robust JSON parsing.
# Arguments:
#   $1: The JSON string of models.
#   $2: A boolean string ("true" or "false") to include an "All" option.
#   $3-$8: Namerefs for the output arrays: names, sizes, dates, formatted_sizes, bg_colors, pre_rendered_lines.
# Returns 0 on success, 1 on failure.
_parse_model_data_for_menu() {
    local json_data="$1"
    local include_all="$2"
    local -n out_names="$3"
    local -n out_sizes="$4"
    local -n out_dates="$5"
    local -n out_f_sizes="$6"  # formatted sizes
    local -n out_colors="$7"   # colors
    local -n out_lines="$8"    # pre-rendered lines

    # Check if there are any models.
    if [[ $(echo "$json_data" | jq '.models | length') -eq 0 ]]; then
        return 1 # No models found
    fi

    # Use jq to extract and sort data. Sorting by name alphabetically.
    local sorted_json
    sorted_json=$(echo "$json_data" | jq -c '.models | sort_by(.name) | .[]')

    # Clear output arrays
    out_names=() out_sizes=() out_dates=() out_f_sizes=() out_colors=() out_lines=()

    if [[ "$include_all" == "true" ]]; then
        out_names+=("All")
        local all_line; all_line=$(_format_fixed_width_string " ${C_L_YELLOW}All Models${T_RESET}" 67)
        out_lines+=("$all_line")
    fi

    while IFS= read -r line; do
        local name size modified_at
        name=$(echo "$line" | jq -r '.name')
        size=$(echo "$line" | jq -r '.size')
        modified_at=$(echo "$line" | jq -r '.modified_at')

        # Format size to be human-readable (GB) and determine color
        local size_gb
        size_gb=$(awk -v s="$size" 'BEGIN { printf "%.2f", s / 1024 / 1024 / 1024 }')
        local size_gb_int=${size_gb%.*}
        local size_color="${C_L_GREEN}" # Default to Green for < 3GB

        if (( size_gb_int >= 9 )); then size_color="${C_L_RED}";      # >= 9GB: Red
        elif (( size_gb_int >= 6 )); then size_color="${C_L_YELLOW}"; # 6-9GB: Yellow
        elif (( size_gb_int >= 3 )); then size_color="${C_L_BLUE}";   # 3-6GB: Blue
        fi

        local formatted_size="${size_gb} GB"

        # Format date to be more friendly
        local formatted_date
        formatted_date=$(date -d "$(echo "$modified_at" | cut -d'T' -f1)" +"%Y-%m-%d")

        out_names+=("$name")
        out_sizes+=("$size")
        out_dates+=("$formatted_date")
        out_f_sizes+=("$formatted_size")
        out_colors+=("$size_color")

        # Pre-render the line for the menu
        local unformatted_line
        unformatted_line=$(printf " %-41s ${size_color}%10s ${T_RESET} ${C_MAGENTA} %-10s ${T_RESET}" "$name" "$formatted_size" "$formatted_date")
        # Perform the expensive fixed-width formatting here, once per refresh.
        out_lines+=("$(_format_fixed_width_string "$unformatted_line" 67)")

    done <<< "$sorted_json"

    return 0
}

# (Private) An optimized version of _parse_model_data_for_menu.
# This version avoids calling the expensive _format_fixed_width_string function.
# It manually truncates the model name and uses a carefully crafted printf
# statement to build the pre-rendered line, which is significantly faster.
# Arguments are the same as the original function.
_parse_model_data_for_menu_optimized() {
    local json_data="$1"
    local include_all="$2"
    local -n out_names="$3"
    local -n out_sizes="$4"
    local -n out_dates="$5"
    local -n out_f_sizes="$6"
    local -n out_colors="$7"
    local -n out_lines="$8"

    if [[ $(echo "$json_data" | jq '.models | length') -eq 0 ]]; then
        return 1
    fi

    local sorted_json
    sorted_json=$(echo "$json_data" | jq -c '.models | sort_by(.name) | .[]')

    out_names=() out_sizes=() out_dates=() out_f_sizes=() out_colors=() out_lines=()

    if [[ "$include_all" == "true" ]]; then
        out_names+=("All")
        # Manually format the "All" line to the correct width
        local all_line; all_line=$(printf " ${C_L_YELLOW}%-66s${T_RESET}" "All Models")
        out_lines+=("$all_line")
    fi

    while IFS= read -r line; do
        local name size modified_at
        name=$(echo "$line" | jq -r '.name')
        size=$(echo "$line" | jq -r '.size')
        modified_at=$(echo "$line" | jq -r '.modified_at')

        local size_gb; size_gb=$(awk -v s="$size" 'BEGIN { printf "%.2f", s / 1024 / 1024 / 1024 }')
        local size_gb_int=${size_gb%.*}; local size_color="${C_L_GREEN}"
        if (( size_gb_int >= 9 )); then size_color="${C_L_RED}"; elif (( size_gb_int >= 6 )); then size_color="${C_L_YELLOW}"; elif (( size_gb_int >= 3 )); then size_color="${C_L_BLUE}"; fi
        local formatted_size="${size_gb} GB"
        local formatted_date; formatted_date=$(date -d "$(echo "$modified_at" | cut -d'T' -f1)" +"%Y-%m-%d")

        out_names+=("$name"); out_sizes+=("$size"); out_dates+=("$formatted_date"); out_f_sizes+=("$formatted_size"); out_colors+=("$size_color")

        # Manually truncate the name to fit within the 41-character column.
        local truncated_name; truncated_name=$(printf "%.40s" "$name"); if [[ ${#name} -gt 40 ]]; then truncated_name+="…"; fi

        # Use a single, optimized printf call. No more _format_fixed_width_string.
        out_lines+=("$(printf " %-41s ${size_color}%10s ${T_RESET} ${C_MAGENTA} %-10s ${T_RESET}" "$truncated_name" "$formatted_size" "$formatted_date")")
    done <<< "$sorted_json"

    return 0
}

# --- Model Action Wrappers ---

# Executes 'ollama pull' for a given model.
# This is a simple wrapper to be used with run_menu_action.
# Arguments:
#   $1: The name of the model to pull.
_execute_pull() {
    local model_name="$1"
    printInfoMsg "Pulling model: ${C_L_BLUE}${model_name}${T_RESET}"
    printMsg "${C_BLUE}${DIV}${T_RESET}"
    ollama pull "$model_name"
    printMsg "${C_BLUE}${DIV}${T_RESET}"
    printOkMsg "Pull complete for ${C_L_BLUE}${model_name}${T_RESET}."
}

# Deletes one or more models.
# This is a wrapper for use with run_menu_action.
# Arguments:
#   $@: A list of model names to delete.
_perform_model_deletions() {
    local models_to_delete=("$@")
    local total=${#models_to_delete[@]}
    local current=0

    printInfoMsg "Deleting ${total} model(s)..."
    printMsg "${C_BLUE}${DIV}${T_RESET}"

    for model in "${models_to_delete[@]}"; do
        ((current++))
        printMsg "(${current}/${total}) Deleting ${C_L_RED}${model}${T_RESET}..."
        if ollama rm "$model"; then
            printOkMsg "Successfully deleted ${model}."
        else
            printErrMsg "Failed to delete ${model}."
        fi
    done
    printMsg "${C_BLUE}${DIV}${T_RESET}"
    printOkMsg "Delete process finished."
}

# Updates (pulls) one or more models.
# This is a wrapper for use with run_menu_action.
# Arguments:
#   $@: A list of model names to update.
_perform_model_updates() {
    local models_to_update=("$@")
    local total=${#models_to_update[@]}
    local current=0

    printInfoMsg "Updating ${total} model(s)..."
    printMsg "${C_BLUE}${DIV}${T_RESET}"

    for model in "${models_to_update[@]}"; do
        ((current++))
        printMsg "(${current}/${total}) Updating ${C_L_MAGENTA}${model}${T_RESET}..."
        # 'ollama pull' also works for updating
        ollama pull "$model"
    done

    printMsg "${C_BLUE}${DIV}${T_RESET}"
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
    if ! _check_command_exists "nvidia-smi"; then return; fi

    local driver_version; driver_version=$(timeout 5 nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits | head -n 1)
    local cuda_version; cuda_version=$(timeout 5 nvidia-smi | grep -oP 'CUDA Version: \K[^ ]+' | head -n 1)
    printMsg "${indent}${T_INFO_ICON} Driver:   ${C_L_BLUE}${driver_version:-N/A}${T_RESET} (CUDA: ${C_L_BLUE}${cuda_version:-N/A}${T_RESET})"

    local smi_output; smi_output=$(timeout 5 nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu,temperature.gpu --format=csv,noheader,nounits)
    if [[ -z "$smi_output" ]]; then printMsg "${indent}${T_ERR_ICON}${T_ERR} Could not retrieve GPU information from nvidia-smi.${T_RESET}"; return; fi

    local gpu_index=0
    while IFS=',' read -r gpu_name mem_used mem_total gpu_util temp_gpu; do
        gpu_name=$(echo "$gpu_name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'); mem_used=$(echo "$mem_used" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        mem_total=$(echo "$mem_total" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'); gpu_util=$(echo "$gpu_util" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        temp_gpu=$(echo "$temp_gpu" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        printMsg "${indent}${T_OK_ICON} GPU ${gpu_index}:    ${C_L_CYAN}${gpu_name}${T_RESET}"
        printMsg "${indent}      - Memory: ${C_L_YELLOW}${mem_used} MiB / ${mem_total} MiB${T_RESET}"
        printMsg "${indent}      - Usage:  ${C_L_YELLOW}${gpu_util}%${T_RESET} (Temp: ${C_L_YELLOW}${temp_gpu}°C${T_RESET})"
        ((gpu_index++))
    done <<< "$smi_output"
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
        local size_bg_color="${C_GREEN}" # Default to Small
        local size_gb_int=${size_gb%.*}

        if [[ "$size_gb_int" -ge 9 ]]; then size_bg_color="${C_RED}";
        elif [[ "$size_gb_int" -ge 6 ]]; then size_bg_color="${C_YELLOW}";
        elif [[ "$size_gb_int" -ge 3 ]]; then size_bg_color="${C_BLUE}";
        fi

        local colored_name="${C_L_CYAN}${name}${T_RESET}"
        local colored_size="${T_BOLD}${size_bg_color}${size_gb} GB${T_RESET}"
        local colored_modified="${C_MAGENTA}${modified}${T_RESET}"

        full_tsv+="${i}\t${colored_name}\t${colored_size}\t${colored_modified}\n"
        ((i++))
    done <<< "$models_tsv"

    local formatted_table
    formatted_table=$(echo -e "${full_tsv}" | format_tsv_as_table "  " "1 3")
    local formatted_header
    formatted_header=$(echo "$formatted_table" | head -n 1)
    local formatted_body
    formatted_body=$(echo "$formatted_table" | tail -n +2)

    printMsg "${formatted_header}"
    printMsg "${C_BLUE}${DIV}${T_RESET}"
    printMsg "${formatted_body}"
    printMsg "${C_BLUE}${DIV}${T_RESET}"
}

display_installed_models() {
    printBanner "Installed Ollama Models"
    check_jq_installed --silent
    verify_ollama_api_responsive
    local models_json
    if ! models_json=$(fetch_models_with_spinner "Fetching model list..."); then
        printInfoMsg "Could not retrieve model list from Ollama API"
        return 1
    fi
    clear_lines_up 1
    print_ollama_models_table "$models_json"
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

# Pulls a new model from the Ollama registry.
# This function is interactive and will prompt for a model name if not provided.
# Usage: pull_model [model_name]
pull_model() {
    local model_name="$1"

    if [[ -z "$model_name" ]]; then
        read -r -p "$(echo -e "${T_QST_ICON} Name of model to pull (e.g., llama3): ")" model_name
        if [[ -z "$model_name" ]]; then
            printErrMsg "No model name entered. Aborting."
            return 1
        fi
    fi

    _execute_pull "$model_name"
}