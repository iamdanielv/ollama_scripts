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

# Prints a section header for the report.
_print_diag_header() {
    printMsg "\n${C_L_WHITE}===== ${1} =====${T_RESET}"
}

# Runs a command and prints its output, indented.
# If the command fails, it prints an error message.
# Usage: _run_and_print "Description" [sudo] "command" "arg1" "arg2" ...
_run_and_print() {
    local desc="$1"
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

    # Execute command, capturing output and exit code
    output=$("${cmd[@]}" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        if [[ -n "$output" ]]; then
            echo
            while IFS= read -r line; do
                printf '    %s\n' "$line"
            done <<< "$output"
        else
            echo -e "\n    ${C_L_YELLOW}(No output)${T_RESET}"
        fi
    else
        printMsg "${C_RED}Failed (code: $exit_code)${T_RESET}"
        if [[ -n "$output" ]]; then
            while IFS= read -r line; do
                printf '    %s\n' "$line"
            done <<< "$output"
        fi
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

    _run_and_print "CPU Info" "lscpu"
    _run_and_print "Memory Usage" "free" "-h"
    _run_and_print "Disk Usage" "df" "-h"

    # --- Dependency Versions ---
    _print_diag_header "Dependency Versions"
    _run_and_print "Bash Version" "bash" "--version"
    _run_and_print "Curl Version" "curl" "--version"
    _run_and_print "Docker Version" "docker" "--version"
    local compose_cmd
    # shellcheck disable=SC2207
    if compose_cmd=$(get_docker_compose_cmd 2>/dev/null); then
        local compose_cmd_parts=($compose_cmd)
        _run_and_print "Docker Compose Version" "${compose_cmd_parts[@]}" "version"
    else
        printMsg "  ${C_L_CYAN}Docker Compose Version:${T_RESET} ${C_L_YELLOW}Not found${T_RESET}"
    fi
    _run_and_print "jq Version" "jq" "--version"

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
        
        # Check service status
        if ! _is_systemd_system; then
            printMsg "  ${C_L_CYAN}Service Status:${T_RESET} ${C_L_YELLOW}Not a systemd system.${T_RESET}"
        elif ! _is_ollama_service_known; then
            printMsg "  ${C_L_CYAN}Service Status:${T_RESET} ${C_L_YELLOW}Ollama service not found.${T_RESET}"
        else
            _run_and_print "Service Status" "systemctl" "status" "ollama.service" "--no-pager"

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

            if [[ -n "$compose_cmd" ]]; then # compose_cmd is defined in "Dependency Versions"
                printMsgNoNewline "\n  ${C_L_CYAN}Container Status:${T_RESET}"
                echo
                run_webui_compose ps | sed 's/^/    /'

                printMsg "\n  ${C_L_CYAN}OpenWebUI Logs (last 20 lines):${T_RESET}"
                run_webui_compose logs --tail=20 | sed 's/^/    /'
            fi
        fi
    fi

    # --- Network Diagnostics ---
    _print_diag_header "Network Diagnostics"

    # Special handling for `ss` to format output for readability.
    printMsg "\n  ${C_L_CYAN}Listening Ports:${T_RESET}"
    if ! _check_command_exists "ss"; then
        printMsg "    ${C_L_YELLOW}ss command not found.${T_RESET}"
    elif ! _check_command_exists "awk" || ! _check_command_exists "column"; then
        printMsg "    ${C_L_YELLOW}Cannot format (awk or column not found). Showing raw output.${T_RESET}"
        ss -tlpn 2>&1 | sed 's/^/    /'
    else
        # The script is already running as root via ensure_root.
        # We use awk to select specific columns and column to align them.
        # The header (NR==1) is handled separately because its word count differs from data rows.
        local ss_output
        ss_output=$(ss -tlpn 2>&1 | awk '
            NR==1 { print $1, "Local-Address:Port", "Peer-Address:Port", $NF; next }
            { print $1, $4, $5, $6 }
        ' | column -t)
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