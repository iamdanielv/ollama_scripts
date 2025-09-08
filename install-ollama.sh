#!/bin/bash
# Install or update Ollama.

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

show_help() {
    printBanner "Ollama Installer/Updater"
    printMsg "Installs or updates Ollama on the local system."
    printMsg "If run without flags, enters interactive install/update mode."

    printMsg "\n${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [-v | -t | -h]"

    printMsg "\n${T_ULINE}Options:${T_RESET}"
    printMsg "  ${C_L_BLUE}-v, --version${T_RESET}   Displays the installed and latest available versions."
    printMsg "  ${C_L_BLUE}-t, --test${T_RESET}      Runs internal self-tests for script functions."
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
    if _check_command_exists "ollama"; then
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
    printInfoMsg "Checking network exposure for Ollama..."
    
    # Use the service checker from shared.sh. This will also start the service if needed.
    wait_for_ollama_service

    if check_network_exposure; then
        clear_lines_up 1
        printOkMsg "Ollama is already exposed to the network."
        return
    fi

    local override_file="/etc/systemd/system/ollama.service.d/10-expose-network.conf"
    printInfoMsg "To allow network access (e.g., from Docker),"
    printInfoMsg "Ollama can be configured to listen on all network interfaces."
    printInfoMsg "This creates a systemd override file at:\n    ${C_L_BLUE}${override_file}${T_RESET}"
    printInfoMsg "You can change this setting later by running: ${C_L_BLUE}./config-ollama.sh${T_RESET}"
    if ! prompt_yes_no "Expose Ollama to the network now?" "n"; then
        printInfoMsg "Skipping network exposure. Ollama will only be accessible from localhost."
        return
    fi

    expose_to_network
}

