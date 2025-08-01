#!/bin/bash

# Source the shared library
# shellcheck disable=SC1091
source "$(dirname "$0")/shared.sh"

# --- Main Logic ---

# --- Model Listing ---

# Lists all locally installed Ollama models in a formatted table.
list_models() {
    # 1. Pre-flight checks
    check_ollama_installed
    clear_lines_up 1
    check_jq_installed
    verify_ollama_api_responsive

    # 2. Get model data
    #printInfoMsg "Fetching local models from Ollama API..."
    local ollama_port=${OLLAMA_PORT:-11434}
    local models_json
    if ! models_json=$(curl --silent --fail http://localhost:"${ollama_port}"/api/tags); then
        printErrMsg "Failed to get model list from Ollama API."
        return 1
    fi

    # 3. Check if any models are installed
    if [[ -z "$(echo "$models_json" | jq '.models | .[]')" ]]; then
        printWarnMsg "No local models found."
        printInfoMsg "You can pull a model with the command: ${C_L_BLUE}ollama pull <model_name>${T_RESET}"
        return 0
    fi

    # 4. Render the table
    printBanner "Installed Ollama Models"

    # Table Header
    printf "  %-5s %-40s %-10s %-15s\n" "#" "NAME" "SIZE" "MODIFIED"
    printMsg "${C_BLUE}${DIV}${T_RESET}"

    # Table Body
    local i=1
    echo "$models_json" | jq -r '.models[] | @base64' | while IFS= read -r b64_line; do
        local model_data
        model_data=$(echo "$b64_line" | base64 --decode)

        local name size modified
        name=$(echo "$model_data" | jq -r .name)
        size=$(echo "$model_data" | jq -r .size)
        modified=$(echo "$model_data" | jq -r .modified_at | cut -d'T' -f1)

        # Convert size to human-readable format (GB)
        local size_gb
        size_gb=$(awk -v size="$size" 'BEGIN { printf "%.2f GB", size / 1024 / 1024 / 1024 }')

        printf "  %-5s %-40s %-10s %-15s\n" "$i" "$name" "$size_gb" "$modified"
        ((i++))
    done

    printMsg "${C_BLUE}${DIV}${T_RESET}"
}


# --- Model Pulling ---

# Pulls a new model from the Ollama registry.
# Usage: pull_model [model_name]
pull_model() {
    local model_name="$1"

    # 1. If no model name is passed as an argument, prompt the user.
    if [[ -z "$model_name" ]]; then
        read -p "$(echo -e "${T_QST_ICON} Enter the name of the model to pull (e.g., llama3): ")" model_name
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

# --- Model Deletion ---

# Deletes a local model.
# Usage: delete_model [model_name_or_number]
delete_model() {
    local model_input="$1"

    # 1. Pre-flight checks
    check_ollama_installed
    clear_lines_up 1
    verify_ollama_api_responsive
    

    # 2. Get model data to resolve names/numbers
    local ollama_port=${OLLAMA_PORT:-11434}
    local models_json
    if ! models_json=$(curl --silent --fail http://localhost:"${ollama_port}"/api/tags); then
        printErrMsg "Failed to get model list from Ollama API."
        return 1
    fi

    # 3. If no model input is provided, show a list and prompt the user.
    if [[ -z "$model_input" ]]; then
        # We need to call list_models, but it fetches its own json. This is a slight
        # inefficiency but keeps the functions decoupled.
        list_models

        if [[ -z "$(echo "$models_json" | jq '.models | .[]')" ]]; then
            return 0 # Exit gracefully, no models to delete.
        fi
        echo
        read -p "$(echo -e "${T_QST_ICON} Enter the name or number of the model to delete: ")" model_input
        if [[ -z "$model_input" ]]; then
            printErrMsg "No model name or number entered. Aborting."
            return 1
        fi
    fi

    # 4. Resolve model name from input (which could be a number)
    local model_name
    # Regex to check if input is a positive integer
    if [[ "$model_input" =~ ^[1-9][0-9]*$ ]]; then
        # It's a number, so find the corresponding model name
        # jq arrays are 0-indexed, so we subtract 1
        model_name=$(echo "$models_json" | jq -r ".models[$((model_input - 1))].name")
        if [[ -z "$model_name" || "$model_name" == "null" ]]; then
            printErrMsg "Invalid model number: ${C_L_YELLOW}${model_input}${T_RESET}"
            return 1
        fi
    else
        # It's not a number, so treat it as a name
        model_name="$model_input"
    fi

    # 5. Confirm the deletion
    if ! prompt_yes_no "Are you sure you want to delete the model: ${C_L_RED}${model_name}${T_RESET}?"; then
        printInfoMsg "Deletion cancelled."
        return 1
    fi

    # 6. Call the Ollama API to delete the model
    local delete_url="http://localhost:${ollama_port}/api/delete"
    local payload
    payload=$(jq -n --arg name "$model_name" '{name: $name}')

    local desc="Deleting model ${C_L_RED}${model_name}${T_RESET}"
    if run_with_spinner "${desc}" curl --silent --fail -X DELETE -d "$payload" "$delete_url"; then
        printOkMsg "Successfully deleted model: ${C_L_BLUE}${model_name}${T_RESET}"
    else
        # The spinner will print the error, but we can add context.
        printInfoMsg "Please check that the model name is correct."
        return 1
    fi
}


# --- Main Menu ---

show_menu() {
    printBanner "Ollama Model Manager"
    echo
    printMsg "  1) ${C_L_BLUE}List${T_RESET} Local Models"
    printMsg "  2) ${C_L_YELLOW}Pull${T_RESET} a New Model"
    printMsg "  3) ${C_L_RED}Delete${T_RESET} a Local Model"
    echo
    printMsg "  ${C_GRAY}q) Quit${T_RESET}"
    echo
}

main() {

    load_project_env
    
    # Non-interactive mode
    if [[ "$1" == "--list" ]] || [[ "$1" == "-l" ]]; then
        list_models
        exit 0
    elif [[ "$1" == "--pull" ]]; then
        pull_model "$2"
        exit $?
    elif [[ "$1" == "--delete" ]]; then
        delete_model "$2"
        exit $?
    fi

    # Interactive mode
    while true; do
        show_menu
        local choice
        read -p "$(echo -e "${T_QST_ICON} Enter your choice: ")" choice

        case $choice in
            1)
                clear_lines_up 1
                list_models
                ;;
            2)
                clear_lines_up 3
                pull_model
                ;;
            3)
                clear_lines_up 3
                delete_model
                ;;
            q|Q|*)
                clear_lines_up 3
                #printInfoMsg "Exiting."
                break
                ;;
        esac
        # Pause for user to see the output before clearing for the next menu
        if [[ "$choice" != "q" ]] && [[ "$choice" != "Q" ]]; then
            read -p "$(echo -e "${T_INFO_ICON} Press Enter to continue...")"
        fi
        clear
    done
}

# --- Script Execution ---

# Call the main function with all provided arguments
main "$@"
