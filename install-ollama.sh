#!/bin/bash
# Install or update Ollama.

# Exit immediately if a command exits with a non-zero status.
set -e
# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -o pipefail

# Source common utilities for colors and functions
# shellcheck source=./shared.sh
if ! source "$(dirname "$0")/shared.sh"; then
    echo "Error: Could not source shared.sh. Make sure it's in the same directory." >&2
    exit 1
fi

# --- Script Functions ---

show_help() {
    printMsg "Usage: $(basename "$0") [FLAG]"
    printMsg "Installs or updates Ollama."
    printMsg "\nFlags:"
    printMsg "  -v, --version   Show the currently installed and latest available versions."
    printMsg "  -h, --help      Show this help message"
    printMsg "\nIf no flag is provided, the script will run in interactive install/update mode."
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
    # If versions are identical, return 0
    if [[ "$1" == "$2" ]]; then
        return 0
    fi
    # Use sort -V to compare versions. The highest version will be last.
    local latest
    latest=$(printf '%s\n' "$1" "$2" | sort -V | tail -n1)
    if [[ "$1" == "$latest" ]]; then
        return 1 # ver1 is greater
    else
        return 2 # ver2 is greater
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

# --- Main Execution ---

main() {
    # --- Non-Interactive Argument Handling ---
    if [[ -n "$1" ]]; then
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                printBanner "Ollama Version Check"
                local installed_version
                installed_version=$(get_ollama_version)
                if [[ -n "$installed_version" ]]; then
                    printMsg "  ${T_INFO_ICON} Installed version: ${C_L_BLUE}${installed_version}${T_RESET}"
                else
                    printMsg "  ${T_INFO_ICON} Installed version: ${C_L_YELLOW}Not installed${T_RESET}"
                fi

                printMsgNoNewline "  ${T_INFO_ICON} Latest version:    "
                local latest_version
                latest_version=$(get_latest_ollama_version)
                if [[ -n "$latest_version" ]]; then
                    printMsg "${C_L_GREEN}${latest_version}${T_RESET}"
                else
                    printMsg "${C_RED}Could not fetch from GitHub${T_RESET}"
                fi
                exit 0
                ;;
            *)
                printMsg "\n${T_ERR}Invalid option: $1${T_RESET}"
                show_help
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
    printOkMsg "curl is installed."

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

    printMsg "Downloading 📥 and running the official Ollama install script..."
    if ! curl -fsSL https://ollama.com/install.sh | sh; then
        printErrMsg "Ollama installation script failed to execute."
        exit 1
    fi
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
