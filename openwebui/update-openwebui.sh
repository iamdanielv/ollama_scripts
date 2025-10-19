#!/bin/bash

# Pull the latest OpenWebUI images and restarts the service if new images are found

# --- Source the shared libraries ---
# shellcheck source=../src/lib/shared.lib.sh
if ! source "$(dirname "$0")/../src/lib/shared.lib.sh"; then
    echo "Error: Could not source shared.lib.sh. Make sure it's in the '../src/lib' directory." >&2
    exit 1
fi

# shellcheck source=../src/lib/ollama.lib.sh
if ! source "$(dirname "$0")/../src/lib/ollama.lib.sh"; then
    echo "Error: Could not source ollama.lib.sh. Make sure it's in the '../src/lib' directory." >&2
    exit 1
fi

show_help() {
    printBanner "OpenWebUI Updater"
    printMsg "Pulls the latest Docker images for OpenWebUI."
    printMsg "If new images are downloaded, it will prompt to restart the service."

    printMsg "\n${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [-h | -t]"

    printMsg "\n${T_ULINE}Options:${T_RESET}"
    printMsg "  ${C_L_BLUE}-h, --help${T_RESET}      Show this help message."
    printMsg "  ${C_L_BLUE}-t, --test${T_RESET}      Runs internal self-tests for script functions."
}

run_tests() {
    printBanner "Running Self-Tests for update-openwebui.sh"
    initialize_test_suite

    # --- Mock dependencies ---
    check_docker_prerequisites() { :; }
    prompt_yes_no() { return "${MOCK_PROMPT_RETURN_CODE:-0}"; } # Default to 'yes'
    poll_service() { return "${MOCK_POLL_RETURN_CODE:-0}"; } # Default to success
    # Override the real exit function to just set a flag and return. Use the new name.
    show_webui_logs_and_exit() { MOCK_SHOW_LOGS_CALLED=true; return 1; }

    # The most complex mock is run_with_spinner
    run_with_spinner() {
        local desc="$1"
        shift
        local cmd_str="$*"
        
        # Differentiate between the 'pull' and 'up' commands
        if [[ "$cmd_str" == *"run_webui_compose pull"* ]]; then
            SPINNER_OUTPUT="$MOCK_PULL_OUTPUT"
            return "${MOCK_PULL_EXIT_CODE:-0}"
        elif [[ "$cmd_str" == *"run_webui_compose up"* ]]; then
            MOCK_RESTART_CALLED=true
            return "${MOCK_RESTART_EXIT_CODE:-0}"
        fi
        return 0 # Fallback for any other unexpected spinner call
    }
    export -f check_docker_prerequisites prompt_yes_no poll_service show_webui_logs_and_exit run_with_spinner

    # --- Test Cases ---
    printTestSectionHeader "Scenario: No update available"
    export MOCK_PULL_EXIT_CODE=0
    export MOCK_PULL_OUTPUT="Image is up to date for ghcr.io/open-webui/open-webui:main"
    MOCK_RESTART_CALLED=false
    update_logic &>/dev/null
    local exit_code_no_update=$?
    _run_test "[[ $exit_code_no_update -eq 0 ]]" 0 "Exits successfully when no update is available"
    _run_string_test "$MOCK_RESTART_CALLED" "false" "Does not attempt restart when no update is available"

    printTestSectionHeader "Scenario: Update successful"
    export MOCK_PULL_OUTPUT="Downloaded newer image for ghcr.io/open-webui/open-webui:main"
    export MOCK_PROMPT_RETURN_CODE=0 # User says yes
    export MOCK_RESTART_EXIT_CODE=0
    export MOCK_POLL_RETURN_CODE=0
    MOCK_RESTART_CALLED=false
    update_logic &>/dev/null
    local exit_code_success=$?
    _run_test "[[ $exit_code_success -eq 0 ]]" 0 "Exits successfully on a full update cycle"
    _run_string_test "$MOCK_RESTART_CALLED" "true" "Attempts restart when update is available and user agrees"

    printTestSectionHeader "Scenario: User declines restart"
    export MOCK_PULL_OUTPUT="Downloaded newer image for ghcr.io/open-webui/open-webui:main"
    export MOCK_PROMPT_RETURN_CODE=1 # User says no
    MOCK_RESTART_CALLED=false
    update_logic &>/dev/null
    local exit_code_decline=$?
    _run_test "[[ $exit_code_decline -eq 0 ]]" 0 "Exits successfully when user declines restart"
    _run_string_test "$MOCK_RESTART_CALLED" "false" "Does not attempt restart when user declines"

    printTestSectionHeader "Scenario: Failures"
    export MOCK_PULL_EXIT_CODE=1
    _run_test 'update_logic &>/dev/null' 1 "Fails when initial image pull fails"

    export MOCK_PULL_EXIT_CODE=0 MOCK_PULL_OUTPUT="Downloaded newer image" MOCK_PROMPT_RETURN_CODE=0 MOCK_RESTART_EXIT_CODE=1
    _run_test 'update_logic &>/dev/null' 1 "Fails when restart command fails"

    export MOCK_PULL_OUTPUT="Downloaded newer image"
    export MOCK_RESTART_EXIT_CODE=0 MOCK_POLL_RETURN_CODE=1 MOCK_SHOW_LOGS_CALLED=false
    update_logic &>/dev/null
    local exit_code_poll_fail=$?
    _run_test "[[ $exit_code_poll_fail -eq 1 ]]" 1 "Fails when polling fails after restart"
    _run_string_test "$MOCK_SHOW_LOGS_CALLED" "true" "Calls log helper when polling fails"

    print_test_summary "check_docker_prerequisites" "prompt_yes_no" "poll_service" "show_webui_logs_and_exit" "run_with_spinner"
}

