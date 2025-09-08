#!/bin/bash

# Gathers comprehensive system and application information for diagnosing issues.

# --- Source shared libraries ---
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
# shellcheck source=./shared.sh
if ! source "${SCRIPT_DIR}/shared.sh"; then
    echo "Error: Could not source shared.sh." >&2
    exit 1
fi
# shellcheck source=./ollama-helpers.sh
if ! source "${SCRIPT_DIR}/ollama-helpers.sh"; then
    echo "Error: Could not source ollama-helpers.sh." >&2
    exit 1
fi

# --- Helper Functions ---

show_help() {
    printBanner "Ollama & OpenWebUI Diagnostic Tool"
    printMsg "Gathers system and application information to help with troubleshooting."
    printMsg "The output can be redirected to a file for easy sharing."

    printMsg "\n${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [-o <file>] [-h]"

    printMsg "\n${T_ULINE}Options:${T_RESET}"
    printMsg "  ${C_L_BLUE}-o, --output <file>${T_RESET}  Save the report to a file instead of printing to the screen."
    printMsg "  ${C_L_BLUE}-h, --help${T_RESET}           Show this help message."

    printMsg "\n${T_ULINE}Examples:${T_RESET}"
    printMsg "  ${C_GRAY}# Run and display the report in the terminal${T_RESET}"
    printMsg "  $(basename "$0")"
    printMsg "  ${C_GRAY}# Save the report to a file named 'diag-report.txt'${T_RESET}"
    printMsg "  $(basename "$0") -o diag-report.txt"
}

# (Private) Prints a block of text, indented.
# Usage: _print_indented_output "text"
_print_indented_output() {
    # Use sed to prepend spaces to each line
    echo "$1" | sed 's/^/    /'
}

# Prints a section header for the report.
_print_diag_header() {
    printMsg "\n${C_L_WHITE}===== ${1} =====${T_RESET}"
}

# Runs a command and prints its output, indented.
# If the command fails, it prints an error message.
# Usage: _run_and_print "Description" [sudo] "command" "arg1" "arg2" ...
# It uses the `timeout` command (if available) to prevent hanging.
_run_and_print() {
    local desc="$1"
    local timeout_duration="10s"
    shift
    # If the command was 'sudo', we just discard it since we are already root.
    if [[ "$1" == "sudo" ]]; then
        shift
    fi
    local cmd=("$@")
    local output
    
    printMsgNoNewline "\n  ${C_L_CYAN}${desc}:${T_RESET} "
    
    # Check if command exists first
    if ! _check_command_exists "${cmd[0]}"; then
        printMsg "${C_L_YELLOW}Not found${T_RESET}"
        return
    fi

    # Execute command with a timeout to prevent the script from hanging.
    # The timeout command is part of coreutils and should be available on most systems.
    local exec_cmd=()
    if _check_command_exists "timeout"; then
        exec_cmd=("timeout" "$timeout_duration")
    fi
    exec_cmd+=("${cmd[@]}")

    output=$("${exec_cmd[@]}" 2>&1)
    local exit_code=$?

    # The `timeout` command returns exit code 124 when the command times out.
    if [[ $exit_code -eq 124 ]]; then
        printMsg "${C_L_YELLOW}Timed out after ${timeout_duration}${T_RESET}"
    elif [[ $exit_code -eq 0 ]]; then
        if [[ -n "$output" ]]; then
            echo
            _print_indented_output "$output"
        else
            # Use echo -e to handle the newline and color codes correctly.
            echo -e "\n    ${C_L_YELLOW}(No output)${T_RESET}"
        fi
        return # Success case, so we return early.
    else
        printMsg "${C_RED}Failed (code: $exit_code)${T_RESET}"
    fi

    # This block now handles printing output for both timeout and failure cases.
    if [[ -n "$output" ]]; then
        _print_indented_output "$output"
    fi
}

# (Private) Checks versions of key command-line dependencies.
_check_dependency_versions() {
    _print_diag_header "Dependency Versions"
 
    # Use a 'here document' (heredoc) to feed the list of dependencies
    # directly into the while loop. This is a clean way to handle multi-line input.
    # The `<<-` operator strips leading tab characters, allowing the heredoc to be indented.
    # The format is "Description;command and args".
    while IFS=';' read -r desc cmd_str; do
        # Convert the command string into an array for safe execution.
        # This is safe for these specific commands as they don't have arguments with spaces.
        local -a cmd_parts=($cmd_str)
        _run_and_print "$desc" "${cmd_parts[@]}"
    done <<-EOF
		Bash Version;bash --version
		Curl Version;curl --version
		Docker Version;docker --version
		Docker Info;docker info
		jq Version;jq --version
	EOF

    # Docker Compose is handled separately due to its dynamic command name.
    local compose_cmd
    if compose_cmd=$(get_docker_compose_cmd 2>/dev/null); then
        _run_and_print "Docker Compose Version" $compose_cmd version
    else
        printMsg "\n  ${C_L_CYAN}Docker Compose Version:${T_RESET} ${C_L_YELLOW}Not found${T_RESET}"
    fi
}

