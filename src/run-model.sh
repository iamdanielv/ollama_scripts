#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
# --- Source the shared libraries ---
# shellcheck source=./lib/ollama.lib.sh
if ! source "${SCRIPT_DIR}/lib/ollama.lib.sh"; then
    echo "Error: Could not source ollama.lib.sh. Make sure it's in the 'src/lib' directory." >&2
    exit 1
fi

# Contains the core logic of the script, using `return` instead of `exit` to be testable.
run_model_logic() {
    load_project_env "${SCRIPT_DIR}/.env"

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

    # clear the entire screen so we start with a clean slate
    clear

    # --- Select model ---
    local model_to_run
    # Use the new single-select menu. Declare and assign separately
    # to avoid masking the exit code of the command substitution.
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