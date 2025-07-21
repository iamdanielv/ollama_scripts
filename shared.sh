#!/bin/bash
export C_RED='\e[31m'
export C_GREEN='\e[32m'
export C_YELLOW='\e[33m'
export C_BLUE='\e[34m'
export C_MAGENTA='\e[35m'
export C_CYAN='\e[36m'
export C_WHITE='\e[37m'
export C_GRAY='\e[30;1m'
export C_L_RED='\e[31;1m'
export C_L_GREEN='\e[32;1m'
export C_L_YELLOW='\e[33;1m'
export C_L_BLUE='\e[34;1m'
export C_L_MAGENTA='\e[35;1m'
export C_L_CYAN='\e[36;1m'
export C_L_WHITE='\e[37;1m'

export T_RESET='\e[0m'
export T_BOLD='\e[1m'
export T_ULINE='\e[4m'

export T_ERR="${T_BOLD}\e[31;1m"
export T_ERR_ICON="[${T_BOLD}${C_RED}✗${T_RESET}]"

export T_OK_ICON="[${T_BOLD}${C_GREEN}✓${T_RESET}]"
export T_INFO_ICON="[${T_BOLD}${C_YELLOW}i${T_RESET}]"
export T_WARN_ICON="[${T_BOLD}${C_YELLOW}!${T_RESET}]"
export T_QST_ICON="[${T_BOLD}${C_L_CYAN}?${T_RESET}]"

export DIV="-------------------------------------------------------------------------------"

function printMsg() {
  echo -e "${1}"
}

function printMsgNoNewline() {
  echo -n -e "${1}"
}

function printDatedMsgNoNewLine() {
  echo -n -e "$(getPrettyDate) ${1}"
}

function printErrMsg() {
  printMsg "${T_ERR_ICON}${T_ERR} ${1} ${T_RESET}"
}

function printOkMsg() {
  printMsg "${T_OK_ICON} ${1}${T_RESET}"
}

function getFormattedDate() {
  date +"%Y-%m-%d %I:%M:%S"
}

function getPrettyDate() {
  echo "${C_BLUE}$(getFormattedDate)${T_RESET}"
}

function printBanner() {
  printMsg "${C_BLUE}${DIV}"
  printMsg " ${1}"
  printMsg "${DIV}${T_RESET}"
}

# Checks if the Ollama CLI is installed and exits if it's not.
check_ollama_installed() {
    printMsg "${T_INFO_ICON} Checking for Ollama installation..."
    if ! command -v ollama &> /dev/null; then
        printErrMsg "Ollama is not installed."
        printMsg "    ${T_INFO_ICON} Please run ${C_L_BLUE}./installollama.sh${T_RESET} to install it."
        exit 1
    fi
    printOkMsg "Ollama is installed."
}

# Checks for Docker and Docker Compose. Exits if not found.
check_docker_prerequisites() {
    printMsg "${T_INFO_ICON} Checking for Docker..." >&2
    if ! command -v docker &>/dev/null; then
        printErrMsg "Docker is not installed. Please install Docker to continue." >&2
        exit 1
    fi
    printOkMsg "Docker is installed." >&2

    printMsg "${T_INFO_ICON} Checking for Docker Compose..." >&2
    # Check for either v2 (plugin) or v1 (standalone)
    if ! (command -v docker &>/dev/null && docker compose version &>/dev/null) && ! command -v docker-compose &>/dev/null; then
        printErrMsg "Docker Compose is not installed." >&2
        exit 1
    fi
    printOkMsg "Docker Compose is available." >&2
}

# Gets the correct Docker Compose command ('docker compose' or 'docker-compose').
# Assumes prerequisites have been checked by check_docker_prerequisites.
# Usage:
#   local compose_cmd
#   compose_cmd=$(get_docker_compose_cmd)
#   $compose_cmd up -d
get_docker_compose_cmd() {
    if command -v docker &>/dev/null && docker compose version &>/dev/null; then
        echo "docker compose"
    elif command -v docker-compose &>/dev/null; then
        echo "docker-compose"
    else
        # This case should not be reached if check_docker_prerequisites was called.
        printErrMsg "Could not determine Docker Compose command." >&2
        exit 1
    fi
}

