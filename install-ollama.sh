#!/bin/bash
# Install or update Ollama.

# Source common utilities for colors and functions
# shellcheck source=./shared.sh
if ! source "$(dirname "$0")/shared.sh"; then
    echo "Error: Could not source shared.sh. Make sure it's in the same directory." >&2
    exit 1
fi

# --- Script Functions ---

show_help() {
    printBanner "Ollama Installer/Updater"
    printMsg "Installs or updates Ollama on the local system."
    printMsg "If run without flags, it enters an interactive install/update mode. Also includes self-tests."

    printMsg "\n${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [-v | -t | -h]"

    printMsg "\n${T_ULINE}Options:${T_RESET}"
    printMsg "  ${C_L_BLUE}-v, --version${T_RESET}   Displays the installed and latest available versions."
    printMsg "  ${C_L_BLUE}-t, --test${T_RESET}        Runs internal self-tests for script functions."
    printMsg "  ${C_L_BLUE}-h, --help${T_RESET}      Shows this help message."

    printMsg "\n${T_ULINE}Examples:${T_RESET}"
    printMsg "  ${C_GRAY}# Run the interactive installer/updater${T_RESET}"
    printMsg "  $(basename "$0")"
    printMsg "  ${C_GRAY}# Check the current and latest versions without installing${T_RESET}"
    printMsg "  $(basename "$0") -v"
    printMsg "  ${C_GRAY}# Run internal script tests${T_RESET}"
    printMsg "  $(basename "$0") -t"
}

# Function to get the current Ollama version.
# Returns the version string or an empty string if not installed.
get_ollama_version() {
    if command -v ollama &>/dev/null; then
        # ollama --version can sometimes include warning lines (often on stderr).
        # We need to reliably find the line containing the version string.
        # The output can be "ollama version is 0.9.6" or include warnings like
        # "Warning: client version is 0.9.6".
        # This command redirects stderr, finds the last line with "version is",
        # and extracts the version number (the last field).
        ollama --version 2>&1 | grep 'version is' | tail -n 1 | awk '{print $NF}'
    else
        echo ""
    fi
}

# Fetches the latest version tag from the Ollama GitHub repository.
# Uses curl and text processing to avoid a dependency on jq.
get_latest_ollama_version() {
    # The 'v' prefix is stripped from the tag name (e.g., v0.1.32 -> 0.1.32).
    curl --silent "https://api.github.com/repos/ollama/ollama/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/^v//'
}

# Compares two semantic versions (e.g., 0.1.10 vs 0.1.9).
# Returns:
#   0 if version1 == version2
#   1 if version1 > version2
#   2 if version1 < version2
compare_versions() {
    if [[ "$1" == "$2" ]]; then
        return 0
    fi

    # Use sort -V for robust version comparison.
    # The highest version will be the second line of the output.
    local highest
    highest=$(printf '%s\n' "$1" "$2" | sort -V | tail -n 1)

    if [[ "$highest" == "$1" ]]; then
        return 1 # v1 > v2
    else
        return 2 # v1 < v2
    fi
}

