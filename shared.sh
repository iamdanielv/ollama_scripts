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

# Verifies that the Ollama service is running and responsive.
verify_ollama_service() {
    printMsg "${T_INFO_ICON} Verifying Ollama service status..."
    if ! command -v systemctl &>/dev/null || ! systemctl list-units --type=service | grep -q 'ollama.service'; then
        printMsg "    ${T_INFO_ICON} Not a systemd system or Ollama service not managed by systemd. Skipping service check."
        return 0
    fi

    # 1. Check if the service is active with systemd
    if ! systemctl is-active --quiet ollama.service; then
        show_logs_and_exit "Ollama service failed to activate according to systemd."
    fi
    printMsg "    ${T_OK_ICON} Systemd reports service is active."

    local ollama_port=${OLLAMA_PORT:-11434}
    local ollama_url="http://localhost:${ollama_port}"

    if ! poll_service "$ollama_url" "Ollama API"; then
        show_logs_and_exit "Ollama service is active, but the API is not responding at ${ollama_url}."
    fi
}
