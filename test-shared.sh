#!/bin/bash
# Unit tests for shared.sh

# IMPORTANT: This test script is designed to be run from the script's directory.
# It sources shared.sh from its own location.

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
# --- Source the shared libraries ---
# shellcheck source=./shared.sh
if ! source "${SCRIPT_DIR}/shared.sh"; then
    echo "Error: Could not source shared.sh. Make sure it's in the same directory." >&2
    exit 1
fi

# shellcheck source=./ollama-helpers.sh
if ! source "${SCRIPT_DIR}/ollama-helpers.sh"; then
    echo "Error: Could not source ollama-helpers.sh. Make sure it's in the same directory." >&2
    exit 1
fi

# --- Script Functions ---

# --- Test Suites ---

test_parse_models_to_tsv() {
    printTestSectionHeader "Testing _parse_models_to_tsv function"
    
    local test_json='{
        "models": [
            { "name": "llama3:latest", "size": 4700000000, "modified_at": "2024-04-24T10:00:00.0Z" },
            { "name": "gemma:2b", "size": 2900000000, "modified_at": "2024-03-15T12:00:00.0Z" }
        ]
    }'
    # Note: jq sorts by name. gemma comes before llama3. The jq query rounds to 2 decimal places.
    # Use $'...' to interpret escape sequences like \t and \n.
    local expected_tsv=$'gemma:2b\t2.9\t2024-03-15\nllama3:latest\t4.7\t2024-04-24'

    local actual_tsv
    # Quote the command substitution to preserve newlines.
    actual_tsv="$(_parse_models_to_tsv "$test_json")"

    _run_string_test "$actual_tsv" "$expected_tsv" "Parsing and sorting valid model JSON"

    local empty_json='{"models": []}'
    _run_string_test "$(_parse_models_to_tsv "$empty_json")" "" "Parsing empty model list"

    printTestSectionHeader "─── Corner Cases ───"
    local malformed_json='{"models": [ "name": "bad" }'
    _run_string_test "$(_parse_models_to_tsv "$malformed_json")" "" "Handles malformed JSON"

    local no_models_key_json='{"data": []}'
    _run_string_test "$(_parse_models_to_tsv "$no_models_key_json")" "" "Handles JSON without 'models' key"

    local not_an_array_json='{"models": "not an array"}'
    _run_string_test "$(_parse_models_to_tsv "$not_an_array_json")" "" "Handles when .models is not an array"
}

test_get_docker_compose_cmd() {
    printTestSectionHeader "Testing get_docker_compose_cmd function"

    # Mock 'command' and 'docker'
    # shellcheck disable=SC2317,SC2329 # Mock function for testing
    command() {
        case "$*" in
            "-v docker") [[ "$MOCK_DOCKER_EXISTS" == "true" ]] && return 0 || return 1 ;;
            "-v docker-compose") [[ "$MOCK_DOCKER_COMPOSE_V1_EXISTS" == "true" ]] && return 0 || return 1 ;;
            *) /usr/bin/command "$@" ;;
        esac
    }
    # shellcheck disable=SC2317,SC2329 # Mock function for testing
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
    printTestSectionHeader "Testing prereq_checks function"

    # Mock 'command'
    # shellcheck disable=SC2317,SC2329 # Mock function for testing
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
    printTestSectionHeader "Testing prompt_yes_no function"

    # This function's result is its exit code, which is what _run_test checks.
    # We pipe input to the function and redirect its stdout/stderr to /dev/null
    # to avoid cluttering the test output with its interactive prompts.

    _run_test 'echo "y" | prompt_yes_no "Question?" &>/dev/null' 0 "User enters 'y'"
    _run_test 'echo "YeS" | prompt_yes_no "Question?" &>/dev/null' 0 "User enters 'YeS'"
    _run_test 'echo "n" | prompt_yes_no "Question?" &>/dev/null' 1 "User enters 'n'"
    _run_test 'echo "nO" | prompt_yes_no "Question?" &>/dev/null' 1 "User enters 'nO'"

    printTestSectionHeader "Testing defaults"
    _run_test 'echo "" | prompt_yes_no "Question?" "y" &>/dev/null' 0 "User presses Enter for default 'y'"
    _run_test 'echo "" | prompt_yes_no "Question?" "n" &>/dev/null' 1 "User presses Enter for default 'n'"
    # No default, Enter is invalid, then 'y'
    _run_test 'printf "\ny\n" | prompt_yes_no "Question?" "" &>/dev/null' 0 "Handles Enter then 'y' with no default"

    printTestSectionHeader "Testing invalid input"
    _run_test 'printf "x\ny\n" | prompt_yes_no "Question?" &>/dev/null' 0 "Handles invalid input before 'y'"
    _run_test 'printf "x\nn\n" | prompt_yes_no "Question?" &>/dev/null' 1 "Handles invalid input before 'n'"
}

