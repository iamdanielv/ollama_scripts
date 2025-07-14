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
        printMsg "${T_INFO_ICON} Checking for updates from GitHub... "
        local latest_version
        latest_version=$(get_latest_ollama_version)

        if [[ -z "$latest_version" ]]; then
            printMsg "${T_WARN}Could not fetch latest version.${T_RESET}"
            printMsg "    Proceeding with installation/update anyway."
        elif [[ "$installed_version" == "$latest_version" ]]; then
            printMsg "${T_OK_ICON} Already on the latest version (${latest_version})."
            exit 0
        else
            printMsg "${T_OK_ICON} New version available: ${C_L_BLUE}${latest_version}${T_RESET}"
        fi
    else
        printMsg "${T_INFO_ICON} 🤖 Ollama not found, proceeding with installation..."
    fi

    printMsg "Downloading 📥 and running the official Ollama install script..."
    # The following command downloads and executes a script from the internet.
    # This is a common practice for installers but carries a security risk.
    # For higher security, download the script, inspect it, and then run it manually.
    if ! curl -fsSL https://ollama.com/install.sh | sh; then
        printErrMsg "Ollama installation script failed to execute."
        exit 1
    fi
    printOkMsg "Ollama installation script finished."

    printMsg "${T_INFO_ICON} Verifying installation..."
    # Clear the shell's command lookup cache to find the new executable.
    hash -r

    sleep 1
    local post_install_version
    post_install_version=$(get_ollama_version)

    if [[ -z "$post_install_version" ]]; then
        printErrMsg "Ollama installation failed. The 'ollama' command is not available after installation."
        exit 1
    fi

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
}

# Run the main script logic
main "$@"
#    for i in {1..5}; do
