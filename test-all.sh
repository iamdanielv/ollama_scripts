#!/bin/bash
#
# Runs all script self-tests.
#
# This script iterates through all .sh files in the current directory,
# checks if they support a '-t' or '--test' flag, and executes them.
# It then reports a summary of which tests passed and which failed.
#

# Load shared functions
# shellcheck disable=SC1091
source "$(dirname "$0")/shared.sh"

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
    # It ignores lines starting with #.
    if grep -q -E '^\s*\|?\s*(-t|--test).*\)|^\s*[^#]*if.*["'\''](-t|--test)["'\'']' "$script_path"; then
        return 0 # Testable
    else
        return 1 # Not testable
    fi
}

run_tests() {
    printBanner "Running Self-Tests for test-all.sh"
    initialize_test_suite

    # Create a temporary directory for our test files
    local temp_dir
    temp_dir=$(mktemp -d)
    # Ensure cleanup on exit
    trap 'rm -rf "$temp_dir"' EXIT

    # --- Create Test Files ---
    # Testable cases
    echo 'case "$1" in -t|--test) exit 0 ;; esac' > "$temp_dir/testable_case.sh"
    echo 'if [[ "$1" == "-t" ]]; then exit 0; fi' > "$temp_dir/testable_if.sh"
    echo 'if [[ "$1" == "--test" ]]; then exit 0; fi' > "$temp_dir/testable_if_long.sh"
    echo 'if [[ "$a" == "b" || "$1" == "--test" ]]; then exit 0; fi' > "$temp_dir/testable_if_or.sh"
    echo '    -t|--test) # indented case' > "$temp_dir/testable_case_indent.sh"

    # Not-testable cases
    echo 'echo "no test flag"' > "$temp_dir/not_testable_simple.sh"
    echo '# This is a comment about -t|--test)' > "$temp_dir/not_testable_comment.sh"
    echo 'echo "this is a test"' > "$temp_dir/not_testable_word.sh"
    echo 'ss -tlpn | column -t' > "$temp_dir/not_testable_false_positive.sh" # The original bug
    echo 'if [[ "$1" == "--another-test" ]]; then exit 0; fi' > "$temp_dir/not_testable_other_flag.sh"
    local unreadable_file="$temp_dir/unreadable.sh"
    touch "$unreadable_file"
    chmod 000 "$unreadable_file"

    # This script's own path for testing the --check flag
    local script_path="${BASH_SOURCE[0]}"

    # --- Run Assertions ---
    printTestSectionHeader "Testing script detection logic"
    _run_test "_is_script_testable '$temp_dir/testable_case.sh'" 0 "Detects 'case' statement"
    _run_test "_is_script_testable '$temp_dir/testable_if.sh'" 0 "Detects 'if' statement with -t"
    _run_test "_is_script_testable '$temp_dir/testable_if_long.sh'" 0 "Detects 'if' statement with --test"
    _run_test "_is_script_testable '$temp_dir/testable_if_or.sh'" 0 "Detects 'if' statement with ||"
    _run_test "_is_script_testable '$temp_dir/testable_case_indent.sh'" 0 "Detects indented 'case' statement"

    printTestSectionHeader "Testing non-testable scripts are skipped"
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

  # Create a temporary file to store test output
  local test_output_file
  test_output_file=$(mktemp)

  # Ensure the temporary file is cleaned up on exit (including Ctrl+C)
  trap 'rm -f "$test_output_file"' EXIT

  local -a all_scripts
  mapfile -t all_scripts < <(find . -maxdepth 1 -name "*.sh" -type f -not -name "$(basename "$0")" -not -name "shared.sh" | sort)
  local testable_scripts=()
  local not_testable_scripts=()
  local failed_scripts=()
  local passed_count=0
  local failed_count=0

  # --- Discover testable scripts ---
  for script in "${all_scripts[@]}"; do
    script_name=$(basename "$script")
    if _is_script_testable "$script"; then
      testable_scripts+=("$script_name")
    else
      not_testable_scripts+=("$script_name")
    fi
  done

  if [ ${#testable_scripts[@]} -eq 0 ]; then
    printWarnMsg "No testable scripts found."
    exit 0
  fi

  printInfoMsg "Found ${#testable_scripts[@]} testable scripts. Running tests..."
  printMsg "" # empty line to add some space

  printMsg "${T_ULINE}${C_L_WHITE}    Running tests for:${T_RESET}"
  # --- Run tests ---
  for script_name in "${testable_scripts[@]}"; do
    # Run the test, redirecting all output to the temporary file.
    # This is more robust than capturing to a variable.
    if bash "$script_name" --test >"$test_output_file" 2>&1; then
      printOkMsg "${C_L_GREEN}PASS${T_RESET}: ${C_L_BLUE}$script_name${T_RESET}"
      passed_count=$((passed_count + 1))
    else
      printErrMsg "${C_L_RED}FAIL${T_RESET}: ${T_BOLD}$script_name${T_RESET}"
      failed_count=$((failed_count + 1))
      failed_scripts+=("$script_name")
      # Indent the captured output from the temp file for readability
      sed 's/^/        /' "$test_output_file"
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
    local not_testable_list
    not_testable_list=$(IFS=' '; echo "${not_testable_scripts[*]}")
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
