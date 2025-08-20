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

# --- Main Logic ---

main() {
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
    # Check for test flags in shell script logic (case or if statements)
    # This is more robust than a simple grep for the flag.
    # It looks for patterns like:
    #   -t|--test) in a case statement
    #   if ... [[ "$1" == "-t" || ... ]]
    # It ignores lines starting with #.
    if grep -q -E '^\s*[^#]*(-t|--test)\s*.*[)]|^\s*[^#]*if.*(-t|--test)' "$script"; then
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