test_read_single_char() {
    printTestSectionHeader "Testing read_single_char function"

    # We need to run these in a subshell to properly handle the piped input
    # and capture the output. We use printf for reliable escape sequence handling.

    # Scenario 1: Simple character
    # We send "ab" to ensure it only reads the first character.
    local output
    output=$(printf "ab" | read_single_char)
    _run_string_test "$output" "a" "Handles a simple character and ignores subsequent ones"
    output=$(printf "%s" "$KEY_ESC" | read_single_char)
    _run_string_test "$output" "$KEY_ESC" "Handles a lone ESC key"

    # Scenario 3: Arrow key sequence (Up Arrow)
    output=$(printf "%s" "$KEY_UP" | read_single_char)
    _run_string_test "$output" "$KEY_UP" "Handles an arrow key sequence (Up)"

    # Scenario 4: Arrow key sequence (Down Arrow)
    output=$(printf "%s" "$KEY_DOWN" | read_single_char)
    _run_string_test "$output" "$KEY_DOWN" "Handles an arrow key sequence (Down)"

    # Scenario 5: Arrow key sequence (Right Arrow)
    output=$(printf "%s" "$KEY_RIGHT" | read_single_char)
    _run_string_test "$output" "$KEY_RIGHT" "Handles an arrow key sequence (Right)"

    # Scenario 6: Arrow key sequence (Left Arrow)
    output=$(printf "%s" "$KEY_LEFT" | read_single_char)
    _run_string_test "$output" "$KEY_LEFT" "Handles an arrow key sequence (Left)"

    printTestSectionHeader "─── Corner Cases ───"

    # Scenario 7: Enter key
    output=$(printf "\n" | read_single_char)
    _run_string_test "$output" "$KEY_ENTER" "Handles the Enter key"

    # Scenario 8: Tab key
    output=$(printf "\t" | read_single_char)
    _run_string_test "$output" "$KEY_TAB" "Handles the Tab key"

    # Scenario 9: Longer function key sequence
    local KEY_F5=$'\e[15~'
    output=$(printf "%s" "$KEY_F5" | read_single_char)
    _run_string_test "$output" "$KEY_F5" "Handles a longer function key sequence (F5)"

    # Scenario 10: Backspace key
    output=$(printf "%s" "$KEY_BACKSPACE" | read_single_char)
    _run_string_test "$output" "$KEY_BACKSPACE" "Handles the Backspace key"

    # Scenario 11: Home key
    output=$(printf "%s" "$KEY_HOME" | read_single_char)
    _run_string_test "$output" "$KEY_HOME" "Handles the Home key sequence"

    # Scenario 12: Delete key
    output=$(printf "%s" "$KEY_DELETE" | read_single_char)
    _run_string_test "$output" "$KEY_DELETE" "Handles the Delete key sequence"
}

test_check_network_exposure() {
    printTestSectionHeader "Testing check_network_exposure function"

    # Mock systemctl
    # shellcheck disable=SC2317 # Mock function for testing
    systemctl() {
        # We only care about the 'show' subcommand for this test
        if [[ "$1" == "show" ]]; then
            echo "$MOCK_SYSTEMCTL_SHOW_OUTPUT"
            return 0
        fi
        # Fallback for other calls if needed, though none are expected
        /usr/bin/systemctl "$@"
    }
    export -f systemctl

    # Scenario 1: Network is exposed
    export MOCK_SYSTEMCTL_SHOW_OUTPUT='Environment=OLLAMA_HOST=0.0.0.0'
    # This function returns 0 for exposed, 1 for not. _run_test checks the exit code.
    _run_test 'check_network_exposure' 0 "Network is exposed"

    # Scenario 2: Network is restricted (env var not set)
    export MOCK_SYSTEMCTL_SHOW_OUTPUT='Environment='
    _run_test 'check_network_exposure' 1 "Network is restricted (env var not set)"

    # Scenario 3: systemd property is not set at all (systemctl returns empty)
    export MOCK_SYSTEMCTL_SHOW_OUTPUT=''
    _run_test 'check_network_exposure' 1 "Network is restricted (property not set)"

    unset -f systemctl
}

