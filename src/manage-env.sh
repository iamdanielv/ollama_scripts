#!/bin/bash
#
# manage-env.sh
#
# An interactive TUI for managing environment variables in a .env file.
# It supports adding, editing, and deleting variables, along with special
# comments in the format: ##@ <VAR> comment text
#

set -o pipefail

# --- Source shared libraries ---
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
# shellcheck source=./lib/shared.lib.sh
if ! source "${SCRIPT_DIR}/lib/shared.lib.sh"; then
    echo "Error: Could not source shared.lib.sh. Make sure it's in the 'src/lib' directory." >&2
    exit 1
fi

# --- Script Globals ---
declare -A ENV_VARS # Associative array to hold variable values
declare -A ENV_COMMENTS # Associative array to hold comments
declare -a ENV_ORDER # Array to maintain the original order of variables
declare -a DISPLAY_ORDER # Filtered array for TUI display (only real variables)

FILE_PATH="" # Path to the .env file being edited
ERROR_MESSAGE="" # Holds the current validation error message

# --- Core Logic ---

# Parses the specified .env file into the global arrays.
# It handles variables, comments, and blank lines, preserving order.
function parse_env_file() {
    local file_to_parse="$1"
    # Reset state
    ENV_VARS=()
    ENV_COMMENTS=()
    ENV_ORDER=()
    DISPLAY_ORDER=()
    ERROR_MESSAGE=""

    if [[ ! -f "$file_to_parse" ]]; then
        # File doesn't exist, which is fine. We'll create it on save.
        return
    fi

    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        local trimmed_line; trimmed_line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

        if [[ -z "$trimmed_line" ]]; then
            ENV_ORDER+=("BLANK_LINE_${line_num}")
            continue
        fi

        # Handle special comments: ##@ VAR ...
        if [[ "$trimmed_line" =~ ^##@[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]+(.*) ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local comment_text="${BASH_REMATCH[2]}"
            ENV_COMMENTS["$var_name"]="$comment_text"
            # Don't add to ENV_ORDER here; the associated variable will handle it.
            continue
        fi

        # Handle regular comments
        if [[ "$trimmed_line" =~ ^# ]]; then
            ENV_ORDER+=("COMMENT_LINE_${line_num}")
            ENV_VARS["COMMENT_LINE_${line_num}"]="$line"
            continue
        fi

        # Handle variable assignments
        if [[ "$trimmed_line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)=(.*) ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            # Best Practice: Unquote values for internal storage. Quotes are for file representation.
            if [[ "$value" =~ ^\"(.*)\"$ ]]; then
                value="${BASH_REMATCH[1]}"
            fi

            if [[ -n "${ENV_VARS[$key]}" ]]; then
                ERROR_MESSAGE="Validation Error: Duplicate key '$key' found on line $line_num."
                return 1
            fi

            ENV_VARS["$key"]="$value"
            ENV_ORDER+=("$key")
            DISPLAY_ORDER+=("$key")
        else
            ERROR_MESSAGE="Validation Error: Invalid format on line $line_num: '$line'"
            return 1
        fi
    done < "$file_to_parse"
}

# Saves the current state from the global arrays back to the .env file.
function save_env_file() {
    local file_to_save="$1"
    local mode="${2:-save}" # "save" or "get_content"
    local temp_file; temp_file=$(mktemp)
    # Ensure temp file is cleaned up on script exit or interrupt
    # Only set the trap if we are in save mode, to avoid conflicts when just getting content.
    if [[ "$mode" == "save" ]]; then
        trap 'rm -f "$temp_file"' EXIT
    fi

    for key in "${ENV_ORDER[@]}"; do
        if [[ "$key" =~ ^BLANK_LINE_ ]]; then
            echo "" >> "$temp_file"
        elif [[ "$key" =~ ^COMMENT_LINE_ ]]; then
            echo "${ENV_VARS[$key]}" >> "$temp_file"
        else
            # This is a regular variable. Check if it has a special comment.
            if [[ -n "${ENV_COMMENTS[$key]}" ]]; then
                echo "##@ $key ${ENV_COMMENTS[$key]}" >> "$temp_file"
            fi

            # Best Practice: Add quotes only if the value contains spaces or is empty.
            local value="${ENV_VARS[$key]}"
            if [[ "$value" == *[[:space:]]* || -z "$value" ]]; then
                echo "$key=\"$value\"" >> "$temp_file"
            else
                echo "$key=$value" >> "$temp_file"
            fi
        fi
    done

    if [[ "$mode" == "get_content" ]]; then
        cat "$temp_file"
        rm -f "$temp_file"
        return 0
    fi

    # Safely overwrite the original file
    if mv "$temp_file" "$file_to_save"; then
        local relative_path="$file_to_save"
        # Attempt to find project root to create a friendlier relative path.
        if _find_project_root --silent && [[ "$file_to_save" == "$_PROJECT_ROOT"* ]]; then
            relative_path=".${file_to_save#$_PROJECT_ROOT}"
        fi

        clear_current_line
        show_timed_message "${T_OK_ICON} Saved changes to ${C_L_BLUE}${relative_path}${T_RESET}" 1.5
        return 0
    else
        rm -f "$temp_file"
        show_timed_message "${T_ERR_ICON} Failed to save changes to ${C_L_BLUE}${relative_path}${T_RESET}" 2.5
        return 1
    fi
}

# (Private) Checks if there are any pending changes by comparing the current
# in-memory state with a fresh parse of the original file.
_has_pending_changes() {
    local original_content=""
    # Only read the file if it exists. If not, original content is empty.
    if [[ -f "$FILE_PATH" ]]; then
        original_content=$(<"$FILE_PATH")
    fi
    local current_content; current_content=$(save_env_file "" "get_content")

    if [[ "$original_content" != "$current_content" ]]; then
        return 0 # Has changes
    else
        return 1 # No changes
    fi
}

# --- TUI Components ---

function show_help() {
    printBanner "Interactive .env Manager"
    printMsg "A TUI for managing environment variables in a .env file."
    printMsg "Supports adding, editing, and deleting variables and their comments."

    printMsg "\n${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [path_to_env_file]"
    printMsg "  Defaults to '.env' in the project root if no path is given."

    printMsg "\n${T_ULINE}Options:${T_RESET}"
    printMsg "  ${C_L_BLUE}-h, --help${T_RESET}      Show this help message."

    printMsg "\n${T_ULINE}Examples:${T_RESET}"
    printMsg "  ${C_GRAY}# Edit the root .env file${T_RESET}"
    printMsg "  $(basename "$0")"
    printMsg "  ${C_GRAY}# Edit a specific .env file${T_RESET}"
    printMsg "  $(basename "$0") ./openwebui/.env"
}

# (Private) Draws the UI for the variable editor screen.
_draw_variable_editor() {
    local current_key="$1"
    local pending_key="$2"
    local current_value="$3"
    local pending_value="$4"
    local current_comment="$5"
    local pending_comment="$6"

    # Use the combined display helper to show pending changes with an arrow.
    local name_display; name_display=$(_get_combined_display "name" "$current_key" "$pending_key")
    local value_display; value_display=$(_get_combined_display "value" "$current_value" "$pending_value")
    local comment_display; comment_display=$(_get_combined_display "comment" "$current_comment" "$pending_comment")

    printf "${C_BLUE}┗━━${T_RESET} ${C_WHITE}${T_BOLD}${T_ULINE}Choose an option to configure:${T_RESET}\n"
    _print_menu_item "1" "Name" "$name_display"
    _print_menu_item "2" "Value" "$value_display"
    _print_menu_item "3" "Comment" "$comment_display"
    printMsg ""
    _print_menu_item "s" "${C_L_GREEN}(S)tage${T_RESET} changes and return"
    _print_menu_item "c" "${C_L_YELLOW}(C)ancel/${T_RESET}discard changes"
    printMsg "" # Add blank line before prompt.
}

# (Private) Gets a formatted display string for a given setting value.
# This is a simplified version of the one in config-ollama.sh.
_get_setting_display() {
    local setting_type="$1"
    local value="$2"

    case "$setting_type" in
        "name")
            if [[ -n "$value" ]]; then echo "${C_L_BLUE}${value}${T_RESET}"; else echo "${C_GRAY}(empty)${T_RESET}"; fi
            ;;
        "value")
            if [[ -n "$value" ]]; then echo "${C_L_CYAN}${value}${T_RESET}"; else echo "${C_GRAY}(empty)${T_RESET}"; fi
            ;;
        "comment")
            if [[ -n "$value" ]]; then echo "${C_GRAY}${value}${T_RESET}"; else echo "${C_GRAY}(none)${T_RESET}"; fi
            ;;
        *)
            if [[ -n "$value" ]]; then echo "$value"; else echo "${C_GRAY}(default)${T_RESET}"; fi
            ;;
    esac
}

# (Private) Gets a display string showing current and pending states if they differ.
_get_combined_display() {
    local setting_type="$1"
    local current_val="$2"
    local pending_val="$3"

    local pending_display; pending_display=$(_get_setting_display "$setting_type" "$pending_val")

    if [[ "$current_val" != "$pending_val" ]]; then
        local current_display; current_display=$(_get_setting_display "$setting_type" "$current_val")
        echo -e "${current_display} ${C_WHITE}→${T_RESET} ${pending_display}"
    else
        echo -e "$pending_display"
    fi
}

# (Private) Helper to print a formatted menu item for the editor.
_print_menu_item() {
    local key="$1"
    local text1="$2"
    local text2="$3"

    if [[ -n "$text2" ]]; then
        printf " ${T_BOLD}${key})${T_RESET} %-10s - %b${T_CLEAR_LINE}\n" "$text1" "$text2"
    else
        printf " ${T_BOLD}${key})${T_RESET} %b${T_CLEAR_LINE}\n" "$text1"
    fi
}

# Draws the main list of environment variables.
function draw_var_list() {
    local -n current_option_ref=$1
    local -n list_offset_ref=$2
    local viewport_height=$3

    local list_content=""
    local start_index=$list_offset_ref
    local end_index=$(( list_offset_ref + viewport_height - 1 ))
    if (( end_index >= ${#DISPLAY_ORDER[@]} )); then end_index=$(( ${#DISPLAY_ORDER[@]} - 1 )); fi

    if [[ ${#DISPLAY_ORDER[@]} -gt 0 ]]; then
        for (( i=start_index; i<=end_index; i++ )); do
            local key="${DISPLAY_ORDER[i]}"
            local is_current="false"; if (( i == current_option_ref )); then is_current="true"; fi
            local line_output=""

            if [[ "$key" =~ ^(BLANK_LINE_|COMMENT_LINE_) ]]; then
                local display_text="${ENV_VARS[$key]:-${C_GRAY}(Blank Line)${T_RESET}}"
                line_output=$(_format_fixed_width_string "${C_GRAY}${display_text}${T_RESET}" 70)
            else
                local value="${ENV_VARS[$key]}"
                local comment="${ENV_COMMENTS[$key]}"
                local value_display; value_display=$(_truncate_string "${value}" 20)
                local comment_display; comment_display=$(_truncate_string "${comment}" 22)
                line_output=$(printf "${C_L_BLUE}%-21s${T_FG_RESET} ${C_L_CYAN}%-20s${T_FG_RESET} ${C_GRAY}%-22s${T_FG_RESET}" "${key}" "$value_display" "$comment_display")
            fi

            local item_content=""
            _draw_menu_item "$is_current" "false" "false" "$line_output\n" item_content
            list_content+="${item_content}"
        done
    else
        list_content+=$(printf "  %s" "${C_GRAY}(No variables found. Press 'A' to add one.)${T_CLEAR_LINE}${T_RESET}")
    fi

    # Fill remaining viewport with blank lines
    local list_draw_height=$(( end_index - start_index + 1 ))
    if (( ${#DISPLAY_ORDER[@]} <= 0 )); then list_draw_height=1; fi
    local lines_to_fill=$(( viewport_height - list_draw_height ))
    if (( lines_to_fill > 0 )); then
        for ((j=0; j<lines_to_fill; j++)); do list_content+=$(printf '\n%s' "${T_CLEAR_LINE}"); done
    fi

    printf "%b" "$list_content"
}

# Draws the header for the variable list.
function draw_header() {
    printf "${C_BLUE}┗━━ ${T_FG_RESET}${T_BOLD}${T_ULINE}%-22s${T_RESET} ${T_BOLD}${T_ULINE}%-20s${T_RESET} ${T_BOLD}${T_ULINE}%-22s${T_RESET}" "VARIABLE" "VALUE" "COMMENT"
}

# Draws the footer with keybindings and error messages.
function draw_footer() {
    local help_nav=" ${C_L_CYAN}↑↓${C_WHITE} Move | ${C_L_BLUE}(E)dit${C_WHITE} | ${C_L_GREEN}(A)dd${C_WHITE} | ${C_L_RED}(D)elete${C_WHITE}"
    local help_exit=" ${C_L_GREEN}(S)ave${C_WHITE} | ${C_L_YELLOW}(Q)uit${C_WHITE}"
    printf " %s | %s\n" "$help_nav" "$help_exit"

    if [[ -n "$ERROR_MESSAGE" ]]; then
        printf " ${T_ERR_ICON} %s${T_CLEAR_LINE}" "${T_ERR}${ERROR_MESSAGE}${T_RESET}"
    else
        local relative_path="$FILE_PATH"
        if _find_project_root --silent && [[ "$FILE_PATH" == "$_PROJECT_ROOT"* ]]; then
            relative_path=".${FILE_PATH#$_PROJECT_ROOT}"
        fi
        printf " ${T_BOLD}${T_OK_ICON} Valid File: ${C_L_BLUE}%s${T_RESET}${T_CLEAR_LINE}" "${relative_path}"
    fi
}

# Handles editing an existing variable or adding a new one.
function edit_variable() {
    local -n current_option_idx_ref=$1
    local mode="$2" # "add" or "edit"

    local key value comment
    local original_key original_value original_comment
    local pending_key pending_value pending_comment

    if [[ "$mode" == "edit" ]]; then
        original_key="${DISPLAY_ORDER[current_option_idx_ref]}"
        # Disallow editing of comments/blank lines
        if [[ "$original_key" =~ ^(BLANK_LINE_|COMMENT_LINE_) ]]; then
            show_timed_message "${T_WARN_ICON} Cannot edit blank lines or comments." 1.5
            return 2 # Signal no change
        fi
        key="$original_key"
        original_value="${ENV_VARS[$original_key]}"
        original_comment="${ENV_COMMENTS[$original_key]}"
        pending_key="$original_key"
        pending_value="$original_value"
        pending_comment="$original_comment"
    fi

    # --- Add Mode: Prompt for key first ---
    if [[ "$mode" == "add" ]]; then
        key="NEW_VARIABLE"
        # For 'add' mode, originals are empty
        original_value=""
        pending_key="NEW_VARIABLE"
        original_comment=""
        pending_value=""
        pending_comment=""
    fi

    # --- Interactive Editor Loop ---
    while true; do
        clear_screen
        printBanner "Edit Variable: ${C_L_YELLOW}${key}${C_BLUE}"
        _draw_variable_editor "$original_key" "$pending_key" "$original_value" "$pending_value" "$original_comment" "$pending_comment"

        printMsgNoNewline " ${T_QST_ICON} Your choice: "
        local choice; choice=$(read_single_char)
        clear_current_line

        case "$choice" in
            1)
                # Edit Value
                if ! prompt_for_input "New Name" pending_key "$pending_key" "false" 5; then continue; fi
                if ! [[ "$pending_key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
                    show_timed_message "${T_ERR_ICON} Invalid variable name. Must be alphanumeric and start with a letter or underscore." 3
                    pending_key="$original_key" # Revert
                elif [[ "$pending_key" != "$original_key" && -n "${ENV_VARS[$pending_key]}" ]]; then
                    show_timed_message "${T_ERR_ICON} Variable '$pending_key' already exists." 2
                    pending_key="$original_key" # Revert
                fi
                ;;
            2)
                # Edit Value
                prompt_for_input "New Value" pending_value "$pending_value" "true" 5
                ;;
            3)
                # Edit Comment
                prompt_for_input "New Comment" pending_comment "$pending_comment" "true" 5
                ;;
            's'|'S')
                # Save
                # If the key has changed, we need to perform a rename operation.
                if [[ "$pending_key" != "$original_key" ]]; then
                    # Remove old entries
                    unset "ENV_VARS[$original_key]"
                    unset "ENV_COMMENTS[$original_key]"

                    # Find the key in ENV_ORDER and replace it
                    for i in "${!ENV_ORDER[@]}"; do
                        if [[ "${ENV_ORDER[i]}" == "$original_key" ]]; then
                            ENV_ORDER[i]="$pending_key"
                            break
                        fi
                    done
                    # Also update the display order array
                    for i in "${!DISPLAY_ORDER[@]}"; do
                        if [[ "${DISPLAY_ORDER[i]}" == "$original_key" ]]; then
                            DISPLAY_ORDER[i]="$pending_key"
                        fi
                    done
                fi

                ENV_VARS["$pending_key"]="$pending_value"
                if [[ -n "$pending_comment" ]]; then
                    ENV_COMMENTS["$pending_key"]="$pending_comment"
                else
                    unset "ENV_COMMENTS[$pending_key]"
                fi
                if [[ "$mode" == "add" ]]; then
                    ENV_ORDER+=("$pending_key")
                    DISPLAY_ORDER+=("$pending_key")
                fi
                return 0 # Success, needs refresh
                ;;
            'c'|'C'|"$KEY_ESC")
                # Cancel
                if [[ "$pending_key" != "$original_key" || "$pending_value" != "$original_value" || "$pending_comment" != "$original_comment" ]]; then
                    if ! prompt_yes_no "You have unsaved changes. Discard them?" "y"; then
                        continue # Go back to editor
                    fi
                fi
                return 2 # No change
                ;;
        esac
    done
}

# Deletes the variable at the current cursor position.
function delete_variable() {
    local -n current_option_idx_ref=$1
    local key_to_delete="${DISPLAY_ORDER[current_option_idx_ref]}"

    if [[ "$key_to_delete" =~ ^(BLANK_LINE_|COMMENT_LINE_) ]]; then
        show_timed_message "${T_WARN_ICON} Cannot delete blank lines or comments this way." 1.5
        return 2 # No refresh needed
    fi
    
    clear_current_line
    clear_lines_up 1
    if prompt_yes_no "Delete variable '${C_L_RED}${key_to_delete}${T_RESET}'?" "n"; then
        # Remove from all state arrays
        unset "ENV_VARS[$key_to_delete]"
        unset "ENV_COMMENTS[$key_to_delete]"

        local new_env_order=()
        for item in "${ENV_ORDER[@]}"; do
            if [[ "$item" != "$key_to_delete" ]]; then
                new_env_order+=("$item")
            fi
        done
        ENV_ORDER=("${new_env_order[@]}")

        local new_display_order=()
        for item in "${DISPLAY_ORDER[@]}"; do
            if [[ "$item" != "$key_to_delete" ]]; then
                new_display_order+=("$item")
            fi
        done
        DISPLAY_ORDER=("${new_display_order[@]}")

        # Adjust cursor if we deleted the last item
        if (( current_option_idx_ref >= ${#DISPLAY_ORDER[@]} && ${#DISPLAY_ORDER[@]} > 0 )); then
            current_option_idx_ref=$(( ${#DISPLAY_ORDER[@]} - 1 ))
        fi

        return 0 # Needs refresh
    fi
    return 2 # No refresh needed
}

# --- TUI Main Loop ---

function interactive_manager() {
    local current_option=0
    local list_offset=0

    # --- TUI Helper Functions ---
    _header_func() { draw_header; }
    _footer_func() { draw_footer; }
    _refresh_func() {
        # This is a dummy refresh function for the generic TUI loop.
        # Data is managed locally in this script.
        :
    }
    _viewport_calc_func() {
        # Calculate available height for the list
        local term_height; term_height=$(tput lines)
        # banner(1) + header(1) + list(...) + div(1) + footer(2)
        echo $(( term_height - 5 ))
    }

    # --- Key Handler ---
    _key_handler() {
        local key="$1"
        local -n current_option_ref="$2"
        local -n num_options_ref="$3"
        local -n handler_result_ref="$4"

        case "$key" in
            'q'|'Q'|"$KEY_ESC")
                if _has_pending_changes; then
                    clear_current_line
                    clear_lines_up 1
                    if prompt_yes_no "You have unsaved changes. Quit without saving?" "n"; then
                        handler_result_ref="exit"
                    else
                        handler_result_ref="redraw" # User cancelled, so redraw the menu
                    fi
                else
                    handler_result_ref="exit" # No changes, exit immediately
                fi
                ;;
            's'|'S')
                if ! _has_pending_changes; then
                    clear_current_line
                    clear_lines_up 1
                    show_timed_message " ${T_INFO_ICON} No changes to save." 1.5
                    handler_result_ref="redraw"
                else
                    clear_current_line
                    clear_lines_up 1
                    if prompt_yes_no "Are you sure you want to save these changes?" "y"; then
                        save_env_file "$FILE_PATH"
                        handler_result_ref="refresh_data" # Re-parse file after saving
                    fi
                    handler_result_ref="redraw" # Redraw whether saved or cancelled
                fi
                ;;
            'a'|'A')
                local edit_result
                edit_variable current_option_ref "add"
                edit_result=$?
                if [[ $edit_result -eq 0 ]]; then handler_result_ref="refresh_data"; fi
                if [[ $edit_result -eq 2 ]]; then handler_result_ref="redraw"; fi
                ;;
            'e'|'E')
                # If there are no variables, treat 'edit' as 'add'.
                local mode="edit"
                if [[ ${num_options_ref} -eq 0 ]]; then
                    mode="add"
                fi

                local edit_result
                edit_variable current_option_ref "$mode"
                edit_result=$?
                if [[ $edit_result -eq 0 ]]; then handler_result_ref="refresh_data"; fi
                if [[ $edit_result -eq 2 ]]; then handler_result_ref="redraw"; fi
                ;;
            'd'|'D')
                if delete_variable current_option_ref; then
                    handler_result_ref="refresh_data"
                else
                    handler_result_ref="redraw"
                fi
                ;;
            *)
                handler_result_ref="noop"
                ;;
        esac
    }

    # --- Custom List View Loop ---
    # This is a simplified version of _interactive_list_view from tui.lib.sh
    # to better handle local state management.
    (
        printMsgNoNewline "${T_CURSOR_HIDE}"
        trap 'printMsgNoNewline "${T_CURSOR_SHOW}"' EXIT

        local viewport_height
        local _tui_resized=0
        trap '_tui_resized=1' WINCH

        while true; do
            # --- Recalculate and Redraw ---
            viewport_height=$(_viewport_calc_func)
            num_options=${#DISPLAY_ORDER[@]}

            # Adjust scroll offset
            if (( current_option >= list_offset + viewport_height )); then list_offset=$(( current_option - viewport_height + 1 )); fi
            if (( current_option < list_offset )); then list_offset=$current_option; fi
            local max_offset=$(( num_options - viewport_height )); if (( max_offset < 0 )); then max_offset=0; fi
            if (( list_offset > max_offset )); then list_offset=$max_offset; fi
            if (( num_options < viewport_height )); then list_offset=0; fi

            # --- Double-buffer drawing ---
            local screen_buffer=""
            screen_buffer+=$(generate_banner_string "Environment Variable Manager")
            screen_buffer+=$'\n'
            screen_buffer+=$(_header_func)
            screen_buffer+=$'\n'
            # The div after the header is removed since the header is underlined.
            screen_buffer+=$(draw_var_list current_option list_offset "$viewport_height")
            screen_buffer+="${C_GRAY}${DIV}${T_RESET}\n"
            screen_buffer+=$(_footer_func)
            printf '\033[H%b' "$screen_buffer"

            # --- Handle Input ---
            local key; key=$(read_single_char)
            local handler_result="noop"

            if [[ $_tui_resized -eq 1 ]]; then
                _tui_resized=0
                handler_result="redraw"
            fi

            case "$key" in
                "$KEY_UP"|"k") if (( num_options > 0 )); then current_option=$(( (current_option - 1 + num_options) % num_options )); handler_result="redraw"; fi ;;
                "$KEY_DOWN"|"j") if (( num_options > 0 )); then current_option=$(( (current_option + 1) % num_options )); handler_result="redraw"; fi ;;
                "$KEY_PGUP") if (( num_options > 0 )); then current_option=$(( current_option - viewport_height )); if (( current_option < 0 )); then current_option=0; fi; handler_result="redraw"; fi ;;
                "$KEY_PGDN") if (( num_options > 0 )); then current_option=$(( current_option + viewport_height )); if (( current_option >= num_options )); then current_option=$(( num_options - 1 )); fi; handler_result="redraw"; fi ;;
                "$KEY_HOME") if (( num_options > 0 )); then current_option=0; handler_result="redraw"; fi ;;
                "$KEY_END") if (( num_options > 0 )); then current_option=$(( num_options - 1 )); handler_result="redraw"; fi ;;
                *)
                    _key_handler "$key" current_option num_options handler_result
                    ;;
            esac

            # If the save key was pressed, the key handler shows its own prompt.
            # We should skip redrawing the main UI to avoid output collision.
            case "$key" in
                's'|'S') continue ;;
            esac

            if [[ "$handler_result" == "exit" ]]; then
                break
            elif [[ "$handler_result" == "refresh_data" ]]; then
                # After a save, we re-parse the file to get a clean state.
                # For other actions like 'add' or 'delete', the state is already
                # updated in memory, so we just need to redraw.
                if [[ "$key" == "s" || "$key" == "S" ]]; then
                    parse_env_file "$FILE_PATH"
                fi
                # Loop will redraw
            fi
        done
    )
    clear
}

# --- Main Execution ---

main() {
    # --- Argument Parsing ---
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_help
        exit 0
    fi

    # Determine the target .env file
    if [[ -n "$1" ]]; then
        FILE_PATH="$1"
    else
        if _find_project_root; then
            FILE_PATH="${_PROJECT_ROOT}/.env"
        else
            printErrMsg "Could not find project root. Please specify a path to a .env file."
            exit 1
        fi
    fi

    # Ensure the directory for the .env file exists
    local file_dir; file_dir=$(dirname "$FILE_PATH")
    if [[ ! -d "$file_dir" ]]; then
        if prompt_yes_no "Directory '${file_dir}' does not exist. Create it?" "y"; then
            mkdir -p "$file_dir"
        else
            printInfoMsg "Operation cancelled."
            exit 1
        fi
    fi

    # Initial parse of the .env file
    if ! parse_env_file "$FILE_PATH"; then
        # An error occurred during parsing, but we can still open the editor
        # The error will be displayed in the footer.
        :
    fi

    # Launch the interactive TUI
    interactive_manager

    printOkMsg "Exited .env manager."
}

main "$@"
