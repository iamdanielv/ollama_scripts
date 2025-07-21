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

# Function to get the current Ollama version.
# Returns the version string or an empty string if not installed.
get_ollama_version() {
    if command -v ollama &>/dev/null; then
        # ollama --version outputs "ollama version is 0.1.32"
        # We extract the last field to get just the version number.
        ollama --version | awk '{print $NF}'
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

# Checks if Ollama is configured to be exposed to the network.
# Returns 0 if exposed, 1 if not.
check_network_exposure() {
    local current_host_config
    current_host_config=$(systemctl show --no-pager --property=Environment ollama 2>/dev/null || echo "")
    if echo "$current_host_config" | grep -q "OLLAMA_HOST=0.0.0.0"; then
        return 0 # Is exposed
    else
        return 1 # Is not exposed
    fi
}

# Applies the systemd override to expose Ollama to the network.
# This function requires sudo to run its commands.
expose_to_network() {
    local override_dir="/etc/systemd/system/ollama.service.d"
    local override_file="${override_dir}/10-expose-network.conf"

    printMsg "${T_INFO_ICON} Creating systemd override to expose Ollama to network..."

    if ! sudo mkdir -p "$override_dir"; then
        printErrMsg "Failed to create override directory: $override_dir"
        return 1
    fi

    local override_content="[Service]\nEnvironment=\"OLLAMA_HOST=0.0.0.0\""
    if ! echo -e "$override_content" | sudo tee "$override_file" >/dev/null; then
        printErrMsg "Failed to write override file: $override_file"
        return 1
    fi

    printMsg "${T_INFO_ICON} Reloading systemd daemon and restarting Ollama service..."
    if ! sudo systemctl daemon-reload; then
        printErrMsg "Failed to reload systemd daemon."
        return 1
    fi
    if ! sudo systemctl restart ollama; then
        printErrMsg "Failed to restart Ollama service."
        return 1
    fi

    printOkMsg "Ollama has been configured to be exposed to the network and was restarted."
    return 0
}

# Manages the network exposure configuration for Ollama.
# It checks if the configuration is needed and prompts the user before applying it.
manage_network_exposure() {
    printMsg "${T_INFO_ICON} Checking network exposure for Ollama..."

    # Check if systemd is running and if the ollama service is installed.
    if ! command -v systemctl &>/dev/null || ! systemctl list-unit-files --type=service | grep -q '^ollama\.service'; then
        printMsg "    ${T_INFO_ICON} Not a systemd system or Ollama service not found. Skipping network exposure check."
        return
    fi

    if check_network_exposure; then
        printOkMsg "Ollama is already exposed to the network."
        return
    fi

    local override_file="/etc/systemd/system/ollama.service.d/10-expose-network.conf"
    printMsg "${T_QST_ICON} To allow network access to Ollama (from Docker), \n    the script can configure it to listen on all interfaces (0.0.0.0)."
    printMsg "    This will create a systemd override file at:\n    \t${C_L_BLUE}${override_file}${T_RESET}"
    printMsg "    This requires sudo privileges."
    printMsgNoNewline "    ${T_QST_ICON} Do you want to continue? (y/N) "
    local response
    read -r response
    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        printMsg "${T_INFO_ICON} Ollama service change cancelled by user."
        return
    fi

    expose_to_network
}

# --- Main Execution ---

main() {
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

                verify_ollama_service
                manage_network_exposure # Check and optionally configure network exposure

                if [[ $comparison_result -eq 0 ]]; then
                    printOkMsg "Ollama is up-to-date and running correctly."
                else
                    printOkMsg "Ollama is running correctly."
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
    read -r response
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
}

# Run the main script logic
main "$@"