test_check_ollama_installed() {
    printTestSectionHeader "Testing check_ollama_installed function"

    # Mock the internal helper function it relies on
    _check_command_exists() {
        if [[ "$1" == "ollama" ]]; then
            [[ "$MOCK_OLLAMA_CMD_EXISTS" == "true" ]] && return 0 || return 1
        else
            # Allow other commands to be checked normally if needed
            command -v "$1" &>/dev/null
        fi
    }
    export -f _check_command_exists

    # Scenario 1: Ollama is installed. Should return 0.
    export MOCK_OLLAMA_CMD_EXISTS=true
    _OLLAMA_IS_INSTALLED="" # Reset cache
    _run_test 'check_ollama_installed --silent' 0 "Ollama is installed"

    # Scenario 2: Ollama is not installed. Should exit with 1.
    export MOCK_OLLAMA_CMD_EXISTS=false
    _OLLAMA_IS_INSTALLED="" # Reset cache
    _run_test 'check_ollama_installed --silent' 1 "Ollama is not installed"

    unset -f _check_command_exists
}

test_validate_env_file() {
    printTestSectionHeader "Testing _validate_env_file function"

    # Helper to create a temp file with content
    create_temp_env_file() {
        local content="$1"
        local tmp_file
        tmp_file=$(mktemp)
        # Use printf to handle backslashes in content correctly
        printf "%s" "$content" > "$tmp_file"
        echo "$tmp_file"
    }

    # --- Test Cases ---
    local test_file

    # Scenario 1: Valid file
    test_file=$(create_temp_env_file "VAR1=value1\nVAR_2=value2\n# A comment\n")
    _run_test "_validate_env_file '$test_file' &>/dev/null" 0 "Valid .env file"
    rm "$test_file"

    # Scenario 2: Invalid - space after =
    test_file=$(create_temp_env_file "VAR1= value1")
    _run_test "_validate_env_file '$test_file' &>/dev/null" 1 "Invalid: space after ="
    rm "$test_file"

    # Scenario 3: Invalid - space before =
    test_file=$(create_temp_env_file "VAR1 =value1")
    _run_test "_validate_env_file '$test_file' &>/dev/null" 1 "Invalid: space before ="
    rm "$test_file"

    # Scenario 4: Invalid - no =
    test_file=$(create_temp_env_file "VAR1")
    _run_test "_validate_env_file '$test_file' &>/dev/null" 1 "Invalid: missing ="
    rm "$test_file"

    # Scenario 5: Invalid - bad variable name
    test_file=$(create_temp_env_file "1VAR=value")
    _run_test "_validate_env_file '$test_file' &>/dev/null" 1 "Invalid: bad variable name"
    rm "$test_file"
}

