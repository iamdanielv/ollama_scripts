#!/bin/bash

# Source the TUI library which contains all shared visual/interactive functions
# This ensures that colors, key codes, prompts, and spinners are consistent.
# shellcheck source=src/lib/tui.lib.sh
if ! source "$(dirname "${BASH_SOURCE[0]}")/tui.lib.sh"; then
    # Use raw echo for fatal errors in case TUI/shared functions aren't available.
    echo "FATAL: TUI library not found." >&2
    exit 1
fi

# --- Banner Control ---
# This logic helps determine if a script is being called by another script in this project.
# The first script to source this file will set the entry-level shell level ($SHLVL).
# Any script *executed* by that first script will run in a new shell, which will have a
# higher SHLVL. This allows us to print a simpler banner for nested script calls.
# Note: This banner logic is distinct from the TUI library's banner.
if [[ -z "${SCRIPT_EXEC_ENTRY_SHLVL:-}" ]]; then
    export SCRIPT_EXEC_ENTRY_SHLVL=$SHLVL
fi

function printTestSectionHeader() {
  printMsg "\n${T_ULINE}${C_L_WHITE}${1}${T_RESET}"
}

function printDatedMsgNoNewLine() {
  echo -n -e "$(getPrettyDate) ${1}"
}

function getFormattedDate() {
  date +"%Y-%m-%d %I:%M:%S"
}

function getPrettyDate() {
  echo "${C_BLUE}$(getFormattedDate)${T_RESET}"
}

# Formats Tab-Separated Value (TSV) data into a clean, aligned table.
# This function correctly handles cells that contain ANSI color codes.
# It reads from stdin and takes an optional indent prefix as an argument.
# Usage:
#   echo -e "HEADER1\tHEADER2\nValue1\tValue2" | format_tsv_as_table "  "
# To right-align column 2:
#   ... | format_tsv_as_table "  " "2"
format_tsv_as_table() {
    local indent="${1:-}" # Optional indent prefix
    local right_align_cols="${2:-}" # Optional string of column numbers to right-align, e.g., "2 3"
    local padding=4      # Spaces between columns

    # Use a two-pass awk script for perfect alignment.
    # 1. The first pass calculates the maximum *visible* width of each column.
    # 2. The second pass prints each cell, followed by the required padding.
    # This approach is necessary to correctly handle ANSI color codes, which have
    # a non-zero character length but zero visible width.
    awk -v indent="$indent" -v padding="$padding" -v right_align_str="$right_align_cols" '
        # Function to calculate the visible length of a string by removing ANSI codes.
        # temp_s is declared as a parameter to make it a local variable,
        # which is the portable way to do this in awk.
        function visible_length(s, temp_s) {
            temp_s = s # Copy the string to a local variable.
            gsub(/\x1b\[[0-9;?]*[a-zA-Z]/, "", temp_s)
            return length(temp_s)
        }

        BEGIN {
            FS="\t"
            # Parse the right_align_str into an associative array for quick lookups.
            split(right_align_str, col_map, " ")
            for (i in col_map) { right_align[col_map[i]] = 1 }
        }

        # First pass: Read all data and calculate max visible width for each column.
        {
            for(i=1; i<=NF; i++) {
                len = visible_length($i)
                if(len > max_width[i]) { max_width[i] = len }
            }
            data[NR] = $0 # Store the original line with colors.
        }

        # Second pass: Print the formatted table.
        END {
            for(row=1; row<=NR; row++) {
                printf "%s", indent
                num_fields = split(data[row], fields, FS) # Split the original line to preserve colors.
                # Skip processing for lines that are completely empty. This handles trailing newlines from echo.
                if (num_fields == 1 && fields[1] == "") { continue }
                for(col=1; col<=num_fields; col++) {
                    align_pad = max_width[col] - visible_length(fields[col])

                    if (right_align[col]) {
                        # Right-align: alignment padding, then content.
                        for (p=0; p<align_pad; p++) { printf " " }
                        printf "%s", fields[col]
                    } else {
                        # Left-align: content, then alignment padding.
                        printf "%s", fields[col]
                        for (p=0; p<align_pad; p++) { printf " " }
                    }

                    # Print inter-column padding, but not for the last column.
                    if (col < num_fields) {
                        for (p=0; p<padding; p++) { printf " " }
                    }
                }
                printf "\n"
            }
        }
    '
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

# Set the trap. This will call our handler function whenever a command fails.
# The arguments passed to the handler are the line number and the command that failed.
# shellcheck disable=SC2064
trap 'script_error_handler $LINENO "$BASH_COMMAND"' ERR

# --- Prerequisite & Sanity Checks ---

# Internal helper to check for a command's existence without output.
# Returns 0 if found, 1 otherwise.
_check_command_exists() {
    command -v "$1" &>/dev/null
}

# Checks for command-line tools
# Exits with an error if any of the specified commands are not found.
# Usage: prereq_checks "command1" "command2" "..."
prereq_checks() {
    local missing_commands=()
    printMsgNoNewline "${T_INFO_ICON} Running prereq checks"
    for cmd in "$@"; do
        printMsgNoNewline "${C_L_BLUE}.${T_RESET}"
        if ! _check_command_exists "$cmd"; then
            missing_commands+=("$cmd")
        fi
    done
    echo # Newline after the dots

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        clear_lines_up 1
        printErrMsg "Prerequisite checks failed. Missing commands:"
        for cmd in "${missing_commands[@]}"; do
            printMsg "    - ${C_L_YELLOW}${cmd}${T_RESET}"
        done
        printMsg "${T_INFO_ICON} Please install the missing commands and try again."
        exit 1
    fi
    clear_lines_up 1
}

# Checks if jq is installed. Exits if not found.
# Usage: check_jq_installed [--silent]
#   --silent: If provided, the success message will be cleared instead of printed.
check_jq_installed() {
    local silent=false
    if [[ "$1" == "--silent" ]]; then
        silent=true
    fi

    printMsgNoNewline "${T_INFO_ICON} Checking for jq... " >&2
    if ! _check_command_exists "jq"; then
        echo >&2 # Newline before error message
        printErrMsg "jq is not installed. Please install it to parse model data." >&2
        printMsg "    ${T_INFO_ICON} On Debian/Ubuntu: ${C_L_BLUE}sudo apt-get install jq${T_RESET}" >&2
        exit 1
    fi

    if $silent; then
        # Overwrite the checking message, this reduces visual clutter
        clear_current_line >&2
    else
        printOkMsg "jq is installed." >&2
    fi
}

# Gets the correct Docker Compose command ('docker compose' or 'docker-compose').
# Assumes prerequisites have been checked by check_docker_prerequisites.
# Usage:
#   local compose_cmd
#   compose_cmd=$(get_docker_compose_cmd)
#   $compose_cmd up -d
get_docker_compose_cmd() {
    if _check_command_exists "docker" && docker compose version &>/dev/null; then
        echo "docker compose"
    elif _check_command_exists "docker-compose"; then
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

    # If SCRIPT_DIR is empty, it means the cd in the subshell failed.
    if [[ -z "$SCRIPT_DIR" ]]; then
        printErrMsg "Could not access script directory from path: ${BASH_SOURCE[1]}"
        return 1
    fi

    if [[ "$PWD" != "$SCRIPT_DIR" ]]; then
        printMsg "${T_INFO_ICON} Changing to script directory: ${C_L_BLUE}${SCRIPT_DIR}${T_RESET}"
        cd "$SCRIPT_DIR" || return 1
    fi
}

# (Private) Finds the project root directory by searching upwards for a known file.
# The result is stored in the global variable _PROJECT_ROOT and exported.
# Usage: _find_project_root [--silent]
# Returns 0 on success, 1 on failure.
_find_project_root() {
    local silent=false
    if [[ "$1" == "--silent" ]]; then
        silent=true
    fi
    # If already found, return success
    if [[ -n "${_PROJECT_ROOT:-}" ]]; then
        return 0
    fi

    # Start searching from the directory of the top-level script that was executed.
    local start_dir
    start_dir=$(dirname "${BASH_SOURCE[-1]}")

    local current_dir
    current_dir=$(cd "$start_dir" && pwd)

    while [[ "$current_dir" != "/" && "$current_dir" != "" ]]; do
        # Using README.md and shared.lib.sh as anchor files to identify the project root.
        if [[ -f "$current_dir/README.md" && -f "$current_dir/src/lib/shared.lib.sh" ]] || [[ -f "$current_dir/GEMINI.md" ]]; then
            _PROJECT_ROOT="$current_dir"
            export _PROJECT_ROOT # Export so subshells can see it
            return 0
        fi
        current_dir=$(dirname "$current_dir")
    done

    return 1 # Failed to find root
}
#export -f _find_project_root

# A helper to run docker compose commands for OpenWebUI from any directory.
# It automatically locates the 'openwebui' directory within the project.
# Usage: run_webui_compose "ps" "--filter" "status=running"
run_webui_compose() {
    if ! _find_project_root; then
        printErrMsg "Could not determine project root directory. Cannot run docker compose."
        return 1
    fi

    local webui_dir="${_PROJECT_ROOT}/openwebui"
    local compose_cmd
    compose_cmd=$(get_docker_compose_cmd)
    local compose_cmd_parts=($compose_cmd)

    # Execute the command using --project-directory, which is safer than cd.
    "${compose_cmd_parts[@]}" --project-directory "$webui_dir" "$@"
}
#export -f run_webui_compose



# (Private) Validates the format of a .env file.
# It prints a detailed error and returns 1 on the first invalid line found.
# Returns 0 if the entire file is valid.
# Usage:
#   if ! _validate_env_file "/path/to/.env"; then
#       # Handle validation failure
#   fi
_validate_env_file() {
    local env_file_path="$1"
    local line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        local trimmed_line
        trimmed_line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

        if [[ -z "$trimmed_line" || "$trimmed_line" =~ ^# ]]; then
            continue
        fi

		local error_reason=""
		# Rule 1: Must contain an equals sign.
		if ! [[ "$trimmed_line" =~ = ]]; then
			error_reason="Missing '=' in '${trimmed_line}'"
		# Rule 2: Must not have spaces immediately surrounding the equals sign.
		elif [[ "$trimmed_line" =~ [[:space:]]=|=[[:space:]] ]]; then
			error_reason="Found spaces around '=' in '${trimmed_line}'"
		# Rule 3: The key must be a valid shell variable name.
		elif ! [[ "$trimmed_line" =~ ^[a-zA-Z_][a-zA-Z0-9_]*= ]]; then
			error_reason="Invalid variable name in '${trimmed_line}'"
		fi

		if [[ -n "$error_reason" ]]; then
            printErrMsg "Found an error in ${C_L_BLUE}${env_file_path}${T_RESET} on line ${line_num}."
            printMsg "    ${T_ERR_ICON} ${error_reason}"
            printInfoMsg "Expecting 'VARIABLE=VALUE' (no spaces around equals sign)."
            return 1
        fi
    done <"$env_file_path"
    return 0
}

# Sources a specified .env file if it exists and exports its variables.
# It also prints the variables that were found and sourced.
# Usage: load_project_env "/path/to/your/.env"
load_project_env() {
	local env_file_path="$1"
	if [[ ! -f "$env_file_path" ]]; then
		return 0 # Not an error if the file doesn't exist
	fi

    # Validate the file first. The helper function will print detailed errors.
    if ! _validate_env_file "$env_file_path"; then
        return 1
    fi

    # File is valid, now get the variable names for the success message.
    local valid_vars=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        local trimmed_line
        trimmed_line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        if [[ -z "$trimmed_line" || "$trimmed_line" =~ ^# ]]; then
            continue
        fi
        valid_vars+=("${trimmed_line%%=*}")
    done <"$env_file_path"

	# If there are variables to source, print the message and source them.
	if [[ ${#valid_vars[@]} -gt 0 ]]; then
		# printInfoMsg "Sourcing environment variables from ${C_L_BLUE}${env_file_path}${T_RESET}"
		# local pretty_vars
		# pretty_vars=$(printf ", %s" "${valid_vars[@]}")
		# printMsg "    Found: ${C_L_CYAN}${pretty_vars:2}${T_RESET}"

		set -a
		# shellcheck source=/dev/null
		source "$env_file_path"
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
    if _check_command_exists "systemctl" && [ -d /run/systemd/system ]; then
        _IS_SYSTEMD=0 # true
    else
        _IS_SYSTEMD=1 # false
    fi
    return "$_IS_SYSTEMD"
}

# Checks if a given service is known to systemd.
# Assumes _is_systemd_system() has been checked.
# Usage: _is_systemd_service_known <service_name>
# Returns 0 if found, 1 otherwise.
_is_systemd_service_known() {
    local service_name="$1"
    # 'systemctl cat' is a direct way to check if a service exists
    # It will return a non-zero exit code if the service doesn't exist.
    # We redirect stdout and stderr to /dev/null to suppress all output.
    if systemctl cat "${service_name}" &>/dev/null; then
        return 0 # Found
    else
        return 1 # Not found
    fi
}

# Public-facing check if a given systemd service exists.
# Usage: check_systemd_service_exists <service_name>
# Returns 0 if it exists, 1 otherwise.
check_systemd_service_exists() {
    local service_name="$1"
    if ! _is_systemd_system || ! _is_systemd_service_known "${service_name}"; then
        return 1
    fi
    return 0
}

# Helper to show systemd logs and exit on failure.
show_logs_and_exit() {
    local message="$1"
    printErrMsg "$message"
    # Check if journalctl is available before trying to use it.
    if _check_command_exists "journalctl"; then
        printMsg "    ${T_INFO_ICON} Preview of system log:"
        # Indent the journalctl output for readability
        journalctl -u ollama.service -n 10 --no-pager | sed 's/^/    /'
    else
        printMsg "    ${T_WARN_ICON} 'journalctl' not found. Cannot display logs."
    fi
    exit 1
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
# --- OpenWebUI Helpers ---

# Gets the full URL for the OpenWebUI service.
# It respects the OPEN_WEBUI_PORT environment variable.
# Usage:
#   local webui_url
#   webui_url=$(get_openwebui_url)
get_openwebui_url() {
    local webui_port=${OPEN_WEBUI_PORT:-3000}
    echo "http://localhost:${webui_port}"
}

# Checks if the OpenWebUI container is running.
# Returns 0 if running, 1 otherwise.
check_openwebui_container_running() {
    # Use the shared helper to run docker compose. It will find the webui dir.
    # We pipe the output to grep, and check the status of the pipe.
    # Redirect stderr to /dev/null to hide "no such service" errors if compose file is bad.
    if run_webui_compose ps --filter "status=running" --services 2>/dev/null | grep -q "open-webui"; then
        return 0 # Running
    else
        return 1 # Not running
    fi
}

# Helper to show OpenWebUI logs and exit on failure.
show_webui_logs_and_exit() {
    local message="$1"
    printErrMsg "$message"
    # Check if run_webui_compose is available before trying to use it.
    if command -v run_webui_compose &>/dev/null; then
        printMsg "    ${T_INFO_ICON} Preview of container logs:"
        # Indent the logs for readability
        run_webui_compose logs --tail=20 | sed 's/^/    /'
    fi
    exit 1
}

# --- Test Framework ---
# These are not 'local' so the helper functions can access them.
test_count=0 # Global test counter
failures=0   # Global failure counter

# Initializes or resets the test suite counters.
# This should be called at the beginning of any `run_tests` function.
initialize_test_suite() {
    test_count=0
    failures=0
}

# (Private) Helper to run a single string comparison test case.
# Usage: _run_string_test "actual_output" "expected_output" "description"
_run_string_test() {
    local actual="$1"
    local expected="$2"
    local description="$3"
    ((test_count++))

    if [[ "$actual" == "$expected" ]]; then
        _test_passed "${description}"
    else
        # Sanitize output for printing to prevent control characters from
        # messing up the terminal output. `printf %q` is perfect for this.
        local sanitized_expected sanitized_actual
        sanitized_expected=$(printf '%q' "$expected")
        sanitized_actual=$(printf '%q' "$actual")
        _test_failed "${description}"
        printErrMsg "    Expected: ${sanitized_expected}"
        printErrMsg "    Got:      ${sanitized_actual}"
        ((failures++))
    fi
}

# (Private) Helper to run a single return code test case.
# Usage: _run_test "command_to_run" <expected_code> "description"
_run_test() {
    local cmd_string="$1"
    local expected_code="$2"
    local description="$3"
    ((test_count++))

    # Run command in a subshell to not affect the test script's state,
    # and capture its stdout and stderr.
    local output
    output=$(eval "$cmd_string" 2>&1)
    local actual_code=$?

    if [[ $actual_code -eq $expected_code ]]; then
        _test_passed "${description}"
    else
        _test_failed "${description}" "Expected: ${expected_code}, Got: ${actual_code}"
        # Print the captured output on failure for debugging
        if [[ -n "$output" ]]; then
            while IFS= read -r line; do
                printf '    %s\n' "$line"
            done <<< "$output"
        fi
        ((failures++))
    fi
}

# (Private) Helper to run a single test case for the compare_versions function.
# It is defined at the script level to ensure it's available when called.
# It accesses the `test_count` and `failures` variables from its caller's scope.
# Usage: _run_compare_versions_test "v1" "v2" <expected_code> "description"
_run_compare_versions_test() {
    local v1="$1"
    local v2="$2"
    local expected_code="$3"
    local description="$4"
    ((test_count++))

    compare_versions "$v1" "$v2"
    local actual_code=$?
    if [[ $actual_code -eq $expected_code ]]; then
        _test_passed "${description}"
    else
        _test_failed "${description}" "Expected: ${expected_code}, Got: ${actual_code}"
        ((failures++))
    fi
}

# (Private) Helper to print a passing test message.
# Usage: testPassed "description"
_test_passed() {
    printOkMsg "${C_L_GREEN}PASS${T_RESET}: ${1}"
}

# (Private) Helper to print a failing test message.
# Usage: testFailed "description" ["additional_info"]
_test_failed() {
    local description="$1"
    local additional_info="$2"
    if [[ -n "$additional_info" ]]; then
        printErrMsg "${C_L_RED}FAIL${T_RESET}: ${description} (${additional_info})"
    else
        printErrMsg "${C_L_RED}FAIL${T_RESET}: ${description}"
    fi
}

# Prints summary for test suite.
# Reads global variables 'test_count' and 'failures'.
# Exits with 0 on success and 1 on failure.
# Usage:
#   print_test_summary "mock_function1" "mock_function2" ...
# Arguments:
#   $@ - Optional list of mock function names to unset before exiting.
print_test_summary() {
    printTestSectionHeader "Test Summary"

    if [[ $failures -eq 0 ]]; then
        printOkMsg "All ${test_count} tests passed!"
    else
        printErrMsg "${failures} of ${test_count} tests failed."
    fi

    # Unset any mock functions passed as arguments
    if [[ $# -gt 0 ]]; then
        # The -f flag is important to unset functions.
        # Using -- prevents arguments like "-f" from being interpreted as options.
        # Redirecting stderr to /dev/null suppresses "not found" errors if a mock
        # wasn't defined (e.g., due to a test suite being skipped).
        unset -f -- "$@" &>/dev/null
    fi

    if [[ $failures -eq 0 ]]; then exit 0; else exit 1; fi
}

# Checks for Docker and Docker Compose. Exits if not found.
# Usage: check_docker_prerequisites [--silent]
#   --silent: If provided, success messages will be cleared instead of printed.
check_docker_prerequisites() {
    local silent=false
    if [[ "$1" == "--silent" ]]; then
        silent=true
    fi

    printMsgNoNewline "${T_INFO_ICON} Checking for Docker... " >&2
    if ! _check_command_exists "docker"; then
        echo >&2 # Newline before error message
        printErrMsg "Docker is not installed. Please install Docker to continue." >&2
        exit 1
    fi
    if $silent; then
        clear_current_line >&2
    else
        printOkMsg "Docker is installed." >&2
    fi

    printMsgNoNewline "${T_INFO_ICON} Checking for Docker Compose... " >&2
    # Check for either v2 (plugin) or v1 (standalone)
    if ! (_check_command_exists "docker" && \
            docker compose version &>/dev/null) && \
        ! _check_command_exists "docker-compose"; then
        echo >&2 # Newline before error message
        printErrMsg "Docker Compose is not installed." >&2
        exit 1
    fi
    if $silent; then
        clear_current_line >&2
    else
        printOkMsg "Docker Compose is available." >&2
    fi
}