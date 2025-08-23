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

    printWarnMsg "No tests implemented yet for run-model.sh"

    print_test_summary
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

    load_project_env "$(dirname "$0")/.env"

    # --- Pre-flight checks ---
    check_ollama_installed --silent
    check_jq_installed --silent
    verify_ollama_api_responsive

    # --- Fetch models ---
    local models_json
    if ! models_json=$(fetch_models_with_spinner "Fetching model list..."); then
        printInfoMsg "Could not retrieve model list from Ollama API."
        exit 1
    fi

    # Check if there are any models to run.
    if [[ -z "$(echo "$models_json" | jq '.models | .[]')" ]]; then
        printWarnMsg "No local models found to run."
        printInfoMsg "Use ${C_L_BLUE}./manage-models.sh -p <model_name>${T_RESET} to pull a model first."
        exit 0
    fi

    clear_lines_up 1 # remove "Fetching model..." from output

    # --- Select model ---
    local menu_output
    # We use the multi-select menu but will only use the first selection.
    # The '--with-all' option is omitted as it doesn't make sense here.
    menu_output=$(interactive_multi_select_list_models "Select a model to RUN:" "$models_json")
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        printInfoMsg "No model selected. Aborting."
        exit 1
    fi

    local -a selected_models=()
    mapfile -t selected_models <<< "$menu_output"

    if [[ ${#selected_models[@]} -eq 0 ]]; then
        printWarnMsg "Selection process returned no models. Aborting."
        exit 1
    fi

    local model_to_run="${selected_models[0]}"

    if [[ ${#selected_models[@]} -gt 1 ]]; then
        printWarnMsg "Multiple models were selected. Only the first one will be used: ${C_L_BLUE}${model_to_run}${T_RESET}"
        echo
        read -r -p "$(echo -e "${T_INFO_ICON} Press Enter to continue...")"
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
}

# --- Script Execution ---
main "$@"