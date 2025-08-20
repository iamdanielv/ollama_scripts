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

    # --- Table Header ---
    printf "  %-5s %-40s %10s  %-15s\n" "#" "NAME" "SIZE" "MODIFIED"
    printMsg "${C_BLUE}${DIV}${T_RESET}"

    # --- Table Body ---
    local i=1
    # iterate over TSV data
    while IFS=$'\t' read -r name size_gb modified; do
        # Determine background color for size
        # < 3GB: Green (Small), 3-6GB: Blue (Medium), 6-9GB: Yellow (Large), >= 9GB: Red (Extra Large)
        local size_bg_color="${BG_GREEN}" # Default to Small
        local size_gb_int=${size_gb%.*}

        if [[ "$size_gb_int" -ge 9 ]]; then
            size_bg_color="${BG_RED}"      # Extra Large
        elif [[ "$size_gb_int" -ge 6 ]]; then
            size_bg_color="${BG_YELLOW}"   # Large
        elif [[ "$size_gb_int" -ge 3 ]]; then
            size_bg_color="${BG_BLUE}"     # Medium
        fi

        printf "  %-5s ${C_L_CYAN}%-40s${T_RESET} ${size_bg_color}${C_BLACK}%10s${T_RESET}  ${C_MAGENTA}%-15s${T_RESET}\n" "$i" "$name" "${size_gb} GB" "$modified"
        ((i++))
    done <<< "$models_tsv" # Use a "here string" for cleaner input to loop

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

    clear_lines_up 1 # remove "Fetching model..." from output

    # 3. Display table
    print_ollama_models_table "$models_json"
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