# Manages the network exposure configuration for Ollama.
# It checks if the configuration is needed and prompts the user before applying it.
manage_network_exposure() {
    printMsg "${T_INFO_ICON} Checking network exposure for Ollama..."

    # First, check if this is a systemd system
    if ! _is_systemd_system; then
        printMsg "    ${T_INFO_ICON} Not a systemd system. Skipping network exposure check."
        return
    fi

    # Then, check if the service exists, with retries, as systemd might need a moment
    # to recognize a newly installed service.
    printMsgNoNewline "    ${T_INFO_ICON} Looking for Ollama service"
    local ollama_found=false
    for i in {1..5}; do
        printMsgNoNewline "${C_L_BLUE}.${T_RESET}"
        if _is_ollama_service_known; then
            ollama_found=true
            break
        fi
        sleep 1
    done
    echo # Newline for the dots

    if ! $ollama_found; then
        printMsg "    ${T_INFO_ICON} Ollama service not found after 5 attempts. Skipping network exposure check."
        return # Not an error, just can't configure it.
    fi

    if check_network_exposure; then
        printOkMsg "Ollama is already exposed to the network."
        return
    fi

    local override_file="/etc/systemd/system/ollama.service.d/10-expose-network.conf"
    printMsg "${T_INFO_ICON} To allow network access (e.g., from Docker),"
    printMsg "${T_INFO_ICON} Ollama can be configured to listen on all network interfaces."
    printMsg "${T_INFO_ICON} This creates a systemd override file at:\n    ${C_L_BLUE}${override_file}${T_RESET}"
    printMsg "${T_INFO_ICON} You can change this setting later by running: ${C_L_BLUE}./config-ollama-net.sh${T_RESET}"
    printMsgNoNewline "\n    ${T_QST_ICON} Expose Ollama to the network now? (y/N) "
    local response
    read -r response || true
    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        printMsg "${T_INFO_ICON} Skipping network exposure. Ollama will only be accessible from localhost."
        return
    fi

    expose_to_network
}

# Helper to run a single test case for the run_tests function.
# It is defined at the script level to ensure it's available when called.
# It accesses the `test_count` and `failures` variables from its caller's scope.
# Usage: _run_compare_versions_test "v1" "v2" <expected_code> "description"
_run_compare_versions_test() {
    local v1="$1"
    local v2="$2"
    local expected_code="$3"
    local description="$4"
    ((test_count++))

    printMsgNoNewline "  Test: ${description}... "
    compare_versions "$v1" "$v2"
    local actual_code=$?
    if [[ $actual_code -eq $expected_code ]]; then
        printMsg "${C_L_GREEN}PASSED${T_RESET}"
    else
        printMsg "${C_RED}FAILED${T_RESET} (Expected: $expected_code, Got: $actual_code)"
        ((failures++))
    fi
}

# Helper to run a single return code test case.
# Usage: _run_test "command_to_run" <expected_code> "description"
_run_test() {
    local cmd_string="$1"
    local expected_code="$2"
    local description="$3"
    ((test_count++))

    printMsgNoNewline "  Test: ${description}... "
    # Run command in a subshell to not affect the test script's state
    (eval "$cmd_string") &>/dev/null # Redirect output to keep test output clean
    local actual_code=$?
    if [[ $actual_code -eq $expected_code ]]; then
        printMsg "${C_L_GREEN}PASSED${T_RESET}"
    else
        printMsg "${C_RED}FAILED${T_RESET} (Expected: $expected_code, Got: $actual_code)"
        ((failures++))
    fi
}

# Helper to run a single string comparison test case for the run_tests function.
# It accesses the `test_count` and `failures` variables from its caller's scope.
# Usage: _run_string_test "actual_output" "expected_output" "description"
_run_string_test() {
    local actual="$1"
    local expected="$2"
    local description="$3"
    ((test_count++))

    printMsgNoNewline "  Test: ${description}... "
    if [[ "$actual" == "$expected" ]]; then
        printMsg "${C_L_GREEN}PASSED${T_RESET}"
    else
        printMsg "${C_RED}FAILED${T_RESET} (Expected: '$expected', Got: '$actual')"
        ((failures++))
    fi
}

