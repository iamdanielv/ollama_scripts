#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
# --- Source the shared libraries ---
# shellcheck source=./lib/ollama.lib.sh
if ! source "${SCRIPT_DIR}/lib/ollama.lib.sh"; then
    echo "Error: Could not source ollama.lib.sh. Make sure it's in the 'src/lib' directory." >&2
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

    # --- Mock dependencies ---
    # These will be mocked globally for all tests in this suite.
    # We use environment variables to control the behavior of some mocks.
    printErrMsg() { :; } # Suppress error messages for tests
    get_ollama_models_json() {
        if [[ "${MOCK_API_FAIL:-false}" == "true" ]]; then
            return 1
        else
            # The jq sort_by(.name) will order this as gemma, llama2, llama3
            echo '{"models": [{"name": "llama3:latest"}, {"name": "gemma:2b"}, {"name": "llama2:latest"}]}'
        fi
    }
    _perform_model_deletions() { MOCK_DELETE_CALLED_WITH="$*"; return 0; }
    _perform_model_updates() { MOCK_UPDATE_CALLED_WITH="$*"; return 0; }
    prompt_yes_no() { [[ "${MOCK_PROMPT_ANSWER}" == "y" ]]; }
    display_installed_models() { MOCK_LIST_CALLED=true; }
    pull_model() { MOCK_PULL_CALLED_WITH="$1"; return 0; }
    show_help() { MOCK_HELP_CALLED=true; }
    fetch_models_with_spinner() { [[ "${MOCK_FETCH_FAIL:-false}" == "true" ]] && return 1 || echo "{}"; }
    interactive_model_manager() { MOCK_INTERACTIVE_CALLED=true; }

    # --- Test Cases for delete_model ---
    # This section tests the real `delete_model` function, but with its dependencies mocked.
    printTestSectionHeader "Testing delete_model function"
    
    # Helper to reset mock state for delete_model tests
    reset_delete_mocks() {
        MOCK_DELETE_CALLED_WITH=""
        export MOCK_PROMPT_ANSWER="y"
        export MOCK_API_FAIL="false"
    }

    reset_delete_mocks
    delete_model "llama3:latest" &>/dev/null
    _run_string_test "$MOCK_DELETE_CALLED_WITH" "llama3:latest" "Deletes correct model by name"

    reset_delete_mocks; export MOCK_PROMPT_ANSWER="n"
    delete_model "llama3:latest" &>/dev/null
    _run_string_test "$MOCK_DELETE_CALLED_WITH" "" "Does not delete if user cancels"

    # Sorted models: gemma:2b (1), llama2:latest (2), llama3:latest (3)
    reset_delete_mocks
    delete_model "2" &>/dev/null
    _run_string_test "$MOCK_DELETE_CALLED_WITH" "llama2:latest" "Deletes correct model by number"

    reset_delete_mocks
    _run_test 'delete_model "99" &>/dev/null' 1 "Fails with an invalid model number"
    _run_string_test "$MOCK_DELETE_CALLED_WITH" "" "Does not call delete with invalid number"

    reset_delete_mocks
    _run_test 'delete_model "" &>/dev/null' 1 "Fails when no model name is provided"

    reset_delete_mocks; export MOCK_API_FAIL="true"
    _run_test 'delete_model "1" &>/dev/null' 1 "Fails if model list fetch fails for number resolution"

    # --- Test Cases for _main_logic (argument parsing) ---
    # For this section, we mock the `delete_model` function itself to test that it's called correctly.
    delete_model() { MOCK_DELETE_FN_CALLED_WITH="$1"; return 0; }
    export -f printErrMsg get_ollama_models_json _perform_model_deletions _perform_model_updates \
        prompt_yes_no display_installed_models pull_model delete_model show_help \
        fetch_models_with_spinner interactive_model_manager

    printTestSectionHeader "Testing argument parsing in _main_logic"
    
    # Helper to reset mock state for _main_logic tests
    reset_main_mocks() {
        MOCK_LIST_CALLED=false
        MOCK_PULL_CALLED_WITH=""
        MOCK_UPDATE_CALLED_WITH=""
        MOCK_DELETE_FN_CALLED_WITH=""
        MOCK_HELP_CALLED=false
        MOCK_INTERACTIVE_CALLED=false
        export MOCK_FETCH_FAIL="false"
    }

    reset_main_mocks; _main_logic --list &>/dev/null
    _run_string_test "$MOCK_LIST_CALLED" "true" "--list calls display_installed_models"

    reset_main_mocks; _main_logic --pull llama3 &>/dev/null
    _run_string_test "$MOCK_PULL_CALLED_WITH" "llama3" "--pull calls pull_model with argument"

    reset_main_mocks; _main_logic --update llama3 &>/dev/null
    _run_string_test "$MOCK_UPDATE_CALLED_WITH" "llama3" "--update calls _perform_model_updates with argument"

    reset_main_mocks; _main_logic --update-all &>/dev/null
    _run_string_test "$MOCK_UPDATE_CALLED_WITH" "gemma:2b llama2:latest llama3:latest" "--update-all calls _perform_model_updates with all models"

    reset_main_mocks; _main_logic --delete llama2 &>/dev/null
    _run_string_test "$MOCK_DELETE_FN_CALLED_WITH" "llama2" "--delete calls delete_model with argument"

    reset_main_mocks; _main_logic &>/dev/null
    _run_string_test "$MOCK_INTERACTIVE_CALLED" "true" "No-args call enters interactive mode"

    print_test_summary \
        "printErrMsg" "get_ollama_models_json" "_perform_model_deletions" "_perform_model_updates" \
        "prompt_yes_no" "display_installed_models" "pull_model" "delete_model" "show_help" \
        "fetch_models_with_spinner" "interactive_model_manager"
}