test_run_with_spinner() {
    printTestSectionHeader "Testing run_with_spinner and its helpers"

    # --- Test _run_with_spinner_non_interactive ---
    printTestSectionHeader "--- Non-Interactive Mode ---"

    # Scenario 1: Success
    local stderr_file
    stderr_file=$(mktemp)
    SPINNER_OUTPUT="" # Reset global
    _run_with_spinner_non_interactive "Non-interactive success" echo "Success!" 2> "$stderr_file"
    local exit_code_s1=$?
    local stderr_output
    stderr_output=$(<"$stderr_file")
    rm "$stderr_file"

    _run_test "[[ $exit_code_s1 -eq 0 ]]" 0 "Non-interactive success returns 0"
    _run_string_test "$SPINNER_OUTPUT" "Success!" "Non-interactive success captures stdout"
    _run_test '[[ "$stderr_output" == *"Done."* ]]' 0 "Non-interactive success prints 'Done.'"

    # Scenario 2: Failure
    stderr_file=$(mktemp)
    SPINNER_OUTPUT="" # Reset global
    # Use bash -c to create a command that fails and prints to stderr
    _run_with_spinner_non_interactive "Non-interactive failure" bash -c 'echo "Error!" >&2; exit 42' 2> "$stderr_file"
    local exit_code_s2=$?
    stderr_output=$(<"$stderr_file")
    rm "$stderr_file"

    _run_test "[[ $exit_code_s2 -eq 42 ]]" 0 "Non-interactive failure returns correct exit code"
    _run_string_test "$SPINNER_OUTPUT" "Error!" "Non-interactive failure captures stderr"
    _run_test '[[ "$stderr_output" == *"Failed."* && "$stderr_output" == *"Error!"* ]]' 0 "Non-interactive failure prints 'Failed' and the error"

    # --- Test _run_with_spinner_interactive ---
    printTestSectionHeader "--- Interactive Mode ---"

    # Mock tput to prevent it from messing with the test terminal
    tput() { :; }
    export -f tput

    # Scenario 3: Success
    stderr_file=$(mktemp)
    SPINNER_OUTPUT="" # Reset global
    # Run directly, redirecting stderr. The function's internal trap will be handled correctly.
    _run_with_spinner_interactive "Interactive success" bash -c 'echo "Interactive OK"' 2> "$stderr_file"
    local exit_code_s3=$?
    local stderr_output_raw
    stderr_output_raw=$(<"$stderr_file")
    rm "$stderr_file"
    # Clean the raw output, removing ANSI escape codes and carriage returns for stable testing.
    local clean_stderr
    clean_stderr=$(echo "$stderr_output_raw" | sed -E 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | tr -d '\r')

    _run_test "[[ $exit_code_s3 -eq 0 ]]" 0 "Interactive success returns 0"
    _run_string_test "$SPINNER_OUTPUT" "Interactive OK" "Interactive success captures stdout"
    _run_test "[[ \"$clean_stderr\" == *\"[✓] Interactive success\"* ]]" 0 "Interactive success prints OK message"

    # Scenario 4: Failure
    stderr_file=$(mktemp)
    SPINNER_OUTPUT="" # Reset global
    _run_with_spinner_interactive "Interactive failure" bash -c 'echo "Interactive Error" >&2; exit 88' 2> "$stderr_file"
    local exit_code_s4=$?
    stderr_output_raw=$(<"$stderr_file")
    rm "$stderr_file"
    clean_stderr=$(echo "$stderr_output_raw" | sed -E 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | tr -d '\r')

    _run_test "[[ $exit_code_s4 -eq 88 ]]" 0 "Interactive failure returns correct exit code"
    _run_string_test "$SPINNER_OUTPUT" "Interactive Error" "Interactive failure captures stderr"
    _run_test "[[ \"$clean_stderr\" == *\"[✗] Task failed: Interactive failure\"* && \"$clean_stderr\" == *\"Interactive Error\"* ]]" 0 "Interactive failure prints FAIL message and error"

    # Scenario 5: mktemp failure
    mktemp() { return 1; }
    export -f mktemp
    # This test doesn't need to capture output, as it's testing an early exit.
    _run_test '_run_with_spinner_interactive "mktemp fail" echo "wont run" &>/dev/null' 1 "Interactive mode fails if mktemp fails"

    # Cleanup mocks
    unset -f tput mktemp
}

# --- Main Test Runner ---

main() {
    # Disable the error and interrupt traps from shared.sh for the test runner
    trap - ERR
    trap - INT
    printBanner "Running Self-Tests for shared.sh"
    initialize_test_suite

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
    test_read_single_char
    test_check_network_exposure
    test_check_ollama_installed
	test_validate_env_file
    test_run_with_spinner

    # --- Test Summary ---
    printTestSectionHeader "Test Summary:"
    if [[ $failures -eq 0 ]]; then
        printOkMsg "All ${test_count} tests passed!"
        exit 0
    else
        printErrMsg "${failures} of ${test_count} tests failed."
        exit 1
    fi
}

# --- Entrypoint ---
# Run tests if the script is called directly (no args) or with the test flag.
# This ensures it's runnable on its own and detectable by test-all.sh.
if [[ "$1" == "-t" || "$1" == "--test" || -z "$1" ]]; then
    main
fi