test_manage_network_exposure() {
    printMsg "\n${T_ULINE}Testing manage_network_exposure function:${T_RESET}"

    # --- Mock dependencies ---
    _is_systemd_system() { [[ "$MOCK_IS_SYSTEMD" == "true" ]]; }
    _is_ollama_service_known() { [[ "$MOCK_SERVICE_KNOWN" == "true" ]]; }
    check_network_exposure() { [[ "$MOCK_IS_EXPOSED" == "true" ]]; }

    # Mock the function that performs the action, and track if it was called.
    expose_to_network() { MOCK_EXPOSE_CALLED=true; }
    export -f _is_systemd_system _is_ollama_service_known check_network_exposure expose_to_network

    # --- Test Cases ---

    # Scenario 1: Not a systemd system. Should exit early.
    export MOCK_IS_SYSTEMD=false
    MOCK_EXPOSE_CALLED=false
    manage_network_exposure &>/dev/null
    _run_string_test "$MOCK_EXPOSE_CALLED" "false" "Skips on non-systemd system"

    # Scenario 2: Ollama service not found. Should exit early.
    export MOCK_IS_SYSTEMD=true
    export MOCK_SERVICE_KNOWN=false
    MOCK_EXPOSE_CALLED=false
    manage_network_exposure &>/dev/null
    _run_string_test "$MOCK_EXPOSE_CALLED" "false" "Skips when service is not found"

    # Scenario 3: Network already exposed. Should exit early.
    export MOCK_IS_SYSTEMD=true
    export MOCK_SERVICE_KNOWN=true
    export MOCK_IS_EXPOSED=true
    MOCK_EXPOSE_CALLED=false
    manage_network_exposure &>/dev/null
    _run_string_test "$MOCK_EXPOSE_CALLED" "false" "Skips when already exposed"

    # Scenario 4: Not exposed, user says 'y'. Should call expose_to_network.
    export MOCK_IS_EXPOSED=false
    MOCK_EXPOSE_CALLED=false
    # Use a "here string" instead of a pipe to avoid a subshell.
    manage_network_exposure &>/dev/null <<< 'y'
    _run_string_test "$MOCK_EXPOSE_CALLED" "true" "Calls expose_to_network when user confirms"

    # Scenario 5: Not exposed, user says 'n'. Should NOT call expose_to_network.
    MOCK_EXPOSE_CALLED=false
    # Use a "here string" here as well.
    manage_network_exposure &>/dev/null <<< 'n'
    _run_string_test "$MOCK_EXPOSE_CALLED" "false" "Skips when user denies"
}

