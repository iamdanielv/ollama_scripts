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

# --- Script Variables ---
readonly STATUS_NETWORK="network"
readonly STATUS_LOCALHOST="localhost"

# --- Helper Functions ---
show_help() {
    printMsg "Usage: $(basename "$0") [FLAG]"
    printMsg "Configures Ollama network exposure."
    printMsg "\nFlags:"
    printMsg "  -e, --expose    Expose Ollama to the network (listens on 0.0.0.0)"
    printMsg "  -r, --restrict  Restrict Ollama to localhost (listens on 127.0.0.1)"
    printMsg "  -v, --view      View the current network configuration"
    printMsg "  -h, --help      Show this help message"
    printMsg "\nIf no flag is provided, the script will run in interactive mode."
}

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
    local command="$1"

    # --- Non-Interactive Argument Handling ---
    if [[ -n "$command" ]]; then
        case "$command" in
            -h|--help)
                show_help
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
                printMsg "\n${T_ERR}Invalid option: $command${T_RESET}"
                show_help
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
    printMsg "  ${T_BOLD}1)${T_RESET} ${C_L_YELLOW}Expose to Network${T_RESET} (allow connections from Docker, etc.)"
    printMsg "  ${T_BOLD}2)${T_RESET} ${C_L_BLUE}Restrict to Localhost${T_RESET} (default, more secure)"
    printMsg "  ${T_BOLD}q)${T_RESET} Quit without changing\n"
    printMsgNoNewline " ${T_QST_ICON} Your choice: "
    local choice
    read -r choice || true

    case $choice in
        1)
            ensure_root "Root privileges are required to modify systemd configuration." "--expose"
            expose_to_network
            printMsg "\n${T_INFO_ICON} Verifying service after configuration change..."
            verify_ollama_service
            print_current_status
            ;;
        2)
            ensure_root "Root privileges are required to modify systemd configuration." "--restrict"
            restrict_to_localhost
            printMsg "\n${T_INFO_ICON} Verifying service after configuration change..."
            verify_ollama_service
            print_current_status
            ;;
        *)
            if [[ "$choice" =~ ^[qQ]$ ]]; then
                printMsg "\n Exiting. No changes made."
            else
                printMsg "\n Invalid option '${choice}'. No changes made."
            fi
            exit 0
            ;;
    esac
}

main "$@"