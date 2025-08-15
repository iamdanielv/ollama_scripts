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
    # Note: jq sorts by name. gemma comes before llama3. The jq query rounds to 2 decimal places.
    # Use $'...' to interpret escape sequences like \t and \n.
    local expected_tsv=$'gemma:2b\t2.9\t2024-03-15\nllama3:latest\t4.7\t2024-04-24'

    local actual_tsv
    # Quote the command substitution to preserve newlines.
    actual_tsv="$(_parse_models_to_tsv "$test_json")"

    _run_string_test "$actual_tsv" "$expected_tsv" "Parsing and sorting valid model JSON"

    local empty_json='{"models": []}'
    _run_string_test "$(_parse_models_to_tsv "$empty_json")" "" "Parsing empty model list"

    printMsg "  --- Corner Cases ---"
    local malformed_json='{"models": [ "name": "bad" }'
    _run_string_test "$(_parse_models_to_tsv "$malformed_json")" "" "Handles malformed JSON"

    local no_models_key_json='{"data": []}'
    _run_string_test "$(_parse_models_to_tsv "$no_models_key_json")" "" "Handles JSON without 'models' key"

    local not_an_array_json='{"models": "not an array"}'
    _run_string_test "$(_parse_models_to_tsv "$not_an_array_json")" "" "Handles when .models is not an array"
}

test_get_docker_compose_cmd() {
    printMsg "\n${T_ULINE}Testing get_docker_compose_cmd function:${T_RESET}"

    # Mock 'command' and 'docker'
    # shellcheck disable=SC2329
    command() {
        case "$*" in
            "-v docker") [[ "$MOCK_DOCKER_EXISTS" == "true" ]] && return 0 || return 1 ;;
            "-v docker-compose") [[ "$MOCK_DOCKER_COMPOSE_V1_EXISTS" == "true" ]] && return 0 || return 1 ;;
            *) /usr/bin/command "$@" ;;
        esac
    }
    # shellcheck disable=SC2329
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
    # shellcheck disable=SC2329
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
    _run_test 'printf "x\ny\n" | prompt_yes_no "Question?" &>/dev/null' 0 "Handles invalid input before 'y'"
    _run_test 'printf "x\nn\n" | prompt_yes_no "Question?" &>/dev/null' 1 "Handles invalid input before 'n'"
}

test_read_single_char() {
    printMsg "\n${T_ULINE}Testing read_single_char function:${T_RESET}"

    # We need to run these in a subshell to properly handle the piped input
    # and capture the output. We use printf for reliable escape sequence handling.

    # Scenario 1: Simple character
    local output
    output=$(printf "a" | read_single_char)
    _run_string_test "$output" "a" "Handles a simple character"

    # Scenario 2: Lone ESC key
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
}

test_check_network_exposure() {
    printMsg "\n${T_ULINE}Testing check_network_exposure function:${T_RESET}"

    # Mock systemctl
    # shellcheck disable=SC2329
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
    printMsg "\n${T_ULINE}Testing check_ollama_installed function:${T_RESET}"

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
    printMsg "\n${T_ULINE}Testing _validate_env_file function:${T_RESET}"

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
    test_read_single_char
    test_check_network_exposure
    test_check_ollama_installed
	test_validate_env_file

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

# --- Entrypoint ---
# Run tests if the script is called directly (no args) or with the test flag.
# This ensures it's runnable on its own and detectable by test-all.sh.
if [[ "$1" == "-t" || "$1" == "--test" || -z "$1" ]]; then
    main
fi