# A function to run internal self-tests for the script's logic.
run_tests() {
    printBanner "Running Self-Tests"
    # These are not 'local' so the _run_test helper function can access them.
    # This is a common pattern in shell scripting for test helpers.
    test_count=0
    failures=0

    # --- compare_versions tests ---
    printMsg "\n${T_ULINE}Testing compare_versions function:${T_RESET}"
    _run_compare_versions_test "0.1.10" "0.1.10" 0 "Equal versions"
    _run_compare_versions_test "0.1.9" "0.1.10" 2 "v1 < v2 (patch)"
    _run_compare_versions_test "0.1.10" "0.1.9" 1 "v1 > v2 (patch)"
    _run_compare_versions_test "0.1.10" "0.2.0" 2 "v1 < v2 (minor)"
    _run_compare_versions_test "0.2.0" "0.1.10" 1 "v1 > v2 (minor)"
    _run_compare_versions_test "0.9.0" "1.0.0" 2 "v1 < v2 (major)"
    _run_compare_versions_test "1.0.0" "0.9.0" 1 "v1 > v2 (major)"
    printMsg "  --- Edge Cases ---"
    _run_compare_versions_test "1.0" "1.0.1" 2 "v1 < v2 (different length)"
    _run_compare_versions_test "1.0.1" "1.0" 1 "v1 > v2 (different length)"
    _run_compare_versions_test "1.0.0" "" 1 "v1 > empty v2"
    _run_compare_versions_test "" "1.0.0" 2 "empty v1 < v2"

    # --- get_ollama_version tests ---
    printMsg "\n${T_ULINE}Testing get_ollama_version function:${T_RESET}"
    # To test get_ollama_version, we mock the `ollama` and `command` commands.
    # We use environment variables to control the mock's behavior for each test case.
    ollama() {
        if [[ "$1" == "--version" ]]; then
            echo -e "$OLLAMA_MOCK_OUTPUT"
        fi
    }
    export -f ollama
    command() {
        if [[ "$1" == "-v" && "$2" == "ollama" ]]; then
            [[ "$COMMAND_V_MOCK_RETURN" -eq 0 ]] && return 0 || return 1
        else
            /usr/bin/command "$@" # Use real command for other calls
        fi
    }
    export -f command

    export COMMAND_V_MOCK_RETURN=0
    export OLLAMA_MOCK_OUTPUT="ollama version is 0.1.25"
    _run_string_test "$(get_ollama_version)" "0.1.25" "Parsing simple version string"

    export OLLAMA_MOCK_OUTPUT="Warning: client version is 0.1.26\nollama version is 0.1.26"
    _run_string_test "$(get_ollama_version)" "0.1.26" "Parsing version with stderr warning"

    export OLLAMA_MOCK_OUTPUT="some other output"
    _run_string_test "$(get_ollama_version)" "" "Parsing output with no version"

    export COMMAND_V_MOCK_RETURN=1
    _run_string_test "$(get_ollama_version)" "" "Command not found"

    # --- get_latest_ollama_version tests ---
    printMsg "\n${T_ULINE}Testing get_latest_ollama_version function:${T_RESET}"
    # To test get_latest_ollama_version, we mock the `curl` command.
    curl() {
        echo -e "$CURL_MOCK_OUTPUT"
    }
    export -f curl

    export CURL_MOCK_OUTPUT='some junk\n"tag_name": "v0.1.29",\nmore junk'
    _run_string_test "$(get_latest_ollama_version)" "0.1.29" "Parsing valid GitHub API response"

    export CURL_MOCK_OUTPUT='no tag name here'
    _run_string_test "$(get_latest_ollama_version)" "" "Parsing invalid API response"

    export CURL_MOCK_OUTPUT=""
    _run_string_test "$(get_latest_ollama_version)" "" "Handling empty API response"

    # --- manage_network_exposure tests ---
    test_manage_network_exposure

    # --- Cleanup Mocks ---
    # Unset the mock functions to restore original behavior
    unset -f ollama command curl
    unset -f _is_systemd_system _is_ollama_service_known check_network_exposure expose_to_network

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

# --- Main Execution ---

main() {
    load_project_env # Source openwebui/.env for custom ports

    # --- Non-Interactive Argument Handling ---
    if [[ -n "$1" ]]; then
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                printBanner "Ollama Version"
                local installed_version
                installed_version=$(get_ollama_version)
                if [[ -n "$installed_version" ]]; then
                    printMsg "  ${T_INFO_ICON} Installed: ${C_L_BLUE}${installed_version}${T_RESET}"
                else
                    printMsg "  ${T_INFO_ICON} Installed: ${C_L_YELLOW}Not installed${T_RESET}"
                fi

                printMsgNoNewline "  ${T_INFO_ICON} Latest:    "
                local latest_version
                latest_version=$(get_latest_ollama_version)
                if [[ -n "$latest_version" ]]; then
                    printMsg "${C_L_GREEN}${latest_version}${T_RESET}"
                else
                    printMsg "${C_RED}Could not fetch from GitHub${T_RESET}"
                fi
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

    printBanner "Ollama Installer/Updater"

    printMsg "${T_INFO_ICON} Checking prerequisites..."
    if ! command -v curl &>/dev/null; then
        printErrMsg "curl is not installed. Please install it to continue."
        exit 1
    fi
    #printOkMsg "curl is installed."

    # Remove the "Checking for prerequisites..." line
    clear_lines_up 1
    
    local installed_version
    installed_version=$(get_ollama_version)

    if [[ -n "$installed_version" ]]; then
        printOkMsg "🤖 Ollama is already installed (version: ${installed_version})."
        printMsgNoNewline "${T_INFO_ICON} Checking for latest version from GitHub... "
        local latest_version
        latest_version=$(get_latest_ollama_version)

        if [[ -z "$latest_version" ]]; then
            printMsg "${T_WARN_ICON} Could not fetch latest version. Will verify current installation."
        else
            printMsg "${C_L_BLUE}${latest_version}${T_RESET}"
            compare_versions "$installed_version" "$latest_version"
            local comparison_result=$?
            if [[ $comparison_result -eq 2 ]]; then
                printMsg "${T_OK_ICON} New version available: ${C_L_BLUE}${latest_version}${T_RESET}"
                # Fall through to the installation block
            else
                # This block handles when the installed version is the same or newer.
                if [[ $comparison_result -eq 0 ]]; then
                    printMsg "${T_OK_ICON} You are on the latest version."
                else # $comparison_result -eq 1
                    printMsg "${T_INFO_ICON} Your installed version (${installed_version}) is newer than the latest release (${latest_version})."
                fi

                wait_for_ollama_service
                verify_ollama_service
                manage_network_exposure # Check and optionally configure network exposure

                # Check final network state to include in the summary message.
                local net_stat_msg
                if check_network_exposure; then
                    net_stat_msg="(Network Exposed)"
                else
                    net_stat_msg="(Localhost Only)"
                fi

                if [[ $comparison_result -eq 0 ]]; then
                    printOkMsg "Ollama is up-to-date and running correctly. ${C_L_YELLOW}${net_stat_msg}${T_RESET}"
                else
                    printOkMsg "Ollama is running correctly. ${C_L_YELLOW}${net_stat_msg}${T_RESET}"
                fi
                exit 0
            fi
        fi
    else
        printMsg "${T_INFO_ICON} 🤖 Ollama not found, proceeding with installation..."
    fi

    # From this point, we need root privileges to install/update files in system directories.
    ensure_root "Root privileges are required to install or update Ollama." "$@"

    printMsg "${T_QST_ICON} The script will now download and execute the official installer from ${C_L_BLUE}https://ollama.com/install.sh${T_RESET}"
    printMsg "    This is a standard installation method, but it involves running a script from the internet."
    printMsgNoNewline "    ${T_QST_ICON} Do you want to proceed? (y/N) "
    read -r response || true
    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        printMsg "${T_INFO_ICON} Installation cancelled by user."
        exit 0
    fi

    local installer_script
    installer_script=$(mktemp)

    # Download the installer script using the spinner
    if ! run_with_spinner "Downloading the official Ollama installer" \
        curl -fsSL -o "$installer_script" https://ollama.com/install.sh; then
        rm -f "$installer_script"
        # Error message is printed by spinner function, no need for more output.
        exit 1
    fi

    printMsg "${T_INFO_ICON} Running the downloaded installer..."
    # The installer output should be shown to the user.
    if ! sh "$installer_script"; then
        rm -f "$installer_script"
        printErrMsg "Ollama installation script failed to execute."
        exit 1
    fi
    rm -f "$installer_script"
    printOkMsg "Ollama installation script finished."

    # Clear the shell's command lookup cache to find the new executable.
    hash -r
    local post_install_version
    post_install_version=$(get_ollama_version)

    if [[ -z "$post_install_version" ]]; then
        show_logs_and_exit "Ollama installation failed. The 'ollama' command is not available after installation."
    fi

    printMsg "${T_INFO_ICON} Verifying installation version..."
    if [[ "$installed_version" == "$post_install_version" ]]; then
        printOkMsg "Ollama installation script ran, but the version did not change."
        printMsg "    Current version: $post_install_version"
    elif [[ -n "$installed_version" ]]; then
        printOkMsg "Ollama updated successfully."
        printMsg "    ${C_GRAY}Old: ${installed_version}${T_RESET} -> ${C_GREEN}New: ${post_install_version}${T_RESET}"
    else
        printOkMsg "Ollama installed successfully."
        printMsg "    Version: $post_install_version"
    fi

    # Final verification that the service is up and running
    verify_ollama_service

    # Check and configure network exposure
    manage_network_exposure

    # Final message after install/update
    printOkMsg "Ollama installation/update process complete."
    printMsg "    You can manage network settings at any time by running:"
    printMsg "    ${C_L_BLUE}./config-ollama-net.sh${T_RESET}"
}

# Run the main script logic
main "$@"