main() {
    load_project_env "${SCRIPT_DIR}/.env"

    # --- Pre-flight checks for the whole script ---
    check_ollama_installed --silent
    check_jq_installed --silent
    verify_ollama_api_responsive

    _main_logic "$@"
    exit $?
}

_main_logic() {
    # Non-interactive mode
    if [[ -n "$1" ]]; then
        case "$1" in
            -l | --list)
                display_installed_models
                return 0
                ;; 
            -p | --pull)
                pull_model "$2"
                return $?
                ;; 
            -u | --update)
                local model_name="$2"
                if [[ -z "$model_name" || "$model_name" =~ ^- ]]; then
                    printErrMsg "The --update flag requires a model name."
                    return 1
                fi
                _perform_model_updates "$model_name"
                return $?
                ;; 
            -ua | --update-all)
                printInfoMsg "Fetching list of all local models to update..."
                local models_json
                if ! models_json=$(get_ollama_models_json); then
                    printErrMsg "Failed to get model list from Ollama API. Cannot update."
                    return 1
                fi
                local -a all_models
                mapfile -t all_models < <(echo "$models_json" | jq -r '.models | sort_by(.name)[] | .name')
                if [[ ${#all_models[@]} -eq 0 ]]; then
                    printOkMsg "No local models found to update."
                    return 0
                fi
                _perform_model_updates "${all_models[@]}"
                return $?
                ;; 
            -d | --delete)
                local model_name="$2"
                if [[ -z "$model_name" || "$model_name" =~ ^- ]]; then
                    printErrMsg "The --delete flag requires a model name."
                    return 1
                fi
                delete_model "$model_name"
                return $?
                ;; 
            -h | --help)
                show_help
                return 0
                ;; 
            -t | --test)
                run_tests
                return 0
                ;; 
            *)
                show_help
                printMsg "\n${T_ERR}Invalid option: $1${T_RESET}"
                return 1
                ;; 
        esac
    fi

    # --- Interactive Mode (default) ---
    # Fetch the initial model list to pass to the interactive manager.
    local cached_models_json
    if ! cached_models_json=$(fetch_models_with_spinner "Fetching model list..."); then
        printInfoMsg "Could not connect to Ollama API to start model manager."
        return 1
    fi

    # Hand off control to the full-screen interactive manager
    interactive_model_manager "$cached_models_json"
    return $?
}

# --- Script Execution ---

# Call the main function with all provided arguments
main "$@"
