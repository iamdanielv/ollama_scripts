#!/bin/bash

# Checks the status of both the Ollama service and the OpenWebUI containers.

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

# --- Ollama Status ---
check_ollama_status() {
    printMsg "${T_BOLD}--- Ollama Status ---${T_RESET}"

    # 1. Check systemd service status
    if ! _is_systemd_system; then
        printMsg "  ${T_INFO_ICON} Service:  Not a systemd system. Skipping service check."
    elif ! _is_ollama_service_known; then
        printMsg "  ${T_INFO_ICON} Service:  Ollama systemd service not found."
    else
        # It is a systemd system and the service is known
        if systemctl is-active --quiet ollama.service; then
            printMsg "  ${T_OK_ICON} Service:  ${C_GREEN}Active${T_RESET} (via systemd)"
        else
            local state
            state=$(systemctl is-active ollama.service || true)
            printMsg "  ${T_ERR_ICON} Service:  ${C_RED}Inactive (${state})${T_RESET} (via systemd)"
        fi
    fi

    # 2. Check API responsiveness
    local ollama_port=${OLLAMA_PORT:-11434}
    local ollama_url="http://localhost:${ollama_port}"
    if check_endpoint_status "$ollama_url" 3; then
        printMsg "  ${T_OK_ICON} API:      ${C_GREEN}Responsive${T_RESET} at ${C_L_BLUE}${ollama_url}${T_RESET}"
    else
        printMsg "  ${T_ERR_ICON} API:      ${C_RED}Not Responding${T_RESET} at ${C_L_BLUE}${ollama_url}${T_RESET}"
    fi

    # 3. Check network exposure
    if ! _is_systemd_system; then
        printMsg "  ${T_INFO_ICON} Network:  Cannot determine exposure (not a systemd system)."
    elif ! _is_ollama_service_known; then
        printMsg "  ${T_INFO_ICON} Network:  Cannot determine exposure (Ollama service not found)."
    elif check_network_exposure; then
        printMsg "  ${T_OK_ICON} Network:  ${C_L_YELLOW}Exposed (0.0.0.0)${T_RESET}"
    else
        printMsg "  ${T_OK_ICON} Network:  ${C_L_BLUE}Localhost Only${T_RESET}"
    fi
}

# --- OpenWebUI Status ---
check_openwebui_status() {
    printMsg "\n${T_BOLD}--- OpenWebUI Status ---${T_RESET}"

    # Check for docker first
    if ! command -v docker &>/dev/null; then
        printMsg "  ${T_INFO_ICON} Docker not found. Skipping OpenWebUI check."
        return
    fi

    local compose_cmd
    compose_cmd=$(get_docker_compose_cmd)
    if [[ -z "$compose_cmd" ]]; then
        printMsg "  ${T_INFO_ICON} Docker Compose not found. Skipping OpenWebUI check."
        return
    fi

    local webui_dir
    webui_dir="$(dirname "$0")/openwebui"
    if [[ ! -d "$webui_dir" ]]; then
        printMsg "  ${T_ERR_ICON} Directory 'openwebui' not found. Cannot check status."
        return
    fi

    # Source .env file for custom ports
    if [[ -f "${webui_dir}/.env" ]]; then
        set -a
        # shellcheck source=/dev/null
        source "${webui_dir}/.env"
        set +a
    fi

    # 1. Check container status
    # Use --project-directory to avoid cd'ing
    if $compose_cmd --project-directory "$webui_dir" ps --filter "status=running" --services | grep -q "open-webui"; then
        printMsg "  ${T_OK_ICON} Container: ${C_GREEN}Running${T_RESET}"
    else
        printMsg "  ${T_ERR_ICON} Container: ${C_RED}Not Running${T_RESET}"
    fi

    # 2. Check UI responsiveness
    local webui_port=${OPEN_WEBUI_PORT:-3000}
    local webui_url="http://localhost:${webui_port}"
    if check_endpoint_status "$webui_url" 5; then
        printMsg "  ${T_OK_ICON} UI:        ${C_GREEN}Responsive${T_RESET} at ${C_L_BLUE}${webui_url}${T_RESET}"
    else
        printMsg "  ${T_ERR_ICON} UI:        ${C_RED}Not Responding${T_RESET} at ${C_L_BLUE}${webui_url}${T_RESET}"
    fi
}

main() {
    printBanner "Ollama & OpenWebUI Status"
    check_ollama_status
    check_openwebui_status
    printMsg "" # Final newline
}

main "$@"