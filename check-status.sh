#!/bin/bash

# Checks the status of both the Ollama service and the OpenWebUI containers.

# Exit immediately if a command exits with a non-zero status.
#set -e
# The return value of a pipeline is the status of the last command to exit with a non-zero status.
#set -o pipefail

# Source common utilities for colors and functions
# shellcheck source=./shared.sh
if ! source "$(dirname "$0")/shared.sh"; then
    echo "Error: Could not source shared.sh. Make sure it's in the same directory." >&2
    exit 1
fi

show_help() {
    printBanner "Ollama & OpenWebUI Status Checker"
    printMsg "Checks the status of the Ollama service and OpenWebUI containers."
    printMsg "It can also list the installed Ollama models."

    printMsg "\n${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [-m | -h]"

    printMsg "\n${T_ULINE}Options:${T_RESET}"
    printMsg "  ${C_L_BLUE}-m, --models${T_RESET}   List all installed Ollama models."
    printMsg "  ${C_L_BLUE}-h, --help${T_RESET}      Shows this help message."

    printMsg "\n${T_ULINE}Examples:${T_RESET}"
    printMsg "  ${C_GRAY}# Run the standard status check${T_RESET}"
    printMsg "  $(basename "$0")"
    printMsg "  ${C_GRAY}# List installed models${T_RESET}"
    printMsg "  $(basename "$0") --models"
}

# --- Ollama Status ---
check_ollama_status() {
    printMsg "${T_BOLD}--- Ollama Status ---${T_RESET}"

    local is_systemd=false
    local service_known=false
    if _is_systemd_system; then
        is_systemd=true
        if _is_ollama_service_known; then
            service_known=true
        fi
    fi

    # 1. Check systemd service status
    if ! $is_systemd; then
        printMsg "  ${T_INFO_ICON} Service:  Not a systemd system. Skipping service check."
    elif ! $service_known; then
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
    if check_endpoint_status "$ollama_url" 3; then # 3-second timeout
        printMsg "  ${T_OK_ICON} API:      ${C_GREEN}Responsive${T_RESET} at ${C_L_BLUE}${ollama_url}${T_RESET}"
    else
        printMsg "  ${T_ERR_ICON} API:      ${C_RED}Not Responding${T_RESET} at ${C_L_BLUE}${ollama_url}${T_RESET}"
    fi

    # 3. Check network exposure
    if ! $is_systemd; then
        printMsg "  ${T_INFO_ICON} Network:  Cannot determine exposure (not a systemd system)."
    elif ! $service_known; then
        printMsg "  ${T_INFO_ICON} Network:  Cannot determine exposure (Ollama service not found)."
    elif check_network_exposure; then
        printMsg "  ${T_OK_ICON} Network:  ${C_L_YELLOW}Exposed (0.0.0.0)${T_RESET}"
    else
        printMsg "  ${T_OK_ICON} Network:  ${C_L_BLUE}Localhost Only${T_RESET}"
    fi
}

# --- GPU Status ---
check_gpu_status() {
    # Only run if nvidia-smi is available
    if ! command -v nvidia-smi &>/dev/null; then
        return
    fi

    printMsg "\n${T_BOLD}--- GPU Status (NVIDIA) ---${T_RESET}"

    # Use a timeout to prevent the script from hanging if nvidia-smi is slow
    local smi_output
        # nvidia-smi has a bug where querying driver_version and cuda_version can fail.
    # We'll get them separately for robustness.
    local driver_version cuda_version
    driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits | head -n 1)
    cuda_version=$(nvidia-smi | grep -oP 'CUDA Version: \K[^ ]+' | head -n 1)
    
    printMsg "  ${T_INFO_ICON} Driver:   ${C_L_BLUE}${driver_version:-N/A}${T_RESET} (CUDA: ${C_L_BLUE}${cuda_version:-N/A}${T_RESET})"

    # Use a timeout to prevent the script from hanging if nvidia-smi is slow
    local smi_output
    smi_output=$(timeout 5 nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu,temperature.gpu --format=csv,noheader,nounits)

    if [[ -z "$smi_output" ]]; then
        printMsg "  ${T_ERR_ICON} Could not retrieve GPU information from nvidia-smi."
        return
    fi

    # The query command will output one line per GPU. We'll process each one.
    local gpu_index=0
    while IFS=',' read -r gpu_name mem_used mem_total gpu_util temp_gpu; do
        # Trim leading/trailing whitespace that might sneak in
        gpu_name=$(echo "$gpu_name" | xargs)
        mem_used=$(echo "$mem_used" | xargs)
        mem_total=$(echo "$mem_total" | xargs)
        gpu_util=$(echo "$gpu_util" | xargs)
        temp_gpu=$(echo "$temp_gpu" | xargs)

        printMsg "  ${T_OK_ICON} GPU ${gpu_index}:    ${C_L_CYAN}${gpu_name}${T_RESET}"
        printMsg "      - Memory: ${C_L_YELLOW}${mem_used} MiB / ${mem_total} MiB${T_RESET}"
        printMsg "      - Usage:  ${C_L_YELLOW}${gpu_util}%${T_RESET} (Temp: ${C_L_YELLOW}${temp_gpu}°C${T_RESET})"
        ((gpu_index++))
    done <<< "$smi_output"
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

# Prints a list of all installed Ollama models.
print_ollama_models() {
    printBanner "Installed Ollama Models"

    # 1. Check prerequisites
    check_jq_installed
    verify_ollama_api_responsive # This handles the API check and exits on failure

    # 2. Fetch and display models
    printMsg "${T_INFO_ICON} Querying for installed models..." >&2
    local models_json
    if ! models_json=$(get_ollama_models_json); then
        printErrMsg "Failed to fetch model list from Ollama API. The service may be down or the response was invalid."
        exit 1
    fi

    # Overwrite the querying message, this reduces visual clutter 
    clear_lines_up 1

    print_ollama_models_table "$models_json"
}

main() {
    load_project_env # Source openwebui/.env for custom ports

    if [[ -n "$1" ]]; then
        case "$1" in
            -m|--models) print_ollama_models; exit 0 ;;
            -h|--help)   show_help; exit 0 ;;
            *)           printMsg "\n${T_ERR}Invalid option: $1${T_RESET}"; show_help; exit 1 ;;
        esac
    fi

    printBanner "Ollama & OpenWebUI Status"
    check_ollama_status
    check_gpu_status
    check_openwebui_status
    printMsg "" # Final newline
}

main "$@"