# Ensures the script is running from its own directory.
# This is useful for scripts that need to find relative files (e.g., docker-compose.yml).
# It uses BASH_SOURCE[1] to get the path of the calling script.
ensure_script_dir() {
    # BASH_SOURCE[1] is the path to the calling script.
    # This is more robust than passing BASH_SOURCE[0] as an argument.
    local SCRIPT_DIR
    SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[1]}" )" &> /dev/null && pwd )
    if [[ "$PWD" != "$SCRIPT_DIR" ]]; then
        printMsg "${T_INFO_ICON} Changing to script directory: ${C_L_BLUE}${SCRIPT_DIR}${T_RESET}"
        cd "$SCRIPT_DIR"
    fi
}

# Checks if the script is run as root. If not, it prints a message
# and re-executes the script with sudo.
# Usage: ensure_root "Reason why root is needed." "$@"
ensure_root() {
    local reason_msg="$1"
    shift # The rest of "$@" are the original script arguments.
    if [[ $EUID -ne 0 ]]; then
        printMsg "${T_INFO_ICON} ${reason_msg}"
        printMsg "    ${C_L_BLUE}Attempting to re-run with sudo...${T_RESET}"
        exec sudo bash "${BASH_SOURCE[1]}" "$@"
    fi
}

# Helper to show systemd logs and exit on failure.
show_logs_and_exit() {
    local message="$1"
    printErrMsg "$message"
    # Check if journalctl is available before trying to use it
    if command -v journalctl &> /dev/null; then
        printMsg "    ${T_INFO_ICON} Preview of system log:"
        # Indent the journalctl output for readability
        journalctl -u ollama.service -n 10 --no-pager | sed 's/^/    /'
    else
        printMsg "    ${T_WARN_ICON} 'journalctl' not found. Cannot display logs."
    fi
    exit 1
}

# Polls a given URL until it gets a successful HTTP response or times out.
# Usage: poll_service <url> <service_name> [timeout_seconds]
poll_service() {
    local url="$1"
    local service_name="$2"
    local timeout=${3:-15} # Default timeout 15 seconds

    printMsgNoNewline "    ${C_BLUE}Waiting for ${service_name} to respond at ${url}... ${T_RESET}"
    for ((i=0; i<timeout; i++)); do
        if curl --silent --fail --head "$url" &>/dev/null; then
            echo # Newline for the dots
            printMsg "    ${T_OK_ICON} ${service_name} is responsive."
            return 0
        fi
        sleep 1
        printMsgNoNewline "${C_L_BLUE}.${T_RESET}"
    done

    echo # Newline after the dots
    # The calling script should handle the failure message
    return 1
}

# --- Ollama Service Helpers ---

# Cached check to see if this is a systemd-based system.
# The result is stored in a global variable to avoid repeated checks.
# Returns 0 if systemd, 1 otherwise.
_is_systemd_system() {
    # If the check has been run, return the cached result.
    if [[ -n "$_IS_SYSTEMD" ]]; then
        return "$_IS_SYSTEMD"
    fi

    if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null; then
        _IS_SYSTEMD=0 # true
    else
        _IS_SYSTEMD=1 # false
    fi
    return "$_IS_SYSTEMD"
}

# Checks if the ollama.service is known to systemd.
# Assumes _is_systemd_system() has been checked.
# Returns 0 if found, 1 otherwise.
_is_ollama_service_known() {
    if systemctl list-unit-files --type=service | grep -q '^ollama\.service'; then
        return 0 # Found
    else
        return 1 # Not found
    fi
}

# Public-facing check if the Ollama systemd service exists.
# Returns 0 if it exists, 1 otherwise.
check_ollama_systemd_service_exists() {
    if ! _is_systemd_system || ! _is_ollama_service_known; then
        return 1
    fi
    return 0
}

