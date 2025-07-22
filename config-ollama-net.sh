#!/bin/bash
# Configure Ollama network exposure (localhost vs. network).

set -e
set -o pipefail

# Source common utilities
# shellcheck source=./shared.sh
if ! source "$(dirname "$0")/shared.sh"; then
    echo "Error: Could not source shared.sh. Make sure it's in the same directory." >&2
    exit 1
fi

# --- Helper Functions ---
print_current_status() {
    printMsg "\n${T_BOLD}Current Status:${T_RESET}"
    if check_network_exposure; then
        printMsg "  Ollama is currently ${C_L_YELLOW}EXPOSED to the network${T_RESET} (listening on 0.0.0.0)."
    else
        printMsg "  Ollama is currently ${C_L_BLUE}RESTRICTED to localhost${T_RESET} (listening on 127.0.0.1)."
    fi
}

# --- Main Logic ---
main() {
    # Handle the status-check flag '-v' before anything else.
    # This provides a simple, scriptable way to get the current state
    # and avoids the sudo prompt for a read-only operation.
    if [[ "$1" == "-v" ]]; then
        # This check will default to "localhost" if the service is not found
        # or if not on a systemd system, which is the correct unconfigured state.
        if check_network_exposure; then
            echo "network"
        else
            echo "localhost"
        fi
        exit 0
    fi

    ensure_root "Root privileges are required to modify systemd configuration." "$@"
    printBanner "Ollama Network Configurator"

    wait_for_ollama_service
    print_current_status

    printMsg "\n${T_ULINE}Choose an option:${T_RESET}"
    printMsg "  ${T_BOLD}1)${T_RESET} ${C_L_YELLOW}Expose to Network${T_RESET} (allow connections from Docker, etc.)"
    printMsg "  ${T_BOLD}2)${T_RESET} ${C_L_BLUE}Restrict to Localhost${T_RESET} (default, more secure)"
    printMsg "  ${T_BOLD}q)${T_RESET} Quit without changing\n"
    printMsgNoNewline " ${T_QST_ICON} Your choice: "
    local choice
    read -r choice || true
    local network_change=0

    case $choice in
        1)
            expose_to_network
            network_change=$?
            ;;
        2)
            restrict_to_localhost
            network_change=$?
            ;;
        *)
            if [[ "$choice" =~ ^[qQ]$ ]]; then
                # Handles 'q', 'Q'
                printMsg "\n Exiting. No changes made."
            else
                # Handle other invalid input
                printMsg "\n Invalid option '${choice}'. No changes made."
            fi
            exit 0
            ;;
    esac

    # Exit code 2 means no change was needed. The function already printed a message.
    if [[ $network_change -eq 2 ]]; then
        exit 0
    fi

    # If we get here, a change was made. Verify the service and show the new status.
    printMsg "\n${T_INFO_ICON} Verifying service after configuration change..."
    verify_ollama_service
    print_current_status
}

main "$@"