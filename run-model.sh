#!/bin/bash

# --- Source the shared libraries ---
# shellcheck source=./shared.sh
if ! source "$(dirname "$0")/shared.sh"; then
    echo "Error: Could not source shared.sh. Make sure it's in the same directory." >&2
    exit 1
fi

# shellcheck source=./ollama-helpers.sh
if ! source "$(dirname "$0")/ollama-helpers.sh"; then
    echo "Error: Could not source ollama-helpers.sh. Make sure it's in the same directory." >&2
    exit 1
fi

show_help() {
    printBanner "Ollama Model Runner"
    printMsg "Select and run a local Ollama model."
    printMsg "\n${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0")"
    printMsg "\n${T_ULINE}Commands:${T_RESET}"
    printMsg "  ${C_L_BLUE}-h, --help${T_RESET}           Show this help message."
    printMsg "  ${C_L_BLUE}-t, --test${T_RESET}           Run internal self-tests for script logic."
}

run_tests() {
    printBanner "Running Self-Tests for run-model.sh"
    initialize_test_suite

    # --- Mock dependencies ---
    # These will be mocked globally for all tests in this suite.
    load_project_env() { :; }
    check_ollama_installed() { return 0; }
    check_jq_installed() { return 0; }
    verify_ollama_api_responsive() { return 0; }
    clear() { :; } # prevent screen clearing during tests
    
    # These mocks are controlled by environment variables for each test case.
    fetch_models_with_spinner() {
        if [[ "${MOCK_FETCH_MODELS_EXIT_CODE:-0}" -eq 0 ]]; then
            echo "${MOCK_FETCH_MODELS_JSON:-}"
            return 0
        else
            return 1
        fi
    }
    interactive_single_select_list_models() {
        if [[ "${MOCK_SELECT_EXIT_CODE:-0}" -eq 0 ]]; then
            echo "${MOCK_SELECTED_MODEL:-}"
            return 0
        else
            return 1
        fi
    }
    ollama() {
        if [[ "$1" == "run" ]]; then
            MOCK_OLLAMA_RUN_CALLED_WITH="$2"
        fi
    }
    export -f load_project_env check_ollama_installed check_jq_installed verify_ollama_api_responsive clear fetch_models_with_spinner interactive_single_select_list_models ollama

    # --- Test Cases ---
    printTestSectionHeader "Testing main execution logic"

    # Scenario 1: Happy path - select a model and run it.
    export MOCK_FETCH_MODELS_EXIT_CODE=0 MOCK_FETCH_MODELS_JSON='{"models": [{"name": "llama3"}]}'
    export MOCK_SELECT_EXIT_CODE=0 MOCK_SELECTED_MODEL="llama3:latest"
    MOCK_OLLAMA_RUN_CALLED_WITH=""
    run_model_logic &>/dev/null
    _run_string_test "$MOCK_OLLAMA_RUN_CALLED_WITH" "llama3:latest" "Calls 'ollama run' with the selected model"

    # Scenario 2: User cancels model selection.
    export MOCK_SELECT_EXIT_CODE=1
    MOCK_OLLAMA_RUN_CALLED_WITH=""
    run_model_logic &>/dev/null
    _run_string_test "$MOCK_OLLAMA_RUN_CALLED_WITH" "" "Does not call 'ollama run' if selection is cancelled"

    # Scenario 3: No local models are found.
    export MOCK_FETCH_MODELS_JSON='{"models": []}'
    MOCK_OLLAMA_RUN_CALLED_WITH=""
    run_model_logic &>/dev/null
    _run_string_test "$MOCK_OLLAMA_RUN_CALLED_WITH" "" "Does not call 'ollama run' if no models are found"

    # Scenario 4: Fails to fetch models from API.
    export MOCK_FETCH_MODELS_EXIT_CODE=1
    MOCK_OLLAMA_RUN_CALLED_WITH=""
    _run_test 'run_model_logic &>/dev/null' 1 "Returns with error if model fetch fails"
    _run_string_test "$MOCK_OLLAMA_RUN_CALLED_WITH" "" "Does not call 'ollama run' if model fetch fails"

    print_test_summary \
        "load_project_env" "check_ollama_installed" "check_jq_installed" \
        "verify_ollama_api_responsive" "clear" "fetch_models_with_spinner" \
        "interactive_single_select_list_models" "ollama"
}

# Contains the core logic of the script, using `return` instead of `exit` to be testable.
run_model_logic() {
    load_project_env "$(dirname "$0")/.env"

    # --- Pre-flight checks ---
    check_ollama_installed --silent
    check_jq_installed --silent
    verify_ollama_api_responsive

    # --- Fetch models ---
    local models_json
    if ! models_json=$(fetch_models_with_spinner "Fetching model list..."); then
        printInfoMsg "Could not retrieve model list from Ollama API."
        return 1
    fi

    # Check if there are any models to run.
    if [[ -z "$(echo "$models_json" | jq '.models | .[]')" ]]; then
        printWarnMsg "No local models found to run."
        printInfoMsg "Use ${C_L_BLUE}./manage-models.sh -p <model_name>${T_RESET} to pull a model first."
        return 0
    fi

    clear_lines_up 1 # remove "Fetching model..." from output

    # --- Select model ---
    local model_to_run
    # Use the new single-select menu.
    model_to_run=$(interactive_single_select_list_models "Select a model to RUN:" "$models_json")
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        printInfoMsg "No model selected. Aborting."
        return 1
    fi

    # --- Run model ---
    clear # Clear the screen for a clean `ollama run` experience
    printInfoMsg "Starting model: ${C_L_BLUE}${model_to_run}${T_RESET}"
    printInfoMsg "Type '/bye' to exit the model chat."
    printMsg "${C_BLUE}${DIV}${T_RESET}"

    # `ollama run` is an interactive command that takes over the terminal.
    ollama run "$model_to_run"

    printMsg "${C_BLUE}${DIV}${T_RESET}"
    printOkMsg "Finished session with ${C_L_BLUE}${model_to_run}${T_RESET}."
    return 0
}

main() {
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -t|--test)
            run_tests
            exit 0
            ;;
    esac
    run_model_logic
    exit $?
}

# --- Script Execution ---
main "$@"