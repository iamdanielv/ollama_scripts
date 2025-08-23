#!/bin/bash
# Configure Ollama network exposure (localhost vs. network).

# Source common utilities
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
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

# --- Script Variables ---
readonly STATUS_NETWORK="network"
readonly STATUS_LOCALHOST="localhost"

# --- Helper Functions ---
_after_change_verification() {
    printInfoMsg "\nVerifying service after configuration change..."
    verify_ollama_service
    print_current_status
}

show_help() {
    local is_verbose=false
    if [[ "$1" == "verbose" ]]; then
        is_verbose=true
    fi

    if $is_verbose; then
        printBanner "Ollama Network Configurator"
        printMsg "Configures Ollama network exposure."
        printMsg "If run without flags, it enters an interactive configuration mode.\n"
    fi

    printMsg "${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [-e | -r | -v | -h | -t]"

    printMsg "\n${T_ULINE}Options:${T_RESET}"
    printMsg "  ${C_L_BLUE}-e, --expose${T_RESET}    Expose Ollama to the network (listens on 0.0.0.0)."
    printMsg "  ${C_L_BLUE}-r, --restrict${T_RESET}  Restrict Ollama to localhost (listens on 127.0.0.1)."
    printMsg "  ${C_L_BLUE}-v, --view${T_RESET}      View the current network configuration and exit."
    printMsg "  ${C_L_BLUE}-h, --help${T_RESET}      Show this help message."
    printMsg "  ${C_L_BLUE}-t, --test${T_RESET}      Run the internal test suite."

    if $is_verbose; then
        printMsg "\n${T_ULINE}Examples:${T_RESET}"
        printMsg "  ${C_GRAY}# Run the interactive configuration menu${T_RESET}"
        printMsg "  $(basename "$0")"
        printMsg "  ${C_GRAY}# Expose Ollama to the network non-interactively${T_RESET}"
        printMsg "  $(basename "$0") --expose"
    fi
}

print_current_status() {
    printMsgNoNewline "${T_BOLD}Status:${T_RESET}"
    if check_network_exposure; then
        printMsg " ${C_L_YELLOW}EXPOSED to the network${T_RESET} (listening on 0.0.0.0)."
    else
        printMsg " ${C_L_BLUE}RESTRICTED to localhost${T_RESET} (listening on 127.0.0.1)."
    fi
}

# --- Test Suite ---

# A function to run internal self-tests for the script's logic.
run_tests() {
    printBanner "Running tests for config-ollama-net.sh"
    initialize_test_suite
    
    # Mock all external commands and functions
    ensure_root() { :; }
    verify_ollama_service() { :; }
    load_project_env() { :; }
    prereq_checks() { :; }
    
    # Mock the functions that change state
    expose_to_network() {
        # Simulate success (0), no-change (2), or failure (1)
        # We use a global mock variable to control this.
        return "$MOCK_CHANGE_EXIT_CODE"
    }
    restrict_to_localhost() {
        return "$MOCK_CHANGE_EXIT_CODE"
    }
    # Mock the function that checks state
    check_network_exposure() {
        # We use a global mock variable to control this.
        [[ "$MOCK_IS_EXPOSED" == "true" ]]
    }

    # Test --view flag
    printTestSectionHeader "Testing --view flag"
    MOCK_IS_EXPOSED=true
    _run_string_test "$(_main_logic --view)" "$STATUS_NETWORK" "Shows 'network' when exposed"
    MOCK_IS_EXPOSED=false
    _run_string_test "$(_main_logic --view)" "$STATUS_LOCALHOST" "Shows 'localhost' when restricted"

    # Test --expose flag
    printTestSectionHeader "Testing --expose flag"
    MOCK_CHANGE_EXIT_CODE=0 # Success
    MOCK_IS_EXPOSED=true   # State after change
    _run_string_test "$(_main_logic --expose)" "$STATUS_NETWORK" "Exposes network successfully"
    
    MOCK_CHANGE_EXIT_CODE=2 # No change needed
    MOCK_IS_EXPOSED=true   # State is already correct
    _run_string_test "$(_main_logic --expose)" "$STATUS_NETWORK" "Handles no-change when already exposed"

    # Test --restrict flag
    printTestSectionHeader "Testing --restrict flag"
    MOCK_CHANGE_EXIT_CODE=0 # Success
    MOCK_IS_EXPOSED=false  # State after change
    _run_string_test "$(_main_logic --restrict)" "$STATUS_LOCALHOST" "Restricts to localhost successfully"

    MOCK_CHANGE_EXIT_CODE=2 # No change needed
    MOCK_IS_EXPOSED=false  # State is already correct
    _run_string_test "$(_main_logic --restrict)" "$STATUS_LOCALHOST" "Handles no-change when already restricted"

    # Test invalid flag
    printTestSectionHeader "Testing invalid input"
    # This should exit with 1, so we test the exit code
    _run_test '_main_logic --invalid-flag &>/dev/null' 1 "Handles an invalid flag"

    print_test_summary \
        "ensure_root" "verify_ollama_service" "load_project_env" "prereq_checks" \
        "expose_to_network" "restrict_to_localhost" "check_network_exposure"
}




# --- Main Logic ---
main() {
    # First argument is the command, or could be empty for interactive mode.
    local command="$1"

    # --- Test Runner ---
    # If the test flag is passed, run the test suite and exit.
    if [[ "$command" == "-t" || "$command" == "--test" ]]; then
        run_tests
        exit 0
    fi

    # --- Non-interactive and interactive logic ---
    # We run the main logic inside a sub-function to make it testable.
    # The test runner above can mock this function's dependencies.
    _main_logic "$@"
}

_main_logic() {
    prereq_checks "sudo" "systemctl"
    load_project_env "${SCRIPT_DIR}/.env"

    local command="$1"

    # --- Non-Interactive Argument Handling ---
    if [[ -n "$command" ]]; then
        case "$command" in
            -h|--help)
                show_help "verbose"
                ;; 
            -v|--view)
                if check_network_exposure; then echo "$STATUS_NETWORK"; else echo "$STATUS_LOCALHOST"; fi
                ;; 
            -e|--expose)
                ensure_root "Root privileges are required to modify systemd configuration." "$command"
                expose_to_network
                local exit_code=$?
                if [[ $exit_code -eq 2 ]]; then
                    if check_network_exposure; then echo "$STATUS_NETWORK"; else echo "$STATUS_LOCALHOST"; fi
                    exit 0
                fi
                verify_ollama_service &>/dev/null
                if check_network_exposure; then echo "$STATUS_NETWORK"; else echo "$STATUS_LOCALHOST"; fi
                ;; 
            -r|--restrict)
                ensure_root "Root privileges are required to modify systemd configuration." "$command"
                restrict_to_localhost
                local exit_code=$?
                if [[ $exit_code -eq 2 ]]; then
                    if check_network_exposure; then echo "$STATUS_NETWORK"; else echo "$STATUS_LOCALHOST"; fi
                    exit 0
                fi
                verify_ollama_service &>/dev/null
                if check_network_exposure; then echo "$STATUS_NETWORK"; else echo "$STATUS_LOCALHOST"; fi
                ;; 
            *)
                show_help
                printErrMsg "\nInvalid option: $command"
                exit 1
                ;; 
        esac
        exit 0
    fi

    # --- Interactive Menu ---
    printBanner "Ollama Network Configurator"
    wait_for_ollama_service
    print_current_status

    printMsg "\n${T_ULINE}Choose an option:${T_RESET}"
    printMsg "  ${T_BOLD}1, e)${T_RESET} ${C_L_YELLOW}(E)xpose to Network${T_RESET} (allow connections from Docker, etc.)"
    printMsg "  ${T_BOLD}2, r)${T_RESET} ${C_L_BLUE}(R)estrict to Localhost${T_RESET} (default, more secure)"
    printMsg "     ${T_BOLD}q)${T_RESET} (Q)uit without changing\n"
    printMsgNoNewline " ${T_QST_ICON} Your choice: "
    local choice
    choice=$(read_single_char)
    clear_current_line # Clear the "Your choice: " prompt line

    case "$choice" in
        1|e|E)
            printInfoMsg "${C_L_YELLOW}Option 1 selected: Expose to Network${T_RESET}"
            ensure_root "Root privileges are required to modify systemd configuration." "--expose"
            expose_to_network
            _after_change_verification
            ;; 
        2|r|R)
            printInfoMsg "${C_L_BLUE}Option 2 selected: Restrict to Localhost${T_RESET}"
            ensure_root "Root privileges are required to modify systemd configuration." "--restrict"
            restrict_to_localhost
            _after_change_verification
            ;; 
        q|Q|"$KEY_ESC")
            clear_current_line
            printOkMsg "Goodbye! No changes made."
            exit 0
            ;; 
        *)
            clear_current_line
            printErrMsg "Invalid option. Please press 1, 2, e, r, or q."
            exit 1
            ;; 
    esac
}

# Wrap the main call in a function to make it mockable for tests.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
