#!/bin/bash

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

show_help() {
    printBanner "Ollama Model Manager"
    printMsg "An interactive script to list, pull, and delete local Ollama models."
    printMsg "Can also be run non-interactively with flags."

    printMsg "\n${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [command] [argument]"

    printMsg "\n${T_ULINE}Commands:${T_RESET}"
    printMsg "  ${C_L_BLUE}-l, --list${T_RESET}           List all installed models."
    printMsg "  ${C_L_BLUE}-p, --pull <model>${T_RESET}   Pull a new model from the registry."
    printMsg "  ${C_L_BLUE}-u, --update <model>${T_RESET} Update a specific local model."
    printMsg "  ${C_L_BLUE}-ua, --update-all${T_RESET}  Update all existing local models."
    printMsg "  ${C_L_BLUE}-d, --delete <model>${T_RESET} Delete a local model."
    printMsg "  ${C_L_BLUE}-h, --help${T_RESET}           Show this help message."
    printMsg "  ${C_L_BLUE}-t, --test${T_RESET}           Run internal self-tests for script logic."

    printMsg "\n${T_ULINE}Examples:${T_RESET}"
    printMsg "  ${C_L_GRAY}# Run the interactive menu${T_RESET}"
    printMsg "  $(basename "$0")"
    printMsg "  ${C_L_GRAY}# List models non-interactively${T_RESET}"
    printMsg "  $(basename "$0") --list"
    printMsg "  ${C_L_GRAY}# Pull the 'llama3' model${T_RESET}"
    printMsg "  $(basename "$0") --pull llama3"
    printMsg "  ${C_L_GRAY}# Update the 'llama3' model${T_RESET}"
    printMsg "  $(basename "$0") --update llama3"
    printMsg "  ${C_L_GRAY}# Update all local models non-interactively${T_RESET}"
    printMsg "  $(basename "$0") --update-all"
    printMsg "  ${C_L_GRAY}# Delete the 'llama2' model${T_RESET}"
    printMsg "  $(basename "$0") --delete llama2"
    printMsg "  ${C_L_GRAY}# Run internal script tests${T_RESET}"
    printMsg "  $(basename "$0") --test"
}

# --- Main Logic ---

# --- Model Listing ---

# Renders a model table from pre-fetched JSON.
# This is used by the interactive loop to avoid re-fetching data on every redraw.
# Usage: list_models [models_json]
list_models() {
    local models_json="$1"
    print_ollama_models_table "$models_json"
}

# --- Model Deletion ---

# Deletes a single local model, with confirmation.
# This is intended for non-interactive use via flags.
# Usage: delete_model <model_name>
delete_model() {
    local model_name_or_num="$1"

    if [[ -z "$model_name_or_num" ]]; then
        printErrMsg "delete_model function requires a model name or number."
        return 1
    fi

    local model_to_delete="$model_name_or_num"

    # Check if input is a number, and if so, resolve it to a model name.
    if [[ "$model_name_or_num" =~ ^[0-9]+$ ]]; then
        local models_json
        if ! models_json=$(get_ollama_models_json); then
            printErrMsg "Could not fetch model list to resolve number."
            return 1
        fi

        local -a model_names
        mapfile -t model_names < <(echo "$models_json" | jq -r '.models | sort_by(.name)[] | .name')

        local num_models=${#model_names[@]}
        local index=$((model_name_or_num - 1))

        if [[ $index -lt 0 || $index -ge $num_models ]]; then
            printErrMsg "Invalid model number: ${model_name_or_num}. Please choose a number between 1 and ${num_models}."
            return 1
        fi
        model_to_delete="${model_names[index]}"
    fi

    # Confirm the deletion
    if ! prompt_yes_no "Are you sure you want to delete the model: ${C_L_RED}${model_to_delete}${T_RESET}?" "n"; then
        printInfoMsg "Deletion cancelled."
        return 1
    fi

    # Call the shared helper to perform the deletion.
    # It returns 0 on success, 1 on failure.
    _perform_model_deletions "${model_to_delete}"
}

# A function to run internal self-tests for the script's logic.
run_tests() {
    printBanner "Running Self-Tests for manage-models.sh"
    initialize_test_suite
    
    print_test_summary \
        # No mocks to unset as tests are removed.
}

main() {
    load_project_env "${SCRIPT_DIR}/.env"

    # --- Pre-flight checks for the whole script ---
    check_ollama_installed --silent
    check_jq_installed --silent
    verify_ollama_api_responsive

    # Non-interactive mode
    if [[ -n "$1" ]]; then
        case "$1" in
            -l | --list)
                display_installed_models
                exit 0
                ;; 
            -p | --pull)
                pull_model "$2"
                exit $?
                ;; 
            -u | --update)
                local model_name="$2"
                if [[ -z "$model_name" || "$model_name" =~ ^- ]]; then
                    printErrMsg "The --update flag requires a model name."
                    exit 1
                fi
                _perform_model_updates "$model_name"
                exit $?
                ;; 
            -ua | --update-all)
                printInfoMsg "Fetching list of all local models to update..."
                local models_json
                if ! models_json=$(get_ollama_models_json); then
                    printErrMsg "Failed to get model list from Ollama API. Cannot update."
                    exit 1
                fi
                local -a all_models
                mapfile -t all_models < <(echo "$models_json" | jq -r '.models[].name')
                if [[ ${#all_models[@]} -eq 0 ]]; then
                    printOkMsg "No local models found to update."
                    exit 0
                fi
                _perform_model_updates "${all_models[@]}"
                exit $?
                ;; 
            -d | --delete)
                local model_name="$2"
                if [[ -z "$model_name" || "$model_name" =~ ^- ]]; then
                    printErrMsg "The --delete flag requires a model name."
                    exit 1
                fi
                delete_model "$model_name"
                exit $?
                ;; 
            -h | --help)
                show_help
                exit 0
                ;; 
            -t | --test)
                run_tests
                exit 0
                ;; 
            *)
                show_help
                printMsg "\n${T_ERR}Invalid option: $1${T_RESET}"
                exit 1
                ;; 
        esac
    fi

    # --- Interactive Mode (default) ---
    # Fetch the initial model list to pass to the interactive manager.
    local cached_models_json
    if ! cached_models_json=$(fetch_models_with_spinner "Fetching model list..."); then
        printInfoMsg "Could not connect to Ollama API to start model manager."
        exit 1
    fi

    # Hand off control to the full-screen interactive manager
    interactive_model_manager "$cached_models_json"
}

# --- Script Execution ---

# Call the main function with all provided arguments
main "$@"