# Waits for the Ollama systemd service to become known, with retries.
# Useful when running a script immediately after installation.
# Exits if the service is not found after a few seconds.
wait_for_ollama_service() {
    if ! _is_systemd_system; then
        printMsg "${T_INFO_ICON} Not a systemd system. Skipping service discovery."
        return
    fi

    printMsgNoNewline "${T_INFO_ICON} Looking for Ollama service"
    local ollama_found=false
    for i in {1..5}; do
        printMsgNoNewline "${C_L_BLUE}.${T_RESET}"
        if _is_ollama_service_known; then
            ollama_found=true
            break
        fi
        sleep 1
    done

    echo # Newline after the dots

    if ! $ollama_found; then
        printErrMsg "Ollama service not found after 5 attempts. Please install it first with ./installollama.sh"
        exit 1
    fi

    printOkMsg "Ollama service found"
}

# Verifies that the Ollama service is running and responsive.
verify_ollama_service() {
    printMsg "${T_INFO_ICON} Verifying Ollama service status..."

    if ! _is_systemd_system; then
        printMsg "    ${T_INFO_ICON} Not a systemd system. Skipping systemd service check."
    elif ! _is_ollama_service_known; then
        printMsg "    ${T_INFO_ICON} Ollama service not found. Skipping systemd service check."
    else
        # This is a systemd system and the service exists.
        if ! systemctl is-active --quiet ollama.service; then
            show_logs_and_exit "Ollama service failed to activate according to systemd."
        fi
        printMsg "    ${T_OK_ICON} Systemd reports service is active."
    fi

    # Regardless of systemd status, we check if the API is responsive.
    # This covers non-systemd installs or cases where it's run manually.
    local ollama_port=${OLLAMA_PORT:-11434}
    local ollama_url="http://localhost:${ollama_port}"

    if ! poll_service "$ollama_url" "Ollama API"; then
        # Only show systemd logs if we know it's a systemd failure.
        if _is_systemd_system && _is_ollama_service_known; then
            show_logs_and_exit "Ollama service is active, but the API is not responding at ${ollama_url}."
        else
            printErrMsg "Ollama API is not responding at ${ollama_url}."
            printMsg "    ${T_INFO_ICON} Please ensure Ollama is installed and running."
            exit 1
        fi
    fi
}

# --- Ollama Network Configuration Helpers ---

# Checks if Ollama is configured to be exposed to the network.
# Returns 0 if exposed, 1 if not.
check_network_exposure() {
    local current_host_config
    # Query systemd for the effective Environment setting for the service.
    # Redirect stderr to hide "property not set" messages if the override doesn't exist.
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
    if check_network_exposure; then
        printMsg "${T_INFO_ICON} Already exposed to the network. No changes made."
        return 0
    fi

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
    if ! sudo systemctl daemon-reload || ! sudo systemctl restart ollama; then
        show_logs_and_exit "Failed to restart Ollama service after applying network override."
    fi

    printOkMsg "Ollama has been configured to be exposed to the network and was restarted."
    return 0
}

# Removes the systemd override to restrict Ollama to localhost.
# This function requires sudo to run its commands.
restrict_to_localhost() {
    if ! check_network_exposure; then
        printMsg "${T_INFO_ICON} Already restricted to localhost. No changes made."
        return 0
    fi

    local override_file="/etc/systemd/system/ollama.service.d/10-expose-network.conf"
    printMsg "${T_INFO_ICON} Removing systemd override to restrict Ollama to localhost..."

    if [[ ! -f "$override_file" ]]; then
        printMsg "${T_INFO_ICON} Override file not found. No changes needed."
    else
        sudo rm -f "$override_file"
    fi

    printMsg "${T_INFO_ICON} Reloading systemd daemon and restarting Ollama service..."
    sudo systemctl daemon-reload
    sudo systemctl restart ollama
    printOkMsg "Ollama has been restricted to localhost and was restarted."
}
