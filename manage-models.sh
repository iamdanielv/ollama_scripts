#!/bin/bash

# Source the shared library
# shellcheck disable=SC1091
source "$(dirname "$0")/shared.sh"

show_help() {
    printBanner "Ollama Model Manager"
    printMsg "An interactive script to list, pull, and delete local Ollama models."
    printMsg "Can also be run non-interactively with flags."

    printMsg "\n${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [command] [argument]"

    printMsg "\n${T_ULINE}Commands:${T_RESET}"
    printMsg "  ${C_L_BLUE}-l, --list${T_RESET}           List all installed models."
    printMsg "  ${C_L_BLUE}-p, --pull <model>${T_RESET}   Pull a new model from the registry."
    printMsg "  ${C_L_BLUE}-d, --delete <model>${T_RESET} Delete a local model."
    printMsg "  ${C_L_BLUE}-h, --help${T_RESET}           Show this help message."

    printMsg "\n${T_ULINE}Examples:${T_RESET}"
    printMsg "  ${C_GRAY}# Run the interactive menu${T_RESET}"
    printMsg "  $(basename "$0")"
    printMsg "  ${C_GRAY}# List models non-interactively${T_RESET}"
    printMsg "  $(basename "$0") --list"
    printMsg "  ${C_GRAY}# Pull the 'llama3' model${T_RESET}"
    printMsg "  $(basename "$0") --pull llama3"
    printMsg "  ${C_GRAY}# Delete the 'llama2' model${T_RESET}"
    printMsg "  $(basename "$0") --delete llama2"
}

# --- Main Logic ---

# --- Model Listing ---

# Lists all locally installed Ollama models in a formatted table.
# Can optionally be passed the JSON model data to avoid fetching it again.
# Usage: list_models [models_json]
list_models() {
    local models_json="$1"
    if [[ -z "$models_json" ]]; then
        if ! models_json=$(get_ollama_models_json); then
            printErrMsg "Failed to get model list from Ollama API."
            return 1
        fi
    fi

    # Check if any models are installed
    if [[ -z "$(echo "$models_json" | jq '.models | .[]')" ]]; then
        printWarnMsg "No local models found."
        printInfoMsg "You can pull a model with the command: ${C_L_BLUE}ollama pull <model_name>${T_RESET}"
        return 0
    fi

    # Table Header
    printf "  %-5s %-40s %10s  %-15s\n" "#" "NAME" "SIZE" "MODIFIED"
    printMsg "${C_BLUE}${DIV}${T_RESET}"

    # Table Body
    local i=1

    while IFS=$'\t' read -r name size_gb modified; do
        printf "  %-5s ${C_L_CYAN}%-40s${T_RESET} ${C_L_YELLOW}%10s${T_RESET}  ${C_GRAY}%-15s${T_RESET}\n" "$i" "$name" "${size_gb} GB" "$modified"
        ((i++))
    done < <(echo "$models_json" | jq -r '.models | sort_by(.name)[] | "\(.name)\t\(.size / 1e9 | (. * 100 | floor) / 100)\t\(.modified_at | .[:10])"')
    
    printMsg "${C_BLUE}${DIV}${T_RESET}"
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
        model_name=$(echo "$models_json" | jq -r "(.models | sort_by(.name))[$((model_input - 1))].name")
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


# --- Main Menu ---

show_menu() {
    local menu_str
    menu_str="  ${C_L_BLUE}(R)efresh${T_RESET} List  ${C_GRAY}|${T_RESET}"
    menu_str+="  ${C_L_YELLOW}(P)ull${T_RESET} Model    ${C_GRAY}|${T_RESET}"
    menu_str+="  ${C_L_RED}(D)elete${T_RESET} Model  ${C_GRAY}|${T_RESET}"
    menu_str+="  ${C_GRAY}(Q)uit"

    printMsg "\n${C_BLUE}${DIV}${T_RESET}"
    printMsg "${menu_str}"
    printMsg "${C_BLUE}${DIV}${T_RESET}"
}

main() {
    load_project_env

    # --- Pre-flight checks for the whole script ---
    check_ollama_installed
    clear_lines_up 1
    check_jq_installed
    verify_ollama_api_responsive

    # Non-interactive mode
    if [[ -n "$1" ]]; then
        case "$1" in
            -l | --list)
                list_models
                exit 0
                ;;
            -p | --pull)
                pull_model "$2"
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
    if ! run_with_spinner "Fetching model list..." get_ollama_models_json; then
        # Spinner prints error, but we add context.
        printInfoMsg "Could not connect to Ollama API to start model manager."
        exit 1
    fi
    cached_models_json="$SPINNER_OUTPUT"

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
        show_menu

        local choice
        # Read a single character, silently, without needing Enter.
        read -rsn1 choice

        # Handle ESC key for quitting, distinguishing from arrow key sequences
        if [[ "$choice" == $'\e' ]]; then
            local seq
            # Read with a very short timeout to see if other characters follow.
            # The `|| true` prevents the script from exiting if `read` times out.
            read -rsn2 -t 0.01 seq || true
            if [[ -n "$seq" ]]; then
                # It was part of an escape sequence (e.g., arrow key), so ignore it.
                choice="" # Treat it as an invalid keypress
            fi
        fi

        # The menu takes up 4 lines (newline, div, menu, div).
        # We clear it before executing an action for a cleaner interface.
        clear_lines_up 4

        case "$choice" in
            r|R)
                # The loop will automatically refresh by clearing and re-listing.
                if run_with_spinner "Refreshing model list..." get_ollama_models_json; then
                    cached_models_json="$SPINNER_OUTPUT"
                fi
                continue
                ;;
            p|P)
                pull_model
                if run_with_spinner "Refreshing model list..." get_ollama_models_json; then
                    cached_models_json="$SPINNER_OUTPUT"
                fi
                ;;
            d|D)
                delete_model "" "$cached_models_json"
                if run_with_spinner "Refreshing model list..." get_ollama_models_json; then
                    cached_models_json="$SPINNER_OUTPUT"
                fi
                ;;
            q|Q|$'\e') # Quit
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
