#!/bin/bash

# This library should be sourced by other scripts, not executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and should be sourced, not executed." >&2
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

# Verifies that the Ollama API is responsive.
# It uses curl to ping the API endpoint.
# Exits with an error if the API is not reachable.
verify_ollama_api_responsive() {
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