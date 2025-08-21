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


# --- Model Pulling ---

# Pulls a new model from the Ollama registry.
# Usage: pull_model [model_name]
pull_model() {
    local model_name="$1"

    # 1. If no model name is passed as an argument, prompt the user.
    if [[ -z "$model_name" ]]; then
        read -r -p "$(echo -e "${T_QST_ICON} Enter the name of the model to pull (e.g., llama3): ")" model_name
        if [[ -z "$model_name" ]]; then
            printErrMsg "No model name entered. Aborting."
            return 1
        fi
    fi

    printInfoMsg "Starting to pull model: ${C_L_BLUE}${model_name}${T_RESET}"
    printMsg "This may take a while depending on the model size and your network speed..."

    # 2. Use ollama pull for its nice progress bar output.
    # The command streams progress, so we can't use the spinner.
    if ollama pull "$model_name"; then
        printOkMsg "Successfully pulled model: ${C_L_BLUE}${model_name}${T_RESET}"
    else
        printErrMsg "Failed to pull model: ${C_L_BLUE}${model_name}${T_RESET}"
        printInfoMsg "Please check the model name and your network connection."
        return 1
    fi
}

# --- Model Updating ---

# Private helper to perform the actual 'ollama pull' for a list of models.
# Not intended to be called directly by the user.
# Usage: _perform_model_updates "model1" "model2" ...
_perform_model_updates() {
    local models_to_update=("$@")

    if [[ ${#models_to_update[@]} -eq 0 ]]; then
        printWarnMsg "No models specified for update."
        return 0
    fi

    printInfoMsg "The following models will be updated: ${C_L_BLUE}${models_to_update[*]}${T_RESET}"
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

# Updates one or more existing models interactively.
# Usage: update_models_interactive <models_json>
update_models_interactive() {
    local models_json="$1"

    # Check if there are any models to update.
    if [[ -z "$(echo "$models_json" | jq '.models | .[]')" ]]; then
        printWarnMsg "No local models found to update."
        return 0 # Exit gracefully.
    fi

    # Prompt for input. -a reads into an array.
    local -a model_inputs
    read -r -p "$(echo -e "${T_QST_ICON} Enter model number(s) to update (e.g., 1 3 4), or 'all': ")" -a model_inputs
    if [[ ${#model_inputs[@]} -eq 0 ]]; then
        printErrMsg "No input provided. Aborting."
        return 1
    fi

    local models_to_update=()
    local invalid_inputs=()
    local total_models
    total_models=$(echo "$models_json" | jq '.models | length')

    # Handle 'all' keyword (case-insensitive)
    # shellcheck disable=SC2206 # Word splitting is not an issue for the first element.
    if [[ "${model_inputs[0],,}" == "all" ]]; then
        # Get all model names, sorted to be predictable
        mapfile -t models_to_update < <(echo "$models_json" | jq -r '.models | sort_by(.name)[] | .name')
    else
        # Process numeric inputs
        for num in "${model_inputs[@]}"; do
            if [[ "$num" =~ ^[1-9][0-9]*$ && "$num" -le "$total_models" ]]; then
                local model_name
                model_name=$(echo "$models_json" | jq -r ".models | sort_by(.name)[$((num - 1))].name")
                if [[ -n "$model_name" && "$model_name" != "null" ]]; then
                    # Check for duplicates before adding
                    local found=false
                    for item in "${models_to_update[@]}"; do
                        if [[ "$item" == "$model_name" ]]; then found=true; break; fi
                    done
                    if ! $found; then
                       models_to_update+=("$model_name")
                    fi
                else
                    invalid_inputs+=("$num")
                fi
            else
                invalid_inputs+=("$num")
            fi
        done
    fi

    # Report invalid inputs
    if [[ ${#invalid_inputs[@]} -gt 0 ]]; then
        printWarnMsg "Ignoring invalid inputs: ${invalid_inputs[*]}"
    fi

    # Check if there are any valid models to update
    if [[ ${#models_to_update[@]} -eq 0 ]]; then
        printErrMsg "No valid models selected for update."
        return 1
    fi

    # Update the selected models
    _perform_model_updates "${models_to_update[@]}"
}

# --- Model Deletion ---

# Deletes a local model.
# Usage: delete_model [model_name_or_number]
delete_model() {
    local model_input="$1"
    local models_json="$2" # Optional: pass in pre-fetched JSON
    local ollama_port=${OLLAMA_PORT:-11434}

    # Get model data to resolve names/numbers if not provided
    if [[ -z "$models_json" ]]; then
        if ! models_json=$(get_ollama_models_json); then
            printErrMsg "Failed to get model list from Ollama API."
            return 1
        fi
    fi

    # If no model input is provided, show a list and prompt the user.
    if [[ -z "$model_input" ]]; then
        # In interactive mode, the main loop has already displayed the list.
        # We just need to check if there are any models to delete.

        if [[ -z "$(echo "$models_json" | jq '.models | .[]')" ]]; then
            # The main list_models call already showed a "no models" message.
            return 0 # Exit gracefully.
        fi

        read -r -p "$(echo -e "${T_QST_ICON} Enter the name or number of the model to delete: ")" model_input
        if [[ -z "$model_input" ]]; then
            printErrMsg "No model name or number entered. Aborting."
            return 1
        fi
    fi

    # Resolve model name from input (which could be a number)
    local model_name
    # Regex to check if input is a positive integer
    if [[ "$model_input" =~ ^[1-9][0-9]*$ ]]; then
        # It's a number, so find the corresponding model name
        # We sort the models by name first to match the displayed list.
        # Then we select by index (jq arrays are 0-indexed, so we subtract 1).
        model_name=$(echo "$models_json" | jq -r ".models | sort_by(.name)[$((model_input - 1))].name")
        if [[ -z "$model_name" || "$model_name" == "null" ]]; then
            printErrMsg "Invalid model number: ${C_L_YELLOW}${model_input}${T_RESET}"
            return 1
        fi
    else
        # It's not a number, so treat it as a name
        model_name="$model_input"
    fi

    # Confirm the deletion
    if ! prompt_yes_no "Are you sure you want to delete the model: ${C_L_RED}${model_name}${T_RESET}?" "n"; then
        printInfoMsg "Deletion cancelled."
        return 1
    fi

    # Call the Ollama API to delete the model
    local payload
    payload=$(jq -n --arg name "$model_name" '{name: $name}')
    local delete_url="http://localhost:${ollama_port}/api/delete"
    local desc="Deleting model ${C_L_RED}${model_name}${T_RESET}"
    if run_with_spinner "${desc}" curl --silent --show-error --fail -X DELETE -d "$payload" "$delete_url"; then
        printOkMsg "Successfully deleted model: ${C_L_BLUE}${model_name}${T_RESET}"
    else
        # The spinner will print the error, but we can add context.
        printInfoMsg "Please check that the model name is correct."
        return 1
    fi
}

# Refreshes the cached model list used in the interactive menu.
# It calls the shared fetcher function and updates the `cached_models_json`
# variable in the main interactive loop's scope.
# This function is defined here to avoid passing the variable name as an argument.
# Usage: refresh_model_cache
refresh_model_cache() {
    local new_json
    if new_json=$(fetch_models_with_spinner "Refreshing model list..."); then
        cached_models_json="$new_json"
    fi
}

# --- Test Suites ---



test_pull_model() {
    printTestSectionHeader "Testing pull_model function"

    # --- Mock dependencies ---
    # Mock the `ollama` command to track calls and control its exit code.
    ollama() {
        if [[ "$1" == "pull" ]]; then
            MOCK_OLLAMA_PULL_CALLED_WITH="$2"
            return "${MOCK_OLLAMA_PULL_EXIT_CODE:-0}"
        fi
    }
    export -f ollama

    # --- Test Cases ---

    # Scenario 1: Non-interactive call with a model name.
    MOCK_OLLAMA_PULL_CALLED_WITH=""
    pull_model "llama3" &>/dev/null
    _run_string_test "$MOCK_OLLAMA_PULL_CALLED_WITH" "llama3" "Non-interactive pull calls ollama correctly"

    # Scenario 2: Interactive call with user input.
    MOCK_OLLAMA_PULL_CALLED_WITH=""
    pull_model <<< "gemma" &>/dev/null
    _run_string_test "$MOCK_OLLAMA_PULL_CALLED_WITH" "gemma" "Interactive pull calls ollama correctly"

    # Scenario 3: Function fails if the underlying ollama command fails.
    export MOCK_OLLAMA_PULL_EXIT_CODE=1
    _run_test 'pull_model "fail-model" &>/dev/null' 1 "Fails when ollama pull fails"
    export MOCK_OLLAMA_PULL_EXIT_CODE=0 # Reset for next tests

    # Scenario 4: Function fails if no model name is provided interactively.
    _run_test 'pull_model <<< "" &>/dev/null' 1 "Fails when no model name is given interactively"

    # --- Cleanup ---
    unset -f ollama
}


test_perform_model_updates() {
    printTestSectionHeader "Testing _perform_model_updates function"

    # --- Mock dependencies ---
    # This mock tracks the number of calls and which models were requested.
    # It can be configured to fail for a specific model name.
    ollama() {
        if [[ "$1" == "pull" ]]; then
            ((MOCK_OLLAMA_CALL_COUNT++))
            MOCK_OLLAMA_CALLED_WITH+=("$2")
            if [[ "$2" == "$MOCK_OLLAMA_FAIL_ON" ]]; then
                return 1
            fi
            return 0
        fi
    }
    export -f ollama

    # --- Test Cases ---

    # Scenario 1: Successfully updates multiple models. We run the function directly
    # to capture its exit code and check the side-effect on the mock counter.
    MOCK_OLLAMA_CALL_COUNT=0
    MOCK_OLLAMA_CALLED_WITH=()
    export MOCK_OLLAMA_FAIL_ON=""
    _perform_model_updates "model1" "model2" &>/dev/null
    local exit_code_success=$?
    _run_test "[[ $exit_code_success -eq 0 ]]" 0 "Succeeds when all updates work"
    _run_string_test "$MOCK_OLLAMA_CALL_COUNT" "2" "Calls ollama for each model"

    # Scenario 2: Fails if one of the model updates fails.
    MOCK_OLLAMA_CALL_COUNT=0
    MOCK_OLLAMA_CALLED_WITH=()
    export MOCK_OLLAMA_FAIL_ON="model2"
    _perform_model_updates "model1" "model2" &>/dev/null
    local exit_code_fail=$?
    _run_test "[[ $exit_code_fail -eq 1 ]]" 0 "Fails when one update fails"
    _run_string_test "$MOCK_OLLAMA_CALL_COUNT" "2" "Attempts all models even if one fails"

    # Scenario 3: Handles being called with no models.
    MOCK_OLLAMA_CALL_COUNT=0
    _perform_model_updates &>/dev/null
    _run_test "[[ $? -eq 0 ]]" 0 "Handles being called with no models"
    _run_string_test "$MOCK_OLLAMA_CALL_COUNT" "0" "Does not call ollama if no models are given"

    # --- Cleanup ---
    unset -f ollama
}

test_delete_model() {
    printTestSectionHeader "Testing delete_model function"

    # --- Mock dependencies ---
    # Mock the API call to get a predictable list of models.
    # Note: The function under test sorts these by name, so gemma is #1, llama3 is #2.
    get_ollama_models_json() {
        echo '{
            "models": [
                { "name": "llama3:latest", "size": 4700000000, "modified_at": "2024-04-24T10:00:00.0Z" },
                { "name": "gemma:2b", "size": 2900000000, "modified_at": "2024-03-15T12:00:00.0Z" }
            ]
        }'
    }

    # Mock the user confirmation prompt.
    prompt_yes_no() {
        MOCK_PROMPT_CALLED_WITH="$1"
        return "${MOCK_PROMPT_RETURN_CODE:-0}" # Default to 'yes'
    }

    # Mock the spinner which makes the actual API call.
    run_with_spinner() {
        shift # Remove the description
        MOCK_SPINNER_CALLED_WITH_CMD=("$@")
        return "${MOCK_SPINNER_RETURN_CODE:-0}" # Default to success
    }
    export -f get_ollama_models_json prompt_yes_no run_with_spinner

    # --- Test Cases ---

    # Scenario 1: Delete by name, user confirms.
    export MOCK_PROMPT_RETURN_CODE=0
    export MOCK_SPINNER_RETURN_CODE=0
    MOCK_SPINNER_CALLED_WITH_CMD=()
    delete_model "llama3" &>/dev/null
    local exit_code_s1=$?
    _run_test "[[ $exit_code_s1 -eq 0 ]]" 0 "Succeeds when deleting by name with confirmation"
    _run_string_test "${MOCK_SPINNER_CALLED_WITH_CMD[4]}" "-X" "Calls curl with correct method (-X)"

    # Scenario 2: Delete by name, user denies.
    export MOCK_PROMPT_RETURN_CODE=1
    MOCK_SPINNER_CALLED_WITH_CMD=()
    delete_model "llama3" &>/dev/null
    local exit_code_s2=$?
    _run_test "[[ $exit_code_s2 -eq 1 ]]" 0 "Fails when user denies deletion"
    _run_string_test "${#MOCK_SPINNER_CALLED_WITH_CMD[@]}" "0" "Does not call API when user denies"

    # Scenario 3: Delete by number, user confirms.
    export MOCK_PROMPT_RETURN_CODE=0
    MOCK_SPINNER_CALLED_WITH_CMD=()
    MOCK_PROMPT_CALLED_WITH=""
    delete_model "2" &>/dev/null
    local exit_code_s3=$?
    _run_test "[[ $exit_code_s3 -eq 0 ]]" 0 "Succeeds when deleting by number"
    # The prompt should contain the resolved model name, which is llama3 (the 2nd in sorted list).
    _run_test '[[ "$MOCK_PROMPT_CALLED_WITH" == *"llama3"* ]]' 0 "Resolves number to correct model name for prompt"

    # Scenario 4: Delete with invalid number.
    _run_test 'delete_model "99" &>/dev/null' 1 "Fails when given an invalid model number"

    # Scenario 5: API call fails during deletion.
    export MOCK_PROMPT_RETURN_CODE=0
    export MOCK_SPINNER_RETURN_CODE=1
    _run_test 'delete_model "llama3" &>/dev/null' 1 "Fails when the API call fails"
    export MOCK_SPINNER_RETURN_CODE=0 # Reset

    # Scenario 6: No models exist.
    # Override the mock to return an empty list.
    get_ollama_models_json() { echo '{"models": []}'; }
    export -f get_ollama_models_json
    _run_test 'delete_model "" &>/dev/null' 0 "Handles no models existing gracefully"

    # --- Cleanup ---
    unset -f get_ollama_models_json prompt_yes_no run_with_spinner
}

# A function to run internal self-tests for the script's logic.
run_tests() {
    printBanner "Running Self-Tests for manage-models.sh"
    initialize_test_suite
    
    # --- Run Suites ---
    test_pull_model
    test_perform_model_updates
    test_delete_model

    print_test_summary \
        "ollama" "get_ollama_models_json" \
        "prompt_yes_no" "run_with_spinner"
}

# --- Interactive Menu ---
show_main_menu() {
    local menu_str
    menu_str="  ${C_L_BLUE}(R)efresh${T_RESET}  ${C_L_GRAY}|"
    menu_str+="  ${C_L_WHITE}Model:"
    menu_str+="  ${C_L_GREEN}(P)ull"
    menu_str+="  ${C_L_RED}(D)elete"
    menu_str+="  ${C_MAGENTA}(U)pdate${T_RESET}  ${C_L_GRAY}|"
    menu_str+="  ${C_L_WHITE}(Q)uit"

    printMsg "${C_BLUE}${DIV}${T_RESET}"
    printMsg "${menu_str}"
    printMsg "${C_BLUE}${DIV}${T_RESET}"
}

main() {
    load_project_env "$(dirname "$0")/.env"

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
                delete_model "$2"
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

    # --- Interactive Mode ---

    # Fetch the initial model list to cache it for the interactive session.
    local cached_models_json
    if ! cached_models_json=$(fetch_models_with_spinner "Fetching model list..."); then
        # Spinner prints error, but we add context.
        printInfoMsg "Could not connect to Ollama API to start model manager."
        exit 1
    fi

    # Hide cursor for the interactive menu and set a trap to restore it on exit.
    tput civis
    # This trap temporarily overwrites the one in shared.sh to add cursor restoration.
    # It ensures that if the user presses Ctrl+C, the cursor is made visible again.
    trap 'tput cnorm; script_interrupt_handler' INT TERM

    # Interactive mode
    while true; do
        clear
        printBanner "Ollama Model Manager"
        list_models "$cached_models_json"
        clear_lines_up 1
        show_main_menu

        # Read a single character, handling ESC and arrow keys.
        local choice=$(read_single_char)

        # The menu takes up 2 lines (menu, div).
        # We clear it before executing an action for a cleaner interface.
        clear_lines_up 2

        case "$choice" in
            r|R)
                refresh_model_cache
                continue
                ;; 
            p|P)
                pull_model "" # Pass empty string to trigger interactive prompt
                refresh_model_cache
                ;;
            u|U)
                update_models_interactive "$cached_models_json"
                refresh_model_cache
                ;; 
            d|D)
                delete_model "" "$cached_models_json"
                refresh_model_cache
                ;; 
            q|Q|"${KEY_ESC}") # Quit
                printOkMsg "Goodbye!"
                break
                ;; 
            *)
                # Silently ignore invalid keypresses, the loop will redraw.
                continue
                ;; 
        esac
        # Pause for user to see the output of pull/delete before clearing.
        echo
        read -r -p "$(echo -e "${T_INFO_ICON} Press Enter to continue...")"
    done

    # Restore cursor and reset the trap to the default behavior from shared.sh
    tput cnorm
    trap 'script_interrupt_handler' INT
    trap - TERM
}

# --- Script Execution ---

# Call the main function with all provided arguments
main "$@"
