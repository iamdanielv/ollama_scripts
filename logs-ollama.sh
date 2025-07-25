#!/bin/bash
# View logs for the Ollama systemd service.

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

show_help() {
    printBanner "Ollama Log Viewer"
    printMsg "A wrapper for 'journalctl -u ollama.service' to easily view logs."
    printMsg "By default, it opens logs in a searchable pager (like 'less')."
    printMsg "All arguments are passed directly to 'journalctl'."

    printMsg "\n${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [journalctl_options]"

    printMsg "\n${T_ULINE}Common Options:${T_RESET}"
    printMsg "  ${C_L_BLUE}-f${T_RESET}               Follow logs in real-time (press Ctrl+C to stop)."
    printMsg "  ${C_L_BLUE}-n <lines>${T_RESET}       Show the last N lines (e.g., -n 100)."
    printMsg "  ${C_L_BLUE}--since <time>${T_RESET}   Show logs since a specific time (e.g., '1 hour ago')."
    printMsg "  ${C_L_BLUE}-h, --help${T_RESET}       Show this help message."

    printMsg "\n${T_ULINE}Examples:${T_RESET}"
    printMsg "  ${C_GRAY}# View and search all logs (press '/' to search, 'q' to quit)${T_RESET}"
    printMsg "  $(basename "$0")"
    printMsg "\n  ${C_GRAY}# Follow logs in real-time${T_RESET}"
    printMsg "  $(basename "$0") -f"
    printMsg "\n  ${C_GRAY}# Show the last 100 lines${T_RESET}"
    printMsg "  $(basename "$0") -n 100"
}

main() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_help
        exit 0
    fi

    if ! _is_systemd_system; then
        printErrMsg "This script requires a systemd-based system to view service logs with 'journalctl'."
        exit 1
    fi

    if ! _is_ollama_service_known; then
        printErrMsg "Ollama systemd service ('ollama.service') not found."
        printMsg "    ${T_INFO_ICON} Please run ${C_L_BLUE}./install-ollama.sh${T_RESET} to install it."
        exit 1
    fi

    printMsg "${T_INFO_ICON} Showing logs for ${C_L_BLUE}ollama.service${T_RESET}..."
    # Use "$*" to show the user-provided args exactly as they typed them.
    printMsg "${T_INFO_ICON} Command: ${C_GRAY}journalctl -u ollama.service $*${T_RESET}"
    printMsg "${C_BLUE}${DIV}${T_RESET}"

    exec journalctl -u ollama.service "$@"
}

main "$@"