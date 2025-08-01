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

function printInfoMsg() {
  printMsg "${T_INFO_ICON} ${1}${T_RESET}"
}

function printWarnMsg() {
  printMsg "${T_WARN_ICON} ${1}${T_RESET}"
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

# Clears the current line and returns the cursor to the start.
clear_current_line() {
    # \e[2K: clear entire line
    # \r: move cursor to beginning of the line
    echo -ne "\e[2K\r"
}

# Clears a specified number of lines above the current cursor position.
# Usage: clear_lines_up [number_of_lines]
clear_lines_up() {
    local lines=${1:-1} # Default to 1 line if no argument is provided
    for ((i=0; i<lines; i++)); do
        # \e[1A: move cursor up one line
        # \e[2K: clear entire line
        echo -ne "\e[1A\e[2K"
    done
    echo -ne "\r" # Move cursor to the beginning of the line
}

# --- Error Handling & Traps ---

# Centralized error handler function.
# This function is triggered by the 'trap' command on any error when 'set -e' is active.
script_error_handler() {
    local exit_code=$? # Capture the exit code immediately!
    trap - ERR # Disable the trap to prevent recursion if the handler itself fails.
    local line_number=$1
    local command="$2"
    # BASH_SOURCE[1] is the path to the script that sourced this file.
    local script_path="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
    local script_name
    script_name=$(basename "$script_path")

    echo # Add a newline for better formatting before the error.
    printErrMsg "A fatal error occurred."
    printMsg "    Script:     ${C_L_BLUE}${script_name}${T_RESET}"
    printMsg "    Line:       ${C_L_YELLOW}${line_number}${T_RESET}"
    printMsg "    Command:    ${C_L_CYAN}${command}${T_RESET}"
    printMsg "    Exit Code:  ${C_RED}${exit_code}${T_RESET}"
    echo
}

# Function to handle Ctrl+C (SIGINT)
script_interrupt_handler() {
    trap - INT # Disable the trap to prevent recursion.
    echo # Add a newline for better formatting.
    printMsg "${T_WARN_ICON} ${C_L_YELLOW}Operation cancelled by user.${T_RESET}"
    # Exit with a status code indicating cancellation (130 is common for Ctrl+C).
    exit 130
}

# Set the trap. This will call our handler function whenever a command fails.
# The arguments passed to the handler are the line number and the command that failed.
trap 'script_error_handler $LINENO "$BASH_COMMAND"' ERR
trap 'script_interrupt_handler' INT

# A variable to cache the result of the check.
# Unset by default. Can be "true" or "false" after the first run.
_OLLAMA_IS_INSTALLED=""

# Checks if the Ollama CLI is installed and exits if it's not.
check_ollama_installed() {
    # 1. Perform the check only if the status is not already cached.
    if [[ -z "${_OLLAMA_IS_INSTALLED:-}" ]]; then
        if command -v ollama &> /dev/null; then
            _OLLAMA_IS_INSTALLED="true"
        else
            _OLLAMA_IS_INSTALLED="false"
        fi
    fi

    # 2. Print messages and act based on the cached status.
    printMsgNoNewline "${T_INFO_ICON} Checking for Ollama installation... " >&2
    if [[ "${_OLLAMA_IS_INSTALLED}" == "true" ]]; then
        printOkMsg "Ollama is installed." >&2
        return 0
    else
        echo >&2 # Newline before error message
        printErrMsg "Ollama is not installed." >&2
        printMsg "    ${T_INFO_ICON} Please run ${C_L_BLUE}./install-ollama.sh${T_RESET} to install it." >&2
        exit 1
    fi
}

# Checks for Docker and Docker Compose. Exits if not found.
check_docker_prerequisites() {
    printMsgNoNewline "${T_INFO_ICON} Checking for Docker... " >&2
    if ! command -v docker &>/dev/null; then
        echo >&2 # Newline before error message
        printErrMsg "Docker is not installed. Please install Docker to continue." >&2
        exit 1
    fi
    printOkMsg "Docker is installed." >&2

    printMsgNoNewline "${T_INFO_ICON} Checking for Docker Compose... " >&2
    # Check for either v2 (plugin) or v1 (standalone)
    if ! (command -v docker &>/dev/null && docker compose version &>/dev/null) && ! command -v docker-compose &>/dev/null; then
        echo >&2 # Newline before error message
        printErrMsg "Docker Compose is not installed." >&2
        exit 1
    fi
    printOkMsg "Docker Compose is available." >&2
}

# Checks if jq is installed. Exits if not found.
check_jq_installed() {
    printMsgNoNewline "${T_INFO_ICON} Checking for jq... " >&2
    if ! command -v jq &>/dev/null; then
        echo >&2 # Newline before error message
        printErrMsg "jq is not installed. Please install it to parse model data." >&2
        printMsg "    ${T_INFO_ICON} On Debian/Ubuntu: ${C_L_BLUE}sudo apt-get install jq${T_RESET}" >&2
        exit 1
    fi
    
    # Overwrite the checking message, this reduces visual clutter 
    clear_current_line
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

# Sources the project's .env file if it exists.
# This is intended for scripts in the project root that need to access
# configuration defined for OpenWebUI (e.g., custom ports).
# It looks for an .env file in the 'openwebui' subdirectory.
load_project_env() {
    # BASH_SOURCE[1] is the path to the script that called this function.
    local SCRIPT_DIR
    SCRIPT_DIR=$(dirname -- "${BASH_SOURCE[1]}")
    local ENV_FILE="${SCRIPT_DIR}/openwebui/.env"

    if [[ -f "$ENV_FILE" ]]; then
        printMsg "${T_INFO_ICON} Sourcing configuration from ${C_L_BLUE}openwebui/.env${T_RESET}"
        set -a
        # shellcheck source=/dev/null
        source "$ENV_FILE"
        set +a
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
        #printMsg "    ${C_L_BLUE}Attempting to re-run with sudo...${T_RESET}"
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
    # The number of tries is based on the timeout in seconds.
    # We poll once per second.
    local tries=${3:-10} # Default to 10 tries (10 seconds)

    local desc="Waiting for ${service_name} to respond at ${url}"

    # We need to run the loop in a subshell so that `run_with_spinner` can treat it
    # as a single command. The subshell will exit with 0 on success and 1 on failure.
    # We pass 'url' and 'tries' as arguments to the subshell to avoid quoting issues.
    if run_with_spinner "${desc}" bash -c '
        url="$1"
        tries="$2"
        for ((j=0; j<tries; j++)); do
            # Use a short connect timeout for each attempt
            if curl --silent --fail --head --connect-timeout 2 "$url" &>/dev/null; then
                exit 0 # Success
            fi
            sleep 1
        done
        exit 1 # Failure
    ' -- "$url" "$tries"; then
        clear_lines_up 1
        return 0
    else
        printErrMsg "${service_name} is not responding at ${url}"
        return 1
    fi
}

# Checks if an endpoint is responsive without writing to terminal
# Returns 0 on success, 1 on failure.
# Usage: check_endpoint_status <url> [timeout_seconds]
check_endpoint_status() {
    local url="$1"
    local timeout=${2:-5} # A shorter default timeout is fine for a status check.
    # Use --connect-timeout to fail fast if the port isn't open.
    # Use --max-time for the total operation.
    if curl --silent --fail --head --connect-timeout 2 --max-time "$timeout" "$url" &>/dev/null; then
        return 0 # Success
    else
        return 1 # Failure
    fi
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

    # Check for the presence of systemctl and that systemd is the init process.
    # `is-system-running` can fail on a "degraded" system, which is still usable.
    # Checking for the /run/systemd/system directory is a more reliable way to detect systemd.
    if command -v systemctl &>/dev/null && [ -d /run/systemd/system ]; then
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
    # 'systemctl cat' is a direct way to check if a service exists
    # It will return a non-zero exit code if the service doesn't exist.
    # We redirect stdout and stderr to /dev/null to suppress all output.
    if systemctl cat ollama.service &>/dev/null; then
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
        printErrMsg "Ollama service not found after 5 attempts. Please install it first with ./install-ollama.sh"
        exit 1
    fi

    clear_lines_up 1
    #printOkMsg "Ollama service found"

    # After finding the service, ensure it's running.
    if ! systemctl is-active --quiet ollama.service; then
        local current_state
        # Get the state (e.g., "inactive", "failed"). This command has a non-zero
        # exit code when not active, so `|| true` is needed to prevent `set -e` from exiting.
        current_state=$(systemctl is-active ollama.service || true)
        printMsg "    ${T_INFO_ICON} Service is not active (currently ${C_L_YELLOW}${current_state}${T_RESET}). Attempting to start it..."
        # This requires sudo. The calling script should either be run with sudo
        # or the user will be prompted for a password.
        if ! sudo systemctl start ollama.service; then
            show_logs_and_exit "Failed to start Ollama service."
        fi
        printMsg "    ${T_OK_ICON} Service started successfully."
    fi
}

wait_for_ollama_service2() {
    if ! _is_systemd_system; then
        printMsg "${T_INFO_ICON} Not a systemd system. Skipping service discovery."
        return
    fi

    local desc="${T_INFO_ICON} Looking for Ollama service"

    if run_with_spinner "${desc}" bash -c '
        local ollama_found=false
        for i in {1..5}; do
            if _is_ollama_service_known; then
                ollama_found=true
                exit 0 # Success
            fi
            sleep 1
        done

        if ! $ollama_found; then
            exit 1 # Failure
        fi
    '; then
        clear_lines_up 1
        # printOkMsg "Ollama service found"
    else
        printErrMsg "Ollama service not found. Please install it with ./install-ollama.sh"
        exit 1
    fi

    # After finding the service, ensure it's running.
    if ! systemctl is-active --quiet ollama.service; then
        local current_state
        # Get the state (e.g., "inactive", "failed"). This command has a non-zero
        # exit code when not active, so `|| true` is needed to prevent `set -e` from exiting.
        current_state=$(systemctl is-active ollama.service || true)
        printMsg "    ${T_INFO_ICON} Service is not active (currently ${C_L_YELLOW}${current_state}${T_RESET}). Attempting to start it..."
        # This requires sudo. The calling script should either be run with sudo
        # or the user will be prompted for a password.
        if ! sudo systemctl start ollama.service; then
            show_logs_and_exit "Failed to start Ollama service."
        fi
        printMsg "    ${T_OK_ICON} Service started successfully."
    fi
}

# A function to display a spinner while a command runs in the background.
# Usage: run_with_spinner "Description of task..." "command_to_run" "arg1" "arg2" ...
# The command's stdout and stderr will be captured.
# The function returns the exit code of the command.
# The captured stdout is stored in the global variable SPINNER_OUTPUT.
export SPINNER_OUTPUT=""
run_with_spinner() {
    local desc="$1"
    shift
    local cmd=("$@")

    local spinner_chars="⣾⣷⣯⣟⡿⢿⣻⣽"
    local i=0
    local temp_output_file
    temp_output_file=$(mktemp)

    # Run the command in the background, redirecting its output to the temp file.
    "${cmd[@]}" &> "$temp_output_file" &
    local pid=$!

    # Hide cursor
    tput civis
    # Trap to ensure cursor is shown again on exit/interrupt
    trap 'tput cnorm; rm -f "$temp_output_file"; exit 130' INT TERM

    # Initial spinner print
    printMsgNoNewline "    ${C_L_BLUE}${spinner_chars:0:1}${T_RESET} ${desc}"

    while ps -p $pid > /dev/null; do
        # Move cursor to the beginning of the line, print spinner, and stay on the same line
        echo -ne "\r    ${C_L_BLUE}${spinner_chars:$i:1}${T_RESET} ${desc}"
        i=$(((i + 1) % ${#spinner_chars}))
        sleep 0.1
    done

    # Wait for the command to finish and get its exit code
    wait $pid
    local exit_code=$?

    # Read the output from the temp file into the global variable
    SPINNER_OUTPUT=$(<"$temp_output_file")
    rm "$temp_output_file"

    # Show cursor again and clear the trap
    tput cnorm
    trap - INT TERM

    # Overwrite the spinner line with the final status message
    clear_current_line
    if [[ $exit_code -eq 0 ]]; then
        printOkMsg "${desc}"
    else
        printErrMsg "${desc}"
    fi

    return $exit_code
}

# Verifies that the Ollama API is responsive, with a spinner. Exits on failure.
# This is useful as a precondition check in scripts that need to talk to the API.
verify_ollama_api_responsive() {
    local ollama_port=${OLLAMA_PORT:-11434}
    local ollama_url="http://localhost:${ollama_port}"

    # poll_service shows its own spinner and success message.
    # It returns 1 on timeout without printing an error, so we handle that here.
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
    verify_ollama_api_responsive
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
# Returns:
#   0 - on successful change.
#   1 - on error creating override file.
#   2 - if no change was needed (already exposed).
expose_to_network() {
    if check_network_exposure; then
        printMsg "${T_INFO_ICON} No change needed."
        printMsg "${T_OK_ICON} Ollama is already ${C_L_YELLOW}EXPOSED to the network${T_RESET} (listening on 0.0.0.0)."
        return 2 # 2 means no change was needed
    fi

    local override_dir="/etc/systemd/system/ollama.service.d"
    local override_file="${override_dir}/10-expose-network.conf"

    printMsg "${T_INFO_ICON} Creating systemd override to expose Ollama to network..."

    if ! sudo mkdir -p "$override_dir"; then
        printErrMsg "Failed to create override directory: $override_dir"
        return 1
    fi

    # Use a heredoc to safely write the multi-line configuration file
    # The `<<-` operator strips leading tabs, allowing the heredoc to be indented.
    if ! sudo tee "$override_file" >/dev/null <<-EOF; then
		[Service]
		Environment="OLLAMA_HOST=0.0.0.0"
	EOF
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
# Returns:
#   0 - on successful change.
#   2 - if no change was needed (already restricted).
restrict_to_localhost() {
    if ! check_network_exposure; then
        printMsg "\n ${T_INFO_ICON} No change needed."
        printMsg " ${T_INFO_ICON} Ollama is already ${C_L_BLUE}RESTRICTED to localhost${T_RESET} (listening on 127.0.0.1)."
        return 2 # 2 means no change was needed
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
    return 0
}