update_logic() {
    printBanner "OpenWebUI Updater"

    printMsg "${T_INFO_ICON} Checking prerequisites..."
    check_docker_prerequisites

    # The run_with_spinner function will handle output and status.
    # It stores the command's output in the global variable SPINNER_OUTPUT.
    if ! run_with_spinner "Pulling latest OpenWebUI images" run_webui_compose "pull"; then
        # The spinner function prints detailed errors, so we just need to exit.
        return 1
    fi

    # Check if the output from the pull command indicates that images were actually updated.
    # Docker's output for an updated image typically contains "Downloaded newer image".
    # If it's already up to date, it will say "Image is up to date".
    if ! echo "$SPINNER_OUTPUT" | grep -E -i -q "downloaded newer image|download complete|downloading|pulled"; then
        printOkMsg "OpenWebUI is already up-to-date. No new images were pulled."
        return 0
    fi

    printOkMsg "New OpenWebUI images have been downloaded."
    if ! prompt_yes_no "Do you want to restart the OpenWebUI service to apply the updates?" "y"; then
        printInfoMsg "Update cancelled. Run './start-openwebui.sh' later to apply the changes."
        return 0
    fi

    # Restart the service. Using 'up -d' will recreate containers with the new images.
    if ! run_with_spinner "Restarting OpenWebUI with the new images" run_webui_compose up -d --force-recreate; then
        return 1
    fi

    # Verify that the service is responsive after the restart.
    local webui_url
    webui_url=$(get_openwebui_url)

    if ! poll_service "$webui_url" "OpenWebUI UI" 60; then
        show_webui_logs_and_exit "OpenWebUI containers restarted, but the UI is not responding at ${webui_url}."
    fi

    printOkMsg "OpenWebUI has been successfully updated and restarted!"
    printMsg "    🌐 Access it at: ${C_L_BLUE}${webui_url}${T_RESET}"
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

    update_logic
    exit $?
}

# Run the main script logic
main "$@"