test_manage_network_exposure() {
    printTestSectionHeader "Testing manage_network_exposure function"

    # --- Mock dependencies ---
    # Mock all external functions called by manage_network_exposure to isolate its logic.
    wait_for_ollama_service() { :; } # Succeeds without doing anything.
    check_network_exposure() { [[ "$MOCK_IS_EXPOSED" == "true" ]]; }
    # The prompt_yes_no mock must read from stdin to simulate user input.
    prompt_yes_no() { read -r response; [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; }
    expose_to_network() { MOCK_EXPOSE_CALLED=true; }
    export -f wait_for_ollama_service check_network_exposure prompt_yes_no expose_to_network

    # --- Test Cases ---

    # Scenario 1: Network already exposed. Should exit early without prompting.
    export MOCK_IS_EXPOSED=true
    MOCK_EXPOSE_CALLED=false
    manage_network_exposure &>/dev/null
    _run_string_test "$MOCK_EXPOSE_CALLED" "false" "Skips when already exposed"

    # Scenario 2: Not exposed, user says 'y'. Should call expose_to_network.
    export MOCK_IS_EXPOSED=false
    MOCK_EXPOSE_CALLED=false
    # Provide 'y' as input to the mocked prompt_yes_no function using a "here string".
    manage_network_exposure &>/dev/null <<< 'y'
    _run_string_test "$MOCK_EXPOSE_CALLED" "true" "Calls expose_to_network when user confirms"

    # Scenario 3: Not exposed, user says 'n'. Should NOT call expose_to_network.
    export MOCK_IS_EXPOSED=false
    MOCK_EXPOSE_CALLED=false
    manage_network_exposure &>/dev/null <<< 'n'
    _run_string_test "$MOCK_EXPOSE_CALLED" "false" "Skips when user denies"
}

# A function to run internal self-tests for the script's logic.
run_tests() {
    printBanner "Running Self-Tests for install-ollama.sh"
    initialize_test_suite
    
    # --- compare_versions tests ---
    printTestSectionHeader "Testing compare_versions function"
    _run_compare_versions_test "0.1.10" "0.1.10" 0 "Equal versions"
    _run_compare_versions_test "0.1.9" "0.1.10" 2 "v1 < v2 (patch)"
    _run_compare_versions_test "0.1.10" "0.1.9" 1 "v1 > v2 (patch)"
    _run_compare_versions_test "0.1.10" "0.2.0" 2 "v1 < v2 (minor)"
    _run_compare_versions_test "0.2.0" "0.1.10" 1 "v1 > v2 (minor)"
    _run_compare_versions_test "0.9.0" "1.0.0" 2 "v1 < v2 (major)"
    _run_compare_versions_test "1.0.0" "0.9.0" 1 "v1 > v2 (major)"
    printTestSectionHeader "Edge Cases"
    _run_compare_versions_test "1.0" "1.0.1" 2 "v1 < v2 (different length)"
    _run_compare_versions_test "1.0.1" "1.0" 1 "v1 > v2 (different length)"
    _run_compare_versions_test "1.0.0" "" 1 "v1 > empty v2"
    _run_compare_versions_test "" "1.0.0" 2 "empty v1 < v2"

    # --- get_ollama_version tests ---
    printTestSectionHeader "Testing get_ollama_version function"
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
    printTestSectionHeader "Testing get_latest_ollama_version function"
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

    test_manage_network_exposure

    print_test_summary \
        "ollama" "command" "curl" \
        "wait_for_ollama_service" "check_network_exposure" \
        "expose_to_network" "prompt_yes_no"
}

# --- Main Execution ---

main() {
    load_project_env "${SCRIPT_DIR}/.env"

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
                    printInfoMsg "Installed: ${C_L_BLUE}${installed_version}${T_RESET}"
                else
                    printInfoMsg "Installed: ${C_L_YELLOW}Not installed${T_RESET}"
                fi

                printMsgNoNewline "${T_INFO_ICON} Latest:    "
                local latest_version
                latest_version=$(get_latest_ollama_version)
                if [[ -n "$latest_version" ]]; then
                    printMsg "${C_L_GREEN}${latest_version}${T_RESET}"
                else
                    printErrMsg "Could not fetch version from GitHub"
                fi
                exit 0
                ;; 
            -t|--test)
                run_tests
                exit 0
                ;; 
            *)
                show_help
                printErrMsg "Invalid option: $1"
                exit 1
                ;; 
        esac
    fi

    printBanner "Ollama Installer/Updater"

    prereq_checks "curl"
    
    local installed_version
    installed_version=$(get_ollama_version)

    if [[ -n "$installed_version" ]]; then
        printOkMsg "🤖 Ollama is installed (version: ${installed_version})."
        printMsgNoNewline "${T_INFO_ICON} Checking for latest version from GitHub... "
        local latest_version
        latest_version=$(get_latest_ollama_version)

        if [[ -z "$latest_version" ]]; then
            printWarnMsg "Could not fetch latest version. Will verify current installation."
        else
            printInfoMsg "${C_L_BLUE}${latest_version}${T_RESET}"
            compare_versions "$installed_version" "$latest_version"
            local comparison_result=$?
            if [[ $comparison_result -eq 2 ]]; then
                printOkMsg "New version available: ${C_L_BLUE}${latest_version}${T_RESET}"
                # Fall through to the installation block
            else
                # This block handles when the installed version is the same or newer.
                if [[ $comparison_result -eq 0 ]]; then
                    printOkMsg "You are on the latest version."
                else # $comparison_result -eq 1
                    printInfoMsg "Your installed version (${installed_version}) is newer than the latest release (${latest_version})."
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
        printInfoMsg "🤖 Ollama not found, proceeding with installation..."
    fi

    # From this point, we need root privileges to install/update files in system directories.
    ensure_root "Root privileges are required to install or update Ollama." "$@"

    printInfoMsg "The script will now download and execute the official installer from ${C_L_BLUE}https://ollama.com/install.sh${T_RESET}"
    printInfoMsg "    This is a standard installation method, but it involves running a script from the internet."
    if ! prompt_yes_no "Do you want to proceed?" "n"; then
        printInfoMsg "Installation cancelled by user."
        exit 0
    fi

    local installer_script
    # Declare separately to avoid masking mktemp's exit code with `local`.
    installer_script=$(mktemp)

    # Download the installer script using the spinner
    if ! run_with_spinner "Downloading the official Ollama installer" \
        curl -fsSL -o "$installer_script" https://ollama.com/install.sh; then
        rm -f "$installer_script"
        # Error message is printed by spinner function, no need for more output.
        exit 1
    fi

    printInfoMsg "Running the downloaded installer..."
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
    # Declare separately to avoid masking the command's exit code.
    post_install_version=$(get_ollama_version)

    if [[ -z "$post_install_version" ]]; then
        show_logs_and_exit "Ollama installation failed. The 'ollama' command is not available after installation."
    fi

    printInfoMsg "Verifying installation version..."
    if [[ "$installed_version" == "$post_install_version" ]]; then
        printOkMsg "Ollama installation script ran, but the version did not change."
        printMsg "    Current version: $post_install_version"
    elif [[ -n "$installed_version" ]]; then
        printOkMsg "Ollama updated successfully."
        printInfoMsg "    ${C_L_GRAY}Old: ${installed_version}${T_RESET} -> ${C_GREEN}New: ${post_install_version}${T_RESET}"
    else
        printOkMsg "Ollama installed successfully."
        printInfoMsg "    Version: $post_install_version"
    fi

    # Final verification that the service is up and running
    verify_ollama_service

    # Check and configure network exposure
    manage_network_exposure

    # Final message after install/update
    printOkMsg "Ollama installation/update process complete."
    printInfoMsg "    You can manage network settings at any time by running:"
    printInfoMsg "    ${C_L_BLUE}./config-ollama.sh${T_RESET}"
}

# Run the main script logic
main "$@"
