#!/bin/bash
# Unit tests for shared.sh

# IMPORTANT: This test script is designed to be run from the script's directory.
# It sources shared.sh from its own location.

# Source the shared library
# shellcheck disable=SC1091
if ! source "$(dirname "$0")/shared.sh"; then
    echo "Error: Could not source shared.sh. Make sure it's in the same directory." >&2
    exit 1
fi

# --- Test Suites ---

test_parse_models_to_tsv() {
    printMsg "\n${T_ULINE}Testing _parse_models_to_tsv function:${T_RESET}"
    
    local test_json='{
        "models": [
            { "name": "llama3:latest", "size": 4700000000, "modified_at": "2024-04-24T10:00:00.0Z" },
            { "name": "gemma:2b", "size": 2900000000, "modified_at": "2024-03-15T12:00:00.0Z" }
        ]
    }'
    # Note: jq sorts by name. gemma comes before llama3.
    # Use $'...' to interpret escape sequences like \t and \n.
    local expected_tsv=$'gemma:2b\t2.9\t2024-03-15\nllama3:latest\t4.7\t2024-04-24'
    
    local actual_tsv
    # Quote the command substitution to preserve newlines.
    actual_tsv="$(_parse_models_to_tsv "$test_json")"

    _run_string_test "$actual_tsv" "$expected_tsv" "Parsing and sorting valid model JSON"

    local empty_json='{"models": []}'
    _run_string_test "$(_parse_models_to_tsv "$empty_json")" "" "Parsing empty model list"
}

test_get_docker_compose_cmd() {
    printMsg "\n${T_ULINE}Testing get_docker_compose_cmd function:${T_RESET}"

    # Mock 'command' and 'docker'
    command() {
        case "$*" in
            "-v docker") [[ "$MOCK_DOCKER_EXISTS" == "true" ]] && return 0 || return 1 ;;
            "-v docker-compose") [[ "$MOCK_DOCKER_COMPOSE_V1_EXISTS" == "true" ]] && return 0 || return 1 ;;
            *) /usr/bin/command "$@" ;;
        esac
    }
    docker() {
        case "$*" in
            "compose version") [[ "$MOCK_DOCKER_COMPOSE_V2_EXISTS" == "true" ]] && return 0 || return 1 ;;
            *) echo "Unknown mock docker command" >&2; return 127 ;;
        esac
    }
    export -f command docker

    export MOCK_DOCKER_EXISTS=true
    export MOCK_DOCKER_COMPOSE_V2_EXISTS=true
    _run_string_test "$(get_docker_compose_cmd)" "docker compose" "Detects 'docker compose' (v2)"

    export MOCK_DOCKER_COMPOSE_V2_EXISTS=false
    export MOCK_DOCKER_COMPOSE_V1_EXISTS=true
    _run_string_test "$(get_docker_compose_cmd)" "docker-compose" "Detects 'docker-compose' (v1) as fallback"

    export MOCK_DOCKER_COMPOSE_V2_EXISTS=false
    export MOCK_DOCKER_COMPOSE_V1_EXISTS=false
    # We test the exit code here because the function calls `exit 1` on failure.
    _run_test "get_docker_compose_cmd >/dev/null 2>&1" 1 "Exits with error when neither is found"

    unset -f command docker
}

test_prereq_checks() {
    printMsg "\n${T_ULINE}Testing prereq_checks function:${T_RESET}"

    # Mock 'command'
    command() {
        if [[ "$1" == "-v" ]]; then
            # Fail if the command to check is in our MOCK_MISSING variable
            if [[ "$2" == "$MOCK_MISSING" ]]; then
                return 1
            else
                return 0
            fi
        else
            /usr/bin/command "$@"
        fi
    }
    export -f command

    export MOCK_MISSING=""
    # This function exits on failure, so we check for exit code 0 on success.
    # We redirect output to hide the "prereq checks..." messages.
    _run_test 'prereq_checks "curl" "docker" "jq" &>/dev/null' 0 "All prerequisites are met"

    export MOCK_MISSING="docker"
    _run_test 'prereq_checks "curl" "docker" "jq" &>/dev/null' 1 "One prerequisite is missing"

    unset -f command
}

test_prompt_yes_no() {
    printMsg "\n${T_ULINE}Testing prompt_yes_no function:${T_RESET}"

    # This function's result is its exit code, which is what _run_test checks.
    # We pipe input to the function and redirect its stdout/stderr to /dev/null
    # to avoid cluttering the test output with its interactive prompts.

    _run_test 'echo "y" | prompt_yes_no "Question?" &>/dev/null' 0 "User enters 'y'"
    _run_test 'echo "YeS" | prompt_yes_no "Question?" &>/dev/null' 0 "User enters 'YeS'"
    _run_test 'echo "n" | prompt_yes_no "Question?" &>/dev/null' 1 "User enters 'n'"
    _run_test 'echo "nO" | prompt_yes_no "Question?" &>/dev/null' 1 "User enters 'nO'"

    printMsg "  --- Testing defaults ---"
    _run_test 'echo "" | prompt_yes_no "Question?" "y" &>/dev/null' 0 "User presses Enter for default 'y'"
    _run_test 'echo "" | prompt_yes_no "Question?" "n" &>/dev/null' 1 "User presses Enter for default 'n'"
    # No default, Enter is invalid, then 'y'
    _run_test 'printf "\ny\n" | prompt_yes_no "Question?" "" &>/dev/null' 0 "Handles Enter then 'y' with no default"

    printMsg "  --- Testing invalid input ---"
    _run_test 'printf "invalid\ny\n" | prompt_yes_no "Question?" &>/dev/null' 0 "Handles invalid input before 'y'"
    _run_test 'printf "invalid\nn\n" | prompt_yes_no "Question?" &>/dev/null' 1 "Handles invalid input before 'n'"
}

# --- Main Test Runner ---

main() {
    # Disable the error and interrupt traps from shared.sh for the test runner
    trap - ERR
    trap - INT

    # --- Run Suites ---
    # We need jq for this test script itself.
    if ! _check_command_exists "jq"; then
        printErrMsg "jq is required to run the test suite. Please install it."
        exit 1
    fi

    test_parse_models_to_tsv
    test_get_docker_compose_cmd
    test_prereq_checks
    test_prompt_yes_no

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

# Execute main
main
