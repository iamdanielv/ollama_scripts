#!/bin/bash

# Pull the latest container images for OpenWebUI

# --- Source the shared libraries ---
# shellcheck source=../shared.sh
if ! source "$(dirname "$0")/../shared.sh"; then
    echo "Error: Could not source shared.sh. Make sure it's in the parent directory." >&2
    exit 1
fi

# shellcheck source=../ollama-helpers.sh
if ! source "$(dirname "$0")/../ollama-helpers.sh"; then
    echo "Error: Could not source ollama-helpers.sh. Make sure it's in the parent directory." >&2
    exit 1
fi

# --- Script Functions ---
show_help() {
    printBanner "OpenWebUI Updater"
    printMsg "Pulls the latest Docker images for OpenWebUI."
    printMsg "If new images are downloaded, it will prompt to restart the service."

    printMsg "\n${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [-h | -t]"

    printMsg "\n${T_ULINE}Options:${T_RESET}"
    printMsg "  ${C_L_BLUE}-h, --help${T_RESET}      Show this help message."
    printMsg "  ${C_L_BLUE}-t, --test${T_RESET}      Run internal self-tests for script logic."
}

# (Private) A wrapper function to call the start script.
# This is abstracted into a function so it can be easily mocked for testing.
_restart_openwebui() {
    ./start-openwebui.sh
}

# (Private) Handles the logic after a docker pull command has finished.
# This function is separated to make it testable.
# Usage: _handle_pull_result "$pull_output"
_handle_pull_result() {
    local pull_output="$1"

    # Different versions of Docker Compose may have slightly different outputs.
    # We check for "Downloaded newer image" or "Download complete" to be safe,
    # as either indicates new layers were fetched.
    if grep -E -i -q 'Downloaded newer image|Download complete' <<< "$pull_output"; then
        printOkMsg "New OpenWebUI images have been successfully downloaded."
        if prompt_yes_no "Would you like to restart the service now to apply the update?" "y"; then
            printInfoMsg "Restarting OpenWebUI..."
            _restart_openwebui # Call the wrapper function
        else
            printInfoMsg "Update complete. You can restart the service later with: ${C_L_BLUE}./start-openwebui.sh${T_RESET}"
        fi
    else
        printOkMsg "All OpenWebUI images are already up-to-date."
    fi
}

# A function to run internal self-tests for the script's logic.
run_tests() {
    printBanner "Running Self-Tests for update-openwebui.sh"
    test_count=0
    failures=0

    # --- Mock dependencies ---
    # Mock the functions that _handle_pull_result depends on.
    prompt_yes_no() {
        # This mock simulates user input by returning a pre-set exit code.
        # 0 for "yes", 1 for "no".
        return "${MOCK_PROMPT_RETURN_CODE:-0}"
    }
    # Mock the restart wrapper function to just record that it was called.
    _restart_openwebui() {
        MOCK_START_CALLED=true
    }
    # Export the mock functions so subshells can see them.
    export -f prompt_yes_no _restart_openwebui

    # --- Test Cases for _handle_pull_result ---
    printMsg "\n${T_ULINE}Testing _handle_pull_result function:${T_RESET}"

    # Scenario 1: Update found, user says 'y' to restart.
    export MOCK_PROMPT_RETURN_CODE=0
    MOCK_START_CALLED=false
    _handle_pull_result "Status: Downloaded newer image for open-webui:latest" &>/dev/null
    _run_string_test "$MOCK_START_CALLED" "true" "Calls start script when update is found and user says yes"

    # Scenario 2: Update found, user says 'n' to restart.
    export MOCK_PROMPT_RETURN_CODE=1
    MOCK_START_CALLED=false
    _handle_pull_result "Status: Download complete" &>/dev/null
    _run_string_test "$MOCK_START_CALLED" "false" "Does not call start script when user says no"

    # Scenario 3: No update found.
    MOCK_START_CALLED=false
    _handle_pull_result "Image is up to date for open-webui:latest" &>/dev/null
    _run_string_test "$MOCK_START_CALLED" "false" "Does not call start script when no update is found"

    # --- Cleanup Mocks ---
    unset -f prompt_yes_no _restart_openwebui

    # --- Test Summary ---
    printMsg "\n${T_ULINE}Test Summary:${T_RESET}"
    if [[ $failures -eq 0 ]]; then
        printOkMsg "All ${test_count} tests passed!"
        exit 0
    else
        printErrMsg "${failures} of ${test_count} tests failed."
        exit 1
    fi
}


main() {
    if [[ -n "$1" ]]; then
        case "$1" in
            -h|--help) 
                show_help
                exit 0
                ;; 
            -t|--test)
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

    printBanner "OpenWebUI Updater"

    printMsg "${T_INFO_ICON} Checking prerequisites..."

    check_docker_prerequisites
    local docker_compose_cmd
    docker_compose_cmd=$(get_docker_compose_cmd)

    # Ensure we are running in the script's directory so docker-compose can find its files.
    ensure_script_dir

    # The run_with_spinner function will handle output and status.
    # It stores the command's output in the global variable SPINNER_OUTPUT.
    # We split the docker_compose_cmd string into an array to handle "docker compose".
    local docker_compose_cmd_parts=($docker_compose_cmd)

    if ! run_with_spinner "Pulling latest OpenWebUI images" "${docker_compose_cmd_parts[@]}" "pull"; then
        # The spinner function prints detailed errors, so we just need to exit.
        exit 1
    fi

    # Pass the captured output to the handler function.
    _handle_pull_result "$SPINNER_OUTPUT"
}

# Run the main script logic
main "$@"