# --- Main Logic ---
run_diagnostics() {
    printBanner "Ollama & OpenWebUI Diagnostic Report"
    printInfoMsg "Generated on: $(date)"

    # --- System Information ---
    _print_diag_header "System Information"
    _run_and_print "OS Version" "cat" "/etc/os-release"
    _run_and_print "Kernel Version" "uname" "-a"

    # Check user groups, which is important for Docker permissions.
    # We check for the original user who ran sudo, not root.
    local original_user=${SUDO_USER:-$USER}
    _run_and_print "User Groups for '${original_user}'" "id" "-nG" "$original_user"
    # Explicitly check for 'docker' group membership.
    printMsgNoNewline "\n  ${C_L_CYAN}User in 'docker' group?:${T_RESET} "
    if id -nG "$original_user" 2>/dev/null | grep -qw "docker"; then
        printMsg "${C_GREEN}Yes${T_RESET}"
    else
        printMsg "${C_L_YELLOW}No${T_RESET} ${C_GRAY}(May need to run Docker commands with sudo)${T_RESET}"
    fi

    _run_and_print "CPU Info" "lscpu"
    _run_and_print "Memory Usage" "free" "-h"
    _run_and_print "Disk Usage" "df" "-h"

    # --- Security Modules ---
    _print_diag_header "Security Modules"
    _run_and_print "SELinux Status" "sestatus"
    _run_and_print "AppArmor Status" "sudo" "aa-status"

    # --- Dependency Versions ---
    _check_dependency_versions

    # --- Environment Variables ---
    _print_diag_header "Relevant Environment Variables (Current Shell)"
    local relevant_vars=("OLLAMA_HOST" "OLLAMA_PORT" "OLLAMA_MODELS" "OPEN_WEBUI_PORT" "DOCKER_HOST")
    local output=""
    for var in "${relevant_vars[@]}"; do
        if [[ -n "${!var}" ]]; then # Using indirect expansion to get var value
            output+="\n  ${C_L_CYAN}$(printf '%-20s' "$var"):${T_RESET} ${!var}"
        fi
    done

    if [[ -z "$output" ]]; then
        printMsg "\n    ${C_L_GRAY}(No relevant environment variables set in this shell)${T_RESET}"
    else
        printMsg "$output"
    fi

    # --- GPU Information ---
    _print_diag_header "GPU Information"
    if ! _check_command_exists "nvidia-smi"; then
        printMsg "  ${C_L_YELLOW}nvidia-smi not found. Skipping GPU diagnostics.${T_RESET}"
    else
        printMsg "  ${C_L_CYAN}GPU Summary:${T_RESET}"
        print_gpu_status "    " # Call helper with indentation
        _run_and_print "Full NVIDIA SMI Output" "nvidia-smi"
    fi

    # --- Ollama Diagnostics ---
    _print_diag_header "Ollama Diagnostics"
    if ! _check_command_exists "ollama"; then
        printMsg "  ${C_L_YELLOW}Ollama command not found. Skipping Ollama diagnostics.${T_RESET}"
    else
        _run_and_print "Ollama Version" "ollama" "--version"

        # API Responsiveness Check
        printMsgNoNewline "\n  ${C_L_CYAN}API Responsiveness:${T_RESET} "
        local ollama_port=${OLLAMA_PORT:-11434}
        local ollama_url="http://localhost:${ollama_port}"
        if check_endpoint_status "$ollama_url"; then
            local ollama_api_version
            # Use jq to be safe, but fallback to grep/sed if not available
            if _check_command_exists "jq"; then
                ollama_api_version=$(curl -s "${ollama_url}/api/version" | jq -r .version)
            else
                ollama_api_version=$(curl -s "${ollama_url}/api/version" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
            fi
            printMsg "${C_GREEN}Reachable${T_RESET} (API Version: ${C_L_BLUE}${ollama_api_version:-N/A}${T_RESET})"
        else
            printMsg "${C_RED}Not Reachable at ${ollama_url}${T_RESET}"
        fi
        
        # Check service status
        if ! _is_systemd_system; then
            printMsg "  ${C_L_CYAN}Service Status:${T_RESET} ${C_L_YELLOW}Not a systemd system.${T_RESET}"
        elif ! _is_ollama_service_known; then
            printMsg "  ${C_L_CYAN}Service Status:${T_RESET} ${C_L_YELLOW}Ollama service not found.${T_RESET}"
        else
            _run_and_print "Service Status" "systemctl" "status" "ollama.service" "--no-pager"

            # Show the effective environment variables the service is running with.
            _run_and_print "Effective Environment" "systemctl" "show" "--no-pager" "--property=Environment" "ollama.service"

            # The check_network_exposure is a shell function, not an external command.
            # Calling it directly is more robust than trying to export it to a subshell.
            printMsg "\n  ${C_L_CYAN}Network Exposure:${T_RESET} "
            if check_network_exposure; then
                printMsg "    ${C_L_YELLOW}Exposed (0.0.0.0)${T_RESET}"
            else
                printMsg "    ${C_L_BLUE}Localhost Only${T_RESET}"
            fi
        fi

        # Ollama Systemd Overrides
        local override_dir="/etc/systemd/system/ollama.service.d"
        printMsg "\n  ${C_L_CYAN}Systemd Overrides:${T_RESET}"
        if [ -d "$override_dir" ] && [ -n "$(ls -A "$override_dir" 2>/dev/null)" ]; then
            for conf_file in "$override_dir"/*.conf; do
                _run_and_print "  - $(basename "$conf_file")" "cat" "$conf_file"
            done
        else
            printMsg "    ${C_L_GRAY}No override files found.${T_RESET}"
        fi

        # Ollama Models Directory
        printMsg "\n  ${C_L_CYAN}Ollama Models Directory:${T_RESET}"
        if ! _is_systemd_system || ! _is_ollama_service_known; then
            printMsg "    ${C_GRAY}Cannot determine (not a systemd system or service not found).${T_RESET}"
        else
            local ollama_env
            ollama_env=$(systemctl show --no-pager --property=Environment ollama.service 2>/dev/null)
            local models_dir
            models_dir=$(echo "$ollama_env" | grep -o 'OLLAMA_MODELS=[^ ]*' | cut -d'=' -f2 | tr -d '"')

            local source_msg=""
            if [[ -z "$models_dir" ]]; then
                # Determine default path based on the service user
                local ollama_user
                ollama_user=$(systemctl show --no-pager --property=User --value ollama.service 2>/dev/null)
                if [[ -z "$ollama_user" || "$ollama_user" == "root" ]]; then
                    models_dir="/root/.ollama/models"
                else
                    # Default user is 'ollama', home is '/usr/share/ollama'
                    models_dir="/usr/share/ollama/.ollama/models"
                fi
                source_msg="${C_GRAY}(default path for user '${ollama_user:-ollama}')${T_RESET}"
            else
                source_msg="${C_GRAY}(from OLLAMA_MODELS env var)${T_RESET}"
            fi

            printMsg "    Path: ${C_L_BLUE}${models_dir}${T_RESET} ${source_msg}"
            if [[ -d "$models_dir" ]]; then
                _run_and_print "    Permissions" "ls" "-ld" "$models_dir"
                _run_and_print "    Size" "du" "-sh" "$models_dir"
            else
                printMsg "    ${C_L_YELLOW}Directory not found.${T_RESET}"
            fi
        fi

        # Ollama Logs
        printMsg "\n  ${C_L_CYAN}Ollama Logs (last 20 lines):${T_RESET}"
        if _is_systemd_system && _is_ollama_service_known; then
            journalctl -u ollama.service -n 20 --no-pager | sed 's/^/    /'
        else
            printMsg "    ${C_GRAY}Cannot get logs (not a systemd system or service not found).${T_RESET}"
        fi
    fi

    # --- OpenWebUI Diagnostics ---
    _print_diag_header "OpenWebUI Diagnostics"
    if ! _find_project_root; then
        printMsg "  ${C_L_YELLOW}Could not find project root. Skipping OpenWebUI diagnostics.${T_RESET}"
    else
        local webui_dir="${_PROJECT_ROOT}/openwebui"
        if [[ ! -d "$webui_dir" ]]; then
            printMsg "  ${C_L_YELLOW}Directory 'openwebui' not found. Skipping OpenWebUI diagnostics.${T_RESET}"
        else
            _run_and_print "Docker Compose Config" "cat" "${webui_dir}/docker-compose.yaml"

            if [[ -f "${webui_dir}/.env" ]]; then
                _run_and_print "OpenWebUI .env" "cat" "${webui_dir}/.env"
            else
                printMsg "\n  ${C_L_CYAN}OpenWebUI .env:${T_RESET} ${C_GRAY}Not found.${T_RESET}"
            fi

            if [[ -f "${_PROJECT_ROOT}/.env" ]]; then
                _run_and_print "Project Root .env" "cat" "${_PROJECT_ROOT}/.env"
            else
                printMsg "\n  ${C_L_CYAN}Project Root .env:${T_RESET} ${C_GRAY}Not found.${T_RESET}"
            fi

            # Get the compose command. It's defined as a local var in _check_dependency_versions
            # so it's out of scope here. We need it to decide whether to run compose-related checks.
            local compose_cmd
            compose_cmd=$(get_docker_compose_cmd 2>/dev/null)
            if [[ -n "$compose_cmd" ]]; then
                printMsgNoNewline "\n  ${C_L_CYAN}Container Status:${T_RESET}"
                local ps_output
                ps_output=$(run_webui_compose ps 2>&1)
                echo # Add a newline after the header
                _print_indented_output "$ps_output"

                if [[ -z "$ps_output" || $(echo "$ps_output" | wc -l) -le 1 ]]; then
                    printMsg "    ${C_L_YELLOW}No OpenWebUI containers found.${T_RESET}"
                fi

                printMsg "\n  ${C_L_CYAN}OpenWebUI Logs (last 20 lines):${T_RESET}"
                local container_logs
                container_logs=$(run_webui_compose logs --tail=20 2>&1)
                if [[ -z "$container_logs" ]]; then
                    printMsg "    ${C_L_YELLOW}No logs available${T_RESET}"
                else
                    echo "$container_logs" | sed 's/^/    /'
                fi

                # Active connectivity check from WebUI container to Ollama
                printMsg "\n  ${C_L_CYAN}Connectivity from WebUI to Ollama:${T_RESET}"
                if ! check_openwebui_container_running; then
                    printMsg "    ${C_L_YELLOW}Skipped (OpenWebUI container is not running).${T_RESET}"
                else
                    local ollama_port=${OLLAMA_PORT:-11434}
                    local ollama_check_url="http://host.docker.internal:${ollama_port}"
                    printMsgNoNewline "    - Checking connectivity to ${C_L_BLUE}${ollama_check_url}${T_RESET}... "

                    if run_webui_compose exec -T open-webui curl --silent --fail --head --connect-timeout 5 "${ollama_check_url}" >/dev/null 2>&1; then
                        printMsg "${C_GREEN}Success${T_RESET}"
                    else
                        printMsg "${C_RED}Failed${T_RESET}"
                        printMsg "      ${C_GRAY}This is a common issue. It can mean Ollama is not configured for network access"
                        printMsg "      ${C_GRAY}or a firewall is blocking the connection. Try running: ${C_L_BLUE}./config-ollama.sh --expose${T_RESET}"
                    fi
                fi
            fi
        fi
    fi

    # --- Network Diagnostics ---
    _print_diag_header "Network Diagnostics"

    # Focused check for key service ports
    printMsg "\n  ${C_L_CYAN}Key Service Ports:${T_RESET}"
    if ! _check_command_exists "ss"; then
        printMsg "    ${C_L_YELLOW}ss command not found, skipping port checks.${T_RESET}"
    else
        # Check for Ollama
        local ollama_listen_info
        ollama_listen_info=$(ss -tlpn 2>/dev/null | grep '("ollama"')
        if [[ -n "$ollama_listen_info" ]]; then
            # A process can listen on multiple sockets (e.g., IPv4 and IPv6).
            # We use xargs to join the multiple lines from awk into a single line.
            local listen_addrs
            listen_addrs=$(echo "$ollama_listen_info" | awk '{print $4}' | xargs)
            printMsg "    ${T_OK_ICON} Ollama is listening on: ${C_L_BLUE}${listen_addrs}${T_RESET}"
        else
            printMsg "    ${T_ERR_ICON} Ollama process not found listening on any port."
        fi

        # Check for OpenWebUI (via docker-proxy)
        local webui_port=${OPEN_WEBUI_PORT:-3000}
        local webui_listen_info
        webui_listen_info=$(ss -tlpn 2>/dev/null | grep -F ":${webui_port} ")
        if [[ -n "$webui_listen_info" ]]; then
            local listen_addrs
            listen_addrs=$(echo "$webui_listen_info" | awk '{print $4}' | xargs)
            printMsg "    ${T_OK_ICON} A service (likely OpenWebUI) is listening on port ${webui_port}: ${C_L_BLUE}${listen_addrs}${T_RESET}"
        else
            printMsg "    ${T_WARN_ICON} No process found listening on the expected OpenWebUI port (${webui_port})."
        fi
    fi

    # Special handling for `ss` to format output for readability.
    printMsg "\n  ${C_L_CYAN}All Listening Ports (via ss):${T_RESET}"
    if ! _check_command_exists "ss"; then
        printMsg "    ${C_L_YELLOW}ss command not found.${T_RESET}"
    elif ! _check_command_exists "awk" || ! _check_command_exists "column"; then
        printMsg "    ${C_L_YELLOW}Cannot format (awk or column not found). Showing raw output.${T_RESET}"
        ss -tlpn 2>&1 | sed 's/^/    /'
    else
        # The script is already running as root.
        # We use awk to parse the output, sort to order it, and `column` to format it.
        # The awk script extracts the process name from the verbose output, e.g.,
        # from 'users:(("ollama",pid=1234,fd=3))' it extracts 'ollama'.
        local ss_output
        ss_output=$(ss -tlpn 2>&1 | awk '
            # Print a clean header.
            NR==1 { print "Local Address\tPeer Address\tProcess"; next }
            # Process data rows. $4 is Local Address, $5 is Peer Address, $6 is Process info.
            {
                process = $6
                # Find the string inside the first pair of quotes.
                if (match(process, /"[^"]+"/)) {
                    process = substr(process, RSTART + 1, RLENGTH - 2)
                }
                # Print as TSV for the next stage in the pipeline.
                printf "%s\t%s\t%s\n", $4, $5, process
            }
        ' | (read -r header; echo "$header"; sort -t $'\t' -k3) | column -t -s $'\t')
        local exit_code=${PIPESTATUS[0]} # Get exit code of `ss`, not `column`

        if [[ $exit_code -ne 0 ]]; then
            printMsg "    ${C_RED}ss command failed (code: $exit_code). Showing raw output.${T_RESET}"
            ss -tlpn 2>&1 | sed 's/^/    /' # Print raw output on failure
        else
            echo "${ss_output}" | sed 's/^/    /'
        fi
    fi
    
    printMsg "\n  ${C_L_CYAN}Firewall Status:${T_RESET}"
    if _check_command_exists "ufw"; then
        ufw status verbose | sed 's/^/    /'
    elif _check_command_exists "firewall-cmd"; then
        firewall-cmd --state | sed 's/^/    /'
        firewall-cmd --list-all | sed 's/^/    /'
    else
        printMsg "    ${C_GRAY}No known firewall tool (ufw, firewall-cmd) found.${T_RESET}"
    fi

    printMsg "\n${C_GREEN}Diagnostic report complete.${T_RESET}"
}

main() {
    local output_file=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o|--output)
                output_file="$2"
                if [[ -z "$output_file" ]]; then
                    show_help
                    printErrMsg "The --output flag requires a filename."
                    exit 1
                fi
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                show_help
                printErrMsg "Invalid option: $1"
                exit 1
                ;;
        esac
    done

    # Since some diagnostic commands require root, we ensure it at the start.
    # This is simpler than checking for sudo access for individual commands.
    ensure_root "Root privileges are needed to gather full network and firewall status." "$@"

    # Load environment variables from .env file at project root, if it exists.
    # This makes custom ports (OLLAMA_PORT, OPEN_WEBUI_PORT) available.
    if _find_project_root && [[ -f "${_PROJECT_ROOT}/.env" ]]; then
        load_project_env "${_PROJECT_ROOT}/.env"
    fi

    # If an output file is specified, redirect all output of run_diagnostics to it.
    if [[ -n "$output_file" ]]; then
        # Run diagnostics, strip color codes, and save to file.
        # We disable the error trap for this, as a failing diagnostic command
        # would otherwise terminate the script.
        (trap - ERR; run_diagnostics) | sed 's/\x1b\[[0-9;]*m//g' > "$output_file"
        
        if [[ -f "$output_file" ]]; then
            printOkMsg "Diagnostic report saved to: ${C_L_BLUE}${output_file}${T_RESET}"
            exit 0
        else
            printErrMsg "Failed to create diagnostic report file."
            exit 1
        fi
    else
        # If no output file, run and print to terminal.
        # We've already ensured root, so we can just run the diagnostics.
        (trap - ERR; run_diagnostics)
    fi
}

main "$@"