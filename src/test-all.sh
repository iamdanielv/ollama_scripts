#!/bin/bash
#
# Runs all script self-tests.
#
# This script iterates through all .sh files in the current directory,
# checks if they support a '-t' or '--test' flag, and executes them.
# It then reports a summary of which tests passed and which failed.
#

# Load shared functions
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
# shellcheck source=./lib/shared.lib.sh
if ! source "${SCRIPT_DIR}/lib/shared.lib.sh"; then
    echo "Error: Could not source shared.lib.sh. Make sure it's in the 'src/lib' directory." >&2
    exit 1
fi

# --- Self-Test Functions ---

# Helper function to encapsulate the detection logic for easy testing.
# Usage: _is_script_testable <path_to_script>
# Returns 0 if testable, 1 otherwise.
_is_script_testable() {
    local script_path="$1"
    # Check for test flags in shell script logic (case or if statements)
    # This is more robust than a simple grep for the flag.
    # It looks for patterns like:
    #   -t|--test) in a case statement
    #   if ... [[ "$1" == "-t" || ... ]]
    # The regex for 'case' is designed to avoid false positives from command
    # substitutions like `var=$(... command -t)`. It does this by excluding lines
    # that contain an equals sign ('=') or are comments ('#') before the flag.

    # Check for case statement patterns like: -t) or -t|--test)
    if grep -q -E '^\s*[^#=)'\'']*(-t|--test)\b[^)]*\)' "$script_path"; then
        return 0 # Testable
    fi

    # Check for if statement patterns like: if [[ "$1" == "-t" ]]
    if grep -q -E 'if\s+.*["'\''](-t|--test)["'\'']' "$script_path"; then
        return 0 # Testable
    fi

    return 1 # Not testable
}

run_tests() {
    printBanner "Running Self-Tests for test-all.sh"
    initialize_test_suite

    # Create a temporary directory for our test files
    local temp_dir
    # Declare separately to avoid masking mktemp's exit code.
    temp_dir=$(mktemp -d)
    # Ensure cleanup on exit
    trap 'rm -rf "$temp_dir"' EXIT

    # --- Create Test Files ---
    # Testable cases
    echo 'case "$1" in -t|--test) exit 0 ;; esac' > "$temp_dir/testable_case.sh"
    echo 'case "$1" in -t) exit 0 ;; esac' > "$temp_dir/testable_case_single.sh"
    echo '    -t|--test) # indented case' > "$temp_dir/testable_case_indent.sh"

    # More specific testable cases for '-t'
    echo 'case "$1" in -t|--other) exit 0;; esac' > "$temp_dir/testable_case_t_first.sh"
    echo 'case "$1" in --other|-t) exit 0;; esac' > "$temp_dir/testable_case_t_last.sh"
    echo '    -t) # indented case with only -t' > "$temp_dir/testable_case_indent_single.sh"

    # Whitespace variations
    echo 'case "$1" in -t  |--test) exit 0;; esac' > "$temp_dir/testable_case_space_before_pipe.sh"
    echo 'case "$1" in -t|  --test) exit 0;; esac' > "$temp_dir/testable_case_space_after_pipe.sh"
    echo 'case "$1" in -t  |  --test  ) exit 0;; esac' > "$temp_dir/testable_case_many_spaces.sh"
    echo '  -t) # indented with spaces' > "$temp_dir/testable_case_indent_spaces.sh"

    # Tests for if statements
    echo 'if [[ "$1" == "-t" ]]; then exit 0; fi' > "$temp_dir/testable_if.sh"
    echo 'if [[ "$1" == "--test" ]]; then exit 0; fi' > "$temp_dir/testable_if_long.sh"
    echo 'if [[ "$a" == "b" || "$1" == "--test" ]]; then exit 0; fi' > "$temp_dir/testable_if_or.sh"

    # Multi-line case statement tests
    cat <<- 'EOF' > "$temp_dir/testable_case_multiline_full.sh"
		#!/bin/bash
		case "$1" in
		    -h|--help) echo "Help"; exit 0 ;;
		    -t|--test)
		        echo "Running tests"
		        exit 0
		        ;;
		    *) echo "Default"; exit 1 ;;
		esac
	EOF

    # Not-testable cases
    echo 'case "$1" in --teaast) exit 0 ;; esac' > "$temp_dir/not_testable_substring.sh"
    echo 'echo "no test flag"' > "$temp_dir/not_testable_simple.sh"
    echo '# This is a comment about -t|--test)' > "$temp_dir/not_testable_comment.sh"
    echo 'echo "this is a test"' > "$temp_dir/not_testable_word.sh"
    echo 'ss -tlpn | column -t' > "$temp_dir/not_testable_false_positive.sh" # A known false positive pattern
    echo 'if [[ "$1" == "--another-test" ]]; then exit 0; fi' > "$temp_dir/not_testable_other_flag.sh"
    local unreadable_file="$temp_dir/unreadable.sh"
    touch "$unreadable_file"
    chmod 000 "$unreadable_file"

    # This script's own path for testing the --check flag
    local script_path
    # If BASH_SOURCE[0] doesn't contain a slash, it's a bare command name
    # that was found via the PATH or run by `bash script.sh`.
    # Prepend './' to make it executable from the current directory for the test.
    if [[ "${BASH_SOURCE[0]}" != */* ]]; then
        script_path="./${BASH_SOURCE[0]}"
    else
        script_path="${BASH_SOURCE[0]}"
    fi
    # --- Run Assertions ---
    # testing for case
    printTestSectionHeader "Testing script detection logic for -- case --"
    _run_test "_is_script_testable '$temp_dir/testable_case.sh'" 0 "Detects 'case' statement with -t|--test"
    _run_test "_is_script_testable '$temp_dir/testable_case_single.sh'" 0 "Detects 'case' statement with just -t"
    _run_test "_is_script_testable '$temp_dir/testable_case_indent.sh'" 0 "Detects indented 'case' statement"
    _run_test "_is_script_testable '$temp_dir/testable_case_t_first.sh'" 0 "Detects 'case' with -t as first option"
    _run_test "_is_script_testable '$temp_dir/testable_case_t_last.sh'" 0 "Detects 'case' with -t as last option"
    _run_test "_is_script_testable '$temp_dir/testable_case_indent_single.sh'" 0 "Detects indented 'case' with only -t"

    printTestSectionHeader "Testing whitespace variations"
    _run_test "_is_script_testable '$temp_dir/testable_case_space_before_pipe.sh'" 0 "Detects 'case' with space before pipe"
    _run_test "_is_script_testable '$temp_dir/testable_case_space_after_pipe.sh'" 0 "Detects 'case' with space after pipe"
    _run_test "_is_script_testable '$temp_dir/testable_case_many_spaces.sh'" 0 "Detects 'case' with multiple spaces"
    _run_test "_is_script_testable '$temp_dir/testable_case_indent_spaces.sh'" 0 "Detects indented 'case' with spaces"

    # testing for if
    printTestSectionHeader "Testing script detection logic for -- if --"
    _run_test "_is_script_testable '$temp_dir/testable_if.sh'" 0 "Detects 'if' statement with -t"
    _run_test "_is_script_testable '$temp_dir/testable_if_long.sh'" 0 "Detects 'if' statement with --test"
    _run_test "_is_script_testable '$temp_dir/testable_if_or.sh'" 0 "Detects 'if' statement with ||"

    printTestSectionHeader "Testing multi-line case statements"
    _run_test "_is_script_testable '$temp_dir/testable_case_multiline_full.sh'" 0 "Detects multi-line 'case' statement"
   
    # Testing that files are reported as NOT Testable
    printTestSectionHeader "Testing non-testable scripts are skipped"
    _run_test "_is_script_testable '$temp_dir/not_testable_substring.sh'" 1 "Skips substring matches like --teaast"
    _run_test "_is_script_testable '$temp_dir/not_testable_simple.sh'" 1 "Skips script with no test flag"
    _run_test "_is_script_testable '$temp_dir/not_testable_comment.sh'" 1 "Skips commented out test flag"
    _run_test "_is_script_testable '$temp_dir/not_testable_word.sh'" 1 "Skips the word 'test'"
    _run_test "_is_script_testable '$temp_dir/not_testable_false_positive.sh'" 1 "Skips false positive from 'column -t)'"
    _run_test "_is_script_testable '$temp_dir/not_testable_other_flag.sh'" 1 "Skips other similar flags"

    printTestSectionHeader "Testing command-line flags"
    _run_string_test "$($script_path --check "$temp_dir/testable_case.sh")" "Testable" "Reports 'Testable' for a testable file via --check"
    _run_string_test "$($script_path --check "$temp_dir/not_testable_simple.sh")" "NOT Testable" "Reports 'NOT Testable' for a non-testable file via --check"
    _run_test "$script_path --check &>/dev/null" 1 "Fails when --check is missing a file path"
    _run_test "$script_path --check /non/existent/file &>/dev/null" 1 "Fails when --check file does not exist"
    _run_test "$script_path --check '$unreadable_file' &>/dev/null" 1 "Fails when --check file is not readable"

    print_test_summary
}

# --- Main Logic ---

main() {
  # Handle self-test mode
  if [[ "$1" == "-t" || "$1" == "--test" ]]; then
    run_tests
    exit $?
  fi

  # Handle single file check mode
  if [[ "$1" == "--check" ]]; then
    local file_to_check="$2"
    if [[ -z "$file_to_check" ]]; then
        printErrMsg "The --check flag requires a file path."
        exit 1
    fi
    if [[ ! -f "$file_to_check" ]]; then
        printErrMsg "File not found: $file_to_check"
        exit 1
    fi
    if [[ ! -r "$file_to_check" ]]; then
        printErrMsg "File is not readable: $file_to_check"
        exit 1
    fi

    if _is_script_testable "$file_to_check"; then
        echo "Testable"
    else
        echo "NOT Testable"
    fi
    exit 0
  fi

  prereq_checks "grep" "mktemp" "sed"

  # Create a temporary directory to store test results
  local results_dir
  # Declare separately to avoid masking mktemp's exit code.
  results_dir=$(mktemp -d)
  trap 'rm -rf "$results_dir"' EXIT

  local -a all_scripts
  mapfile -t all_scripts < <(find "$SCRIPT_DIR" -maxdepth 1 -name "*.sh" -type f | sort)
  local testable_scripts=()
  local not_testable_scripts=()
  local failed_scripts=()
  local passed_count=0
  local failed_count=0
  local -a pids=()

  # --- Discover testable scripts ---
  for script in "${all_scripts[@]}"; do
    if _is_script_testable "$script"; then
      # Store the full path to the script
      testable_scripts+=("$script")
    else
      not_testable_scripts+=("$(basename "$script")")
    fi
  done

  if [ ${#testable_scripts[@]} -eq 0 ]; then
    printWarnMsg "No testable scripts found."
    exit 0
  fi

  printInfoMsg "Found ${#testable_scripts[@]} testable scripts. Running tests..."
  printMsg "" # empty line to add some space

  printMsg "${T_ULINE}${C_L_WHITE}    Running tests in parallel...${T_RESET}"
  # --- Run tests in parallel ---
  for script_path in "${testable_scripts[@]}"; do
    local script_name; script_name=$(basename "$script_path")
    # Each test runs in a subshell in the background.
    # We save the exit code and output to separate files for later processing.
    (
      local output_file="${results_dir}/${script_name}.log"
      local exit_code_file="${results_dir}/${script_name}.exit"
      bash "$script_path" --test >"$output_file" 2>&1
      echo $? >"$exit_code_file"
    ) &
    pids+=($!)
  done

  # Wait for all background jobs to finish
  wait_for_pids_with_spinner "Running all tests" "${pids[@]}"
  clear_lines_up 1 # Clear the spinner's success message for cleaner output

  # --- Process results ---
  printMsg "${T_ULINE}${C_L_WHITE}    Test Results:${T_RESET}"
  for script_path in "${testable_scripts[@]}"; do
    local script_name; script_name=$(basename "$script_path")
    local output_file="${results_dir}/${script_name}.log"
    local exit_code_file="${results_dir}/${script_name}.exit"
    local exit_code
    exit_code=$(<"$exit_code_file")

    if [[ "$exit_code" -eq 0 ]]; then
      printOkMsg "${C_L_GREEN}PASS${T_RESET}: ${C_L_BLUE}$script_name${T_RESET}"
      passed_count=$((passed_count + 1))
      # For passing tests, show just the summary content (not the header).
      # This finds the line after "Test Summary", takes non-blank lines, and indents them.
      awk '/Test Summary/ {f=1; next} f && NF' "$output_file" | sed 's/^/      /'
    else
      printErrMsg "${C_L_RED}FAIL${T_RESET}: ${T_BOLD}$script_name${T_RESET}"
      failed_count=$((failed_count + 1))
      failed_scripts+=("$script_name")
      sed 's/^/        /' "$output_file"
      echo # Add a blank line for spacing after the failure output
    fi
  done

  # --- Test Summary ---
  printTestSectionHeader "Test Summary:"
  printOkMsg "Passed: $passed_count"
  if [ "$failed_count" -gt 0 ]; then
    printErrMsg "Failed: $failed_count"
    for failed in "${failed_scripts[@]}"; do
      echo "  - $failed"
    done
  else
    printOkMsg "Failed: 0"
  fi

  local not_testable_count=${#not_testable_scripts[@]}
  if [ "$not_testable_count" -gt 0 ]; then
    printf -v not_testable_list '%s ' "${not_testable_scripts[@]}"
    # Trim trailing space from printf
    not_testable_list="${not_testable_list% }"
    printInfoMsg "Not Testable: $not_testable_count"
    printInfoMsg "  $not_testable_list"
  else
    printInfoMsg "Not Testable: 0"
  fi
  echo

  if [ "$failed_count" -gt 0 ]; then
    exit 1
  fi

  exit 0
}

# --- Entrypoint ---
main "$@"
