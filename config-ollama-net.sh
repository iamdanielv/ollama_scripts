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

# --- Main Logic ---
main() {
    ensure_root "Root privileges are required to modify systemd configuration." "$@"
    printBanner "Ollama Network Configurator"

    wait_for_ollama_service

    while true; do
        printMsg "\n\n${T_BOLD}Current Status:${T_RESET}"
        if check_network_exposure; then
            printMsg "  Ollama is currently ${C_L_YELLOW}EXPOSED to the network${T_RESET} (listening on 0.0.0.0)."
        else
            printMsg "  Ollama is currently ${C_L_BLUE}RESTRICTED to localhost${T_RESET} (listening on 127.0.0.1)."
        fi

        printMsg "\n${T_ULINE}Choose an option:${T_RESET}"
        printMsg "  ${T_BOLD}1)${T_RESET} ${C_L_YELLOW}Expose to Network${T_RESET} (allow connections from Docker, etc.)"
        printMsg "  ${T_BOLD}2)${T_RESET} ${C_L_BLUE}Restrict to Localhost${T_RESET} (default, more secure)"
        printMsg "  ${T_BOLD}q)${T_RESET} Quit"
        printMsgNoNewline "${T_QST_ICON} Your choice: "
        local choice
        read -r choice

        case $choice in
            1) expose_to_network ;;
            2) restrict_to_localhost ;;
            [qQ]) printMsg "Exiting."; break ;;
            *) printErrMsg "Invalid option. Please try again." ;;
        esac
    done
}

main "$@"