#!/bin/bash
# A library of shared utilities for building Terminal User Interfaces (TUIs).

# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -o pipefail

# --- Shared Utilities ---

#region Colors and Styles
export C_RED=$'\033[31m'
export C_GREEN=$'\033[32m'
export C_YELLOW=$'\033[33m'
export C_BLUE=$'\033[34m'
export C_MAGENTA=$'\033[35m'
export C_CYAN=$'\033[36m'
export C_WHITE=$'\033[37m'
export C_GRAY=$'\033[38;5;244m'
export C_L_RED=$'\033[31;1m'
export C_L_GREEN=$'\033[32m'
export C_L_YELLOW=$'\033[33m'
export C_L_BLUE=$'\033[34m'
export C_L_MAGENTA=$'\033[35m'
export C_L_CYAN=$'\033[36m'
export C_L_WHITE=$'\033[37;1m'
export C_L_GRAY=$'\033[38;5;252m'

# Background Colors
export BG_BLACK=$'\033[40;1m'
export BG_RED=$'\033[41m'
export BG_GREEN=$'\033[42;1m'
export BG_YELLOW=$'\033[43m'
export BG_BLUE=$'\033[44m'

export C_BLACK=$'\033[30;1m'

export T_RESET=$'\033[0m'
export T_BOLD=$'\033[1m'
export T_ULINE=$'\033[4m'
export T_REVERSE=$'\033[7m'
export T_CLEAR_LINE=$'\033[K'
export T_CURSOR_HIDE=$'\033[?25l'
export T_CURSOR_SHOW=$'\033[?25h'
export T_FG_RESET=$'\033[39m' # Reset foreground color only
export T_BG_RESET=$'\033[49m' # Reset background color only

export T_ERR="${T_BOLD}${C_L_RED}"
export T_ERR_ICON="[${T_BOLD}${C_RED}✗${T_RESET}]"

export T_OK_ICON="[${T_BOLD}${C_GREEN}✓${T_RESET}]"
export T_INFO_ICON="[${T_BOLD}${C_YELLOW}i${T_RESET}]"
export T_WARN_ICON="[${T_BOLD}${C_YELLOW}!${T_RESET}]"
export T_QST_ICON="[${T_BOLD}${C_L_CYAN}?${T_RESET}]"
#endregion Colors and Styles

export DIV="──────────────────────────────────────────────────────────────────────"

#region Key Codes
export KEY_ESC=$'\033'
export KEY_UP=$'\033[A'
export KEY_DOWN=$'\033[B'
export KEY_RIGHT=$'\033[C'
export KEY_LEFT=$'\033[D'
export KEY_ENTER="ENTER"
export KEY_TAB=$'\t'
export KEY_BACKSPACE=$'\x7f' # ASCII DEL character for backspace
export KEY_HOME=$'\033[H'
export KEY_END=$'\033[F'
export KEY_DELETE=$'\033[3~'
export KEY_CTRL_D=$'\x04' # ASCII End of Transmission
#endregion Key Codes

#region Logging & Banners
printMsg() { printf '%b\n' "$1"; }
printMsgNoNewline() { printf '%b' "$1"; }
printErrMsg() { printMsg "${T_ERR_ICON}${T_BOLD}${C_L_RED} ${1} ${T_RESET}"; }
printOkMsg() { printMsg "${T_OK_ICON} ${1}${T_RESET}"; }
printInfoMsg() { printMsg "${T_INFO_ICON} ${1}${T_RESET}"; }
printWarnMsg() { printMsg "${T_WARN_ICON} ${1}${T_RESET}"; }

strip_ansi_codes() {
    local s="$1"; local esc=$'\033'
    if [[ "$s" != *"$esc"* ]]; then echo -n "$s"; return; fi
    local pattern="$esc\\[[0-9;]*[a-zA-Z]"
    while [[ $s =~ $pattern ]]; do s="${s/${BASH_REMATCH[0]}/}"; done
    echo -n "$s"
}

_truncate_string() {
    local input_str="$1"; local max_len="$2"; local trunc_char="${3:-…}"; local trunc_char_len=${#trunc_char}
    local stripped_str; stripped_str=$(strip_ansi_codes "$input_str"); local len=${#stripped_str}
    if (( len <= max_len )); then echo -n "$input_str"; return; fi
    local truncate_to_len=$(( max_len - trunc_char_len )); local new_str=""; local visible_count=0; local i=0; local in_escape=false
    while (( i < ${#input_str} && visible_count < truncate_to_len )); do
        local char="${input_str:i:1}"; new_str+="$char"
        if [[ "$char" == $'\033' ]]; then in_escape=true; elif ! $in_escape; then (( visible_count++ )); fi
        if $in_escape && [[ "$char" =~ [a-zA-Z] ]]; then in_escape=false; fi; ((i++))
    done
    echo -n "${new_str}${trunc_char}"
}

generate_banner_string() {
    local text="$1"; local total_width=70; local prefix="┏"; local line
    printf -v line '%*s' "$((total_width - 1))"; line="${line// /━}"; printf '%s' "${C_L_BLUE}${prefix}${line}${T_RESET}"; printf '\r'
    local text_to_print; text_to_print=$(_truncate_string "$text" $((total_width - 3)))
    printf '%s' "${C_L_BLUE}${prefix} ${text_to_print} ${T_RESET}"
}

_format_fixed_width_string() {
    local input_str="$1"; local max_len="$2"; local trunc_char="${3:-…}"
    local stripped_str; stripped_str=$(strip_ansi_codes "$input_str"); local len=${#stripped_str}
    if (( len <= max_len )); then
        local padding_needed=$(( max_len - len ))
        printf "%s%*s" "$input_str" "$padding_needed" ""
    else
        _truncate_string "$input_str" "$max_len" "$trunc_char"
    fi
}

format_menu_lines() {
    local -a lines=("$@"); local -a formatted_lines=(); local total_width=70
    for line in "${lines[@]}"; do formatted_lines+=("$(_format_fixed_width_string "   ${line}" "$total_width")"); done
    (IFS=$'\n'; echo "${formatted_lines[*]}")
}

printBanner() { printMsg "$(generate_banner_string "$1")"; }
#endregion Logging & Banners

#region Terminal Control
clear_screen() { printf '\033[H\033[J' >/dev/tty; }
clear_current_line() { printf '\033[2K\r' >/dev/tty; }
clear_lines_up() {
    local lines=${1:-1}; for ((i = 0; i < lines; i++)); do printf '\033[1A\033[2K'; done; printf '\r'
} >/dev/tty
clear_lines_down() {
    local lines=${1:-1}; if (( lines <= 0 )); then return; fi
    for ((i = 0; i < lines; i++)); do printf '\033[2K\n'; done; printf '\033[%sA' "$lines"
} >/dev/tty
move_cursor_up() {
    local lines=${1:-1}; if (( lines > 0 )); then for ((i = 0; i < lines; i++)); do printf '\033[1A'; done; fi; printf '\r'
} >/dev/tty

move_cursor_to() {
    local line=${1:-1} column=${2:-1}; printf '\033[%s;%sH' "$line" "$column"
} >/dev/tty

save_cursor_pos() {
    printf '\033[s'
} >/dev/tty

restore_cursor_pos() {
    printf '\033[u'
} >/dev/tty

# A debug helper to display the current cursor position at the top-right of the screen.
# Call this at any point in a TUI function to see where the cursor is.
# It saves and restores the cursor position, so it doesn't disrupt the layout.
# Usage: debug_show_cursor_pos
debug_show_cursor_pos() {
    # Get current cursor position. The terminal responds with `ESC[<row>;<col>R`.
    local pos
    IFS=';' read -s -d R -p $'\E[6n' pos >/dev/tty
    local row="${pos#*[}"
    local col="${pos#*;}"

    # Save current cursor position and attributes
    printf '\033[s' >/dev/tty

    # Print a red star at the current position to make it stand out.
    printf '%s' "${C_L_RED}*${T_RESET}" >/dev/tty
    # Move the cursor back to its original position before we printed the star.
    printf '\033[1D' >/dev/tty

    # Move to top-right corner to display the coordinates
    local term_width; term_width=$(tput cols)
    local msg="R:${row} C:${col}"
    local display_col=$(( term_width - ${#msg} ))
    printf '\033[1;%sH' "$display_col" >/dev/tty
    printf '%s' "${BG_YELLOW}${C_BLACK}${msg}${T_RESET}" >/dev/tty

    # The star and coordinates will be visible until the next screen redraw,
    # which usually happens on the next keypress in the TUI loop.
    # We restore the cursor so the next draw operation starts from the correct place.

    # Restore original cursor position and attributes
    printf '\033[u' >/dev/tty
}
#endregion Terminal Control

#region User Input
read_single_char() {
    local char; local seq; IFS= read -rsn1 char
    if [[ -z "$char" ]]; then echo "$KEY_ENTER"; return; fi
    if [[ "$char" == "$KEY_ESC" ]]; then
        while IFS= read -rsn1 -t 0.001 seq; do char+="$seq"; done
    fi
    echo "$char"
}

prompt_to_continue() {
    printInfoMsg "Press any key to continue..." >/dev/tty
    read_single_char >/dev/null
    clear_lines_up 1
}

# Prints a message for a fixed duration, then clears it. Does not wait for user input.
# Useful for brief status updates that don't require user acknowledgement.
# Usage: show_timed_message "My message" [duration]
show_timed_message() {
    local message="$1"
    local duration="${2:-1.8}"

    # Calculate how many lines the message will take up to clear it correctly.
    # This is important for multi-line messages (e.g., from terminal wrapping).
    local message_lines; message_lines=$(echo -e "$message" | wc -l)

    printMsg "$message" >/dev/tty
    sleep "$duration"
    # Also redirect to /dev/tty to ensure it works when stdout is captured.
    clear_lines_up "$message_lines" >/dev/tty
}

# Prints a standardized, single-line summary of an action that was just taken.
# This is useful for providing feedback after a prompt is successfully answered.
# It truncates the label and value to fit neatly on one line.
# Usage: show_action_summary "Label" "Value"
show_action_summary() {
    local label="$1"
    local value="$2"
    local total_width=70
    local icon_len; icon_len=$(strip_ansi_codes "${T_QST_ICON} " | wc -c)
    local separator_len=2 # for ": "
    local available_width=$(( total_width - icon_len - separator_len ))
    local label_width=$(( available_width / 3 )); local value_width=$(( available_width - label_width ))

    local truncated_label; truncated_label=$(_truncate_string "$label" "$label_width")
    local truncated_value; truncated_value=$(_truncate_string "${C_L_GREEN}${value}${T_RESET}" "$value_width")

    printMsg "${T_QST_ICON} ${truncated_label}: ${truncated_value}" >/dev/tty
}

# An interactive yes/no prompt that handles single-character input.
# It supports default answers and cancellation.
# Usage: prompt_yes_no "Your question?" [default_answer: y/n]
# Returns 0 for 'yes', 1 for 'no', and 2 for cancellation (ESC/q).
prompt_yes_no() {
    local question="$1"
    local default_answer="${2:-}"
    local has_error=false
    local answer
    local prompt_suffix

    if [[ "$default_answer" == "y" ]]; then prompt_suffix="(Y/n)"; elif [[ "$default_answer" == "n" ]]; then prompt_suffix="(y/N)"; else prompt_suffix="(y/n)"; fi
    local question_lines; question_lines=$(echo -e "$question" | wc -l)

    _clear_all_prompt_content() {
        clear_current_line >/dev/tty
        if (( question_lines > 1 )); then clear_lines_up $(( question_lines - 1 )); fi
        if $has_error; then clear_lines_up 1; fi
    }

    printf '%b' "${T_QST_ICON} ${question} ${prompt_suffix} " >/dev/tty

    while true; do
        answer=$(read_single_char </dev/tty)
        if [[ "$answer" == "$KEY_ENTER" ]]; then answer="$default_answer"; fi

        case "$answer" in
            [Yy]|[Nn])
                _clear_all_prompt_content
                if [[ "$answer" =~ [Yy] ]]; then return 0; else return 1; fi
                ;;
            "$KEY_ESC"|"q")
                _clear_all_prompt_content
                show_timed_message " ${C_L_YELLOW}-- cancelled --${T_RESET}" 1
                return 2 # Cancelled
                ;;
            *)
                _clear_all_prompt_content; printErrMsg "Invalid input. Please enter 'y' or 'n'." >/dev/tty; has_error=true
                printf '%b' "${T_QST_ICON} ${question} ${prompt_suffix} " >/dev/tty ;;
        esac
    done
}

# (Private) Handles the logic for toggling a selection in a multi-select list.
# It also manages the special behavior of an "All" option if present.
# Usage: _handle_multi_select_toggle <is_multi_select> <current_option> <num_options> <selected_options_nameref>
_handle_multi_select_toggle() {
    local is_multi_select="$1"
    local current_option="$2"
    local num_options="$3"
    local -n selected_options_ref="$4" # Nameref to the selected options array

    if [[ "$is_multi_select" != "true" ]]; then
        return
    fi

    # Toggle the state of the currently highlighted option.
    selected_options_ref[current_option]=$(( 1 - selected_options_ref[current_option] ))

    # Special handling for an "All" option at index 0.
    if (( num_options > 1 )); then # Assumes "All" is only relevant if there are other options.
        if (( current_option == 0 )); then # If "All" was just toggled...
            local all_state=${selected_options_ref[0]}
            for i in "${!selected_options_ref[@]}"; do selected_options_ref[i]=$all_state; done
        else # An individual item was toggled, so we need to update the "All" status.
            local all_selected=1
            # Check if all items (from index 1 onwards) are selected.
            for ((i=1; i<num_options; i++)); do
                if [[ ${selected_options_ref[i]} -eq 0 ]]; then
                    all_selected=0
                    break
                fi
            done
            # Set the "All" checkbox state accordingly.
            selected_options_ref[0]=$all_selected
        fi
    fi
}

# An interactive prompt for user input that supports cancellation.
# It provides a rich line-editing experience including cursor movement
# (left/right/home/end), insertion, and deletion (backspace/delete). This version
# handles long input by scrolling the text horizontally. It can also replace a
# block of existing lines (like a TUI footer) to prevent UI shifting.
# Usage: prompt_for_input "Prompt text" "variable_name" ["default_value"] ["allow_empty"] [lines_to_replace]
# Returns 0 on success (Enter), 1 on cancellation (ESC).
prompt_for_input() {
    local prompt_text="$1"
    local -n var_ref="$2" # Use nameref to assign to caller's variable
    local default_val="${3:-}"
    local allow_empty="${4:-false}"
    local lines_to_replace="${5:-0}" # Optional: Number of lines this prompt should occupy.

    # If not replacing lines, it's a standalone prompt that takes over the screen.
    if (( lines_to_replace == 0 )); then
        clear_screen
    fi

    # Explicitly show the cursor for the input prompt.
    printMsgNoNewline "${T_CURSOR_SHOW}" >/dev/tty

    local input_str="$default_val" cursor_pos=${#input_str} view_start=0 key

    local icon_prefix_len; icon_prefix_len=$(strip_ansi_codes "${T_QST_ICON} " | wc -c)
    local padding; printf -v padding '%*s' "$icon_prefix_len" ""
    local indented_prompt_text; indented_prompt_text=$(echo -e "$prompt_text" | sed "2,\$s/^/${padding}/")

    # Print the prompt text. Using `printf %b` handles newlines without adding an extra one at the end.
    printf '%b' "${T_QST_ICON} ${indented_prompt_text}" >/dev/tty
    # The actual input line starts with a simple prefix, printed right after the prompt text.
    local input_prefix=": "
    printMsgNoNewline "$input_prefix" >/dev/tty

    # Calculate how many lines the prompt text occupies for later cleanup.
    local prompt_lines; prompt_lines=$(echo -e "${indented_prompt_text}" | wc -l)

    # If replacing lines, fill the remaining space with blank lines to maintain height.
    if (( lines_to_replace > prompt_lines )); then
        local blank_lines_needed=$(( lines_to_replace - prompt_lines ))
        for ((i=0; i<blank_lines_needed; i++)); do
            # Print a newline and a clear-line code to ensure it's blank.
            printf '\n%s' "${T_CLEAR_LINE}"
        done
        # Move cursor back up to the input line.
        move_cursor_up "$blank_lines_needed"
    fi
    local input_line_prefix_len
    if (( prompt_lines > 1 )); then
        local last_line_prompt; last_line_prompt=$(echo -e "${indented_prompt_text}" | tail -n 1)
        input_line_prefix_len=$(strip_ansi_codes " ${last_line_prompt}${input_prefix}" | wc -c)
    else
        input_line_prefix_len=$(strip_ansi_codes "${T_QST_ICON} ${prompt_text}${input_prefix}" | wc -c)
    fi

    # (Private) Helper to redraw the input line.
    _prompt_for_input_redraw() {
        # Go to beginning of line, then move right past the static prompt.
        printf '\r\033[%sC' "$input_line_prefix_len" >/dev/tty

        local term_width; term_width=$(tput cols)
        local available_width=$(( term_width - input_line_prefix_len ))
        if (( available_width < 1 )); then available_width=1; fi

        # --- Scrolling logic ---
        if (( cursor_pos < view_start )); then view_start=$cursor_pos; fi
        if (( cursor_pos >= view_start + available_width )); then view_start=$(( cursor_pos - available_width + 1 )); fi

        local display_str="${input_str:$view_start:$available_width}" local total_len=${#input_str}

        # --- Ellipsis logic for overflow ---
        local ellipsis="…"
        if (( total_len > available_width )); then
            if (( view_start > 0 )); then
                # We've scrolled right, show ellipsis on the left.
                display_str="${ellipsis}${display_str:1}"
            fi
            if (( view_start + available_width < total_len )); then
                # There's more text to the right, show ellipsis on the right.
                display_str="${display_str:0:${#display_str}-1}${ellipsis}"
            fi
        fi

        # Print the dynamic part: colored input, reset color, and clear rest of line.
        # This overwrites the previous input and clears any leftover characters.
        printMsgNoNewline "${C_L_CYAN}${display_str}${T_RESET}${T_CLEAR_LINE}" >/dev/tty

        # --- Cursor positioning ---
        local display_cursor_pos=$(( cursor_pos - view_start )); if (( view_start > 0 )); then ((display_cursor_pos++)); fi
        local chars_after_cursor=$(( ${#display_str} - display_cursor_pos ))
        if (( chars_after_cursor > 0 )); then
            printf '\033[%sD' "$chars_after_cursor" >/dev/tty
        fi
    }

    while true; do
        _prompt_for_input_redraw

        key=$(read_single_char </dev/tty)

        case "$key" in
            "$KEY_ENTER")
                if [[ -n "$input_str" || "$allow_empty" == "true" ]]; then
                    var_ref="$input_str"
                    # On success, clear the area that was used by the prompt.
                    local lines_to_clear=$(( lines_to_replace > 0 ? lines_to_replace : prompt_lines ))
                    clear_current_line >/dev/tty; clear_lines_up $(( lines_to_clear - 1 )) >/dev/tty

                    # Show a summary of the accepted input.
                    show_action_summary "$prompt_text" "$var_ref"
                    printMsgNoNewline "${T_CURSOR_HIDE}" >/dev/tty
                    return 0
                fi
                ;;
            "$KEY_ESC")
                local lines_to_clear=$(( lines_to_replace > 0 ? lines_to_replace : prompt_lines ))
                clear_current_line >/dev/tty; clear_lines_up $(( lines_to_clear - 1 )) >/dev/tty; show_timed_message "${T_INFO_ICON} Input cancelled." 1
                printMsgNoNewline "${T_CURSOR_HIDE}" >/dev/tty
                return 1
                ;;
            "$KEY_BACKSPACE")
                if (( cursor_pos > 0 )); then
                    input_str="${input_str:0:cursor_pos-1}${input_str:cursor_pos}"
                    ((cursor_pos--))
                fi
                ;;
            "$KEY_DELETE")
                if (( cursor_pos < ${#input_str} )); then
                    input_str="${input_str:0:cursor_pos}${input_str:cursor_pos+1}"
                fi
                ;;
            "$KEY_LEFT") if (( cursor_pos > 0 )); then ((cursor_pos--)); fi ;;
            "$KEY_RIGHT") if (( cursor_pos < ${#input_str} )); then ((cursor_pos++)); fi ;;
            "$KEY_HOME") cursor_pos=0 ;;
            "$KEY_END") cursor_pos=${#input_str} ;;
            *)
                if (( ${#key} == 1 )) && [[ "$key" =~ [[:print:]] ]]; then
                    input_str="${input_str:0:cursor_pos}${key}${input_str:cursor_pos}"
                    ((cursor_pos++))
                fi
                ;;
        esac
    done
}
#endregion User Input

#region Editor Loop
# (Private) A generic, reusable interactive loop for entity editors (hosts, port forwards).
# This function encapsulates the shared UI loop for adding, editing, and cloning.
#
# It relies on context-specific functions being defined in the caller's scope, which
# have access to the necessary state variables (e.g., new_alias, original_alias).
#
# Usage: _interactive_editor_loop <mode> <banner> <draw_func> <field_handler_func> <change_checker_func> <reset_func>
# Returns 0 if the user chooses to save, 1 if they cancel/quit.
_interactive_editor_loop() {
    local mode="$1" banner_text="$2" draw_func="$3" field_handler_func="$4" change_checker_func="$5" reset_func="$6"

    while true; do
        clear_screen; printBanner "$banner_text"; "$draw_func"
        local key; key=$(read_single_char)
        case "$key" in
            'c'|'C'|'d'|'D')
                clear_current_line
                local question="Discard all pending changes?"; if [[ "$mode" == "add" || "$mode" == "clone" ]]; then question="Discard all changes and reset fields?"; fi
                if prompt_yes_no "$question" "y"; then "$reset_func"; show_timed_message "${T_INFO_ICON} Changes discarded."; fi ;;
            's'|'S') return 0 ;; # Signal to Save
            'q'|'Q'|"$KEY_ESC")
                if "$change_checker_func"; then
                    if ! prompt_yes_no "You have unsaved changes. Quit without saving?" "n"; then
                        show_timed_message "${T_INFO_ICON} Operation cancelled."; return 1
                    fi
                else
                    clear_current_line
                    show_timed_message "${T_INFO_ICON} Edit Host cancelled. No changes were made."
                    return 1
                fi ;;
            *)
                # Delegate to the context-specific field handler.
                # It returns 0 on success (key was handled), 1 on failure (key was not for it).
                if ! "$field_handler_func" "$key"; then :; fi ;; # Key was not handled, loop to redraw.
        esac
    done
}
#endregion

#region Error Handling & Traps
script_exit_handler() { printMsgNoNewline "${T_CURSOR_SHOW}" >/dev/tty; }
trap 'script_exit_handler' EXIT
script_interrupt_handler() {
    trap - INT # Disable the trap to prevent recursion
    # Restore terminal state before exiting
    printMsgNoNewline "${T_CURSOR_SHOW}" >/dev/tty
    stty echo >/dev/tty
    clear_screen
    printMsg "${T_WARN_ICON} ${C_L_YELLOW}Operation cancelled by user.${T_RESET}"
    exit 130
}
trap 'script_interrupt_handler' INT
#endregion Error Handling & Traps

#region Interactive Menus

# (Private) Applies a reverse-video highlight to a string, correctly handling
# any existing ANSI color codes within it.
# Usage: highlighted_string=$(_apply_highlight "my ${C_RED}colored${T_RESET} string")
_apply_highlight() {
    local content="$1"
    # To correctly handle items that have their own color resets (${T_RESET})
    # or foreground resets (${T_FG_RESET}), we perform targeted substitutions.
    # This ensures the background remains highlighted across the entire line.
    local highlight_restore="${T_RESET}${T_REVERSE}${C_L_BLUE}"
    local highlighted_content="${content//${T_RESET}/${highlight_restore}}"
    # Also handle foreground-only resets.
    highlighted_content="${highlighted_content//${T_FG_RESET}/${C_L_BLUE}}"

    printf "%s%s%s%s" \
        "${T_REVERSE}${C_L_BLUE}" \
        "$highlighted_content" \
        "${T_CLEAR_LINE}" \
        "${T_RESET}"
}

# (Private) Gets the appropriate prefix for a menu item.
# Handles pointers and multi-select checkboxes.
# Usage: prefix=$(_get_menu_item_prefix <is_current> <is_selected> <is_multi_select>)
_get_menu_item_prefix() {
    local is_current="$1" is_selected="$2" is_multi_select="$3"

    local pointer=" "
    if [[ "$is_current" == "true" ]]; then
        pointer="${T_BOLD}${C_L_MAGENTA}❯${T_FG_RESET}"
    fi

    local checkbox="   " # One space for alignment in single-select mode
    if [[ "$is_multi_select" == "true" ]]; then
        checkbox="[ ]" # Default unchecked state
        if [[ "$is_selected" == "true" ]]; then
            checkbox="${T_BOLD}${C_GREEN}[✓]"
        fi
    fi

    echo "${pointer}${checkbox}"
}

# (Private) Draws a single item for an interactive menu or list.
# This function encapsulates the complex logic for single-line, multi-line,
# and highlighted rendering, promoting DRY principles.
#
# Usage: _draw_menu_item <is_current> <is_selected> <is_multi_select> <option_text> <output_nameref>
_draw_menu_item() {
    local is_current="$1" is_selected="$2" is_multi_select="$3" option_text="$4"
    local -n output_ref="$5"

    local prefix; prefix=$(_get_menu_item_prefix "$is_current" "$is_selected" "$is_multi_select")

    local item_output=""
    # The option_text is now a pre-rendered, fixed-width string.
    # We just need to add the prefix and apply highlighting if it's the current item.
    if [[ -n "$option_text" ]]; then
        local line_prefix=" " # A single space for padding after the prefix.

        if [[ "$is_current" == "true" ]]; then
            # Apply highlight to the pre-formatted content.
            local highlighted_line
            highlighted_line=$(_apply_highlight "${line_prefix}${option_text}${T_CLEAR_LINE}")
            item_output+=$(printf "%s%s" "$prefix" "$highlighted_line")
        else
            # For non-current items, just combine the parts.
            item_output+=$(printf "%s%s%s%s%s" \
                "$prefix" \
                "$line_prefix" \
                "$option_text" \
                "${T_CLEAR_LINE}" \
                "${T_RESET}")
        fi
    fi
    output_ref+=$item_output
}

# Generic interactive menu function.
interactive_menu() {
    local mode="$1"; local prompt="$2"; local header="$3"; shift 3; local -a options=("$@")

    if ! [[ -t 0 ]]; then printErrMsg "Not an interactive session." >&2; return 1; fi
    local num_options=${#options[@]}; if [[ $num_options -eq 0 ]]; then printErrMsg "No options provided to menu." >&2; return 1; fi

    local current_option=0; local -a selected_options=()
    if [[ "$mode" == "multi" ]]; then for ((i=0; i<num_options; i++)); do selected_options[i]=0; done; fi

    local header_lines=0
    if [[ -n "$header" ]]; then header_lines=$(echo -e "$header" | wc -l); fi

    local menu_content_lines=0
    if (( num_options > 0 )); then
        menu_content_lines=$(printf "%s\n" "${options[@]}" | wc -l)
    fi

    _draw_menu_options() {
        local menu_content=""
        for i in "${!options[@]}"; do
            local is_current="false"; if (( i == current_option )); then is_current="true"; fi
            local is_selected="false"; if [[ "$mode" == "multi" && ${selected_options[i]} -eq 1 ]]; then is_selected="true"; fi
            local is_multi="false"; if [[ "$mode" == "multi" ]]; then is_multi="true"; fi
            _draw_menu_item "$is_current" "$is_selected" "$is_multi" "${options[i]}" menu_content
        done
        printf "%s" "$menu_content"
    }

    # Hide cursor. The global EXIT trap will restore it.
    printMsgNoNewline "${T_CURSOR_HIDE}" >/dev/tty
    printf '%s\n' "${T_QST_ICON} ${prompt}" >/dev/tty; printf '%s\n' "${C_GRAY}${DIV}${T_RESET}" >/dev/tty
    if [[ -n "$header" ]]; then printf '  %s%s\n' "${header}" "${T_RESET}" >/dev/tty; fi
    _draw_menu_options >/dev/tty
    printf '%s\n' "${C_GRAY}${DIV}${T_RESET}" >/dev/tty

    local movement_keys="↓/↑/j/k"; local select_action="${C_L_GREEN}SPACE/ENTER${C_WHITE} to confirm"
    if [[ "$mode" == "multi" ]]; then select_action="${C_L_CYAN}SPACE${C_WHITE} to select | ${C_L_GREEN}ENTER${C_WHITE} to confirm"; fi
    printf '  %s%s%s Move | %s | %s%s%s to cancel%s\n' "${C_L_CYAN}" "${movement_keys}" "${C_WHITE}" "${select_action}" "${C_L_YELLOW}" "Q/ESC" "${C_GRAY}" "${T_RESET}" >/dev/tty

    move_cursor_up 2

    local key; local lines_above=$((1 + header_lines)); local lines_below=2
    while true; do
        move_cursor_up "$menu_content_lines"; key=$(read_single_char </dev/tty)
        case "$key" in
            "$KEY_UP"|"k") current_option=$(( (current_option - 1 + num_options) % num_options ));;
            "$KEY_DOWN"|"j") current_option=$(( (current_option + 1) % num_options ));;
            "$KEY_ESC"|"q") clear_lines_down $((menu_content_lines + lines_below)); clear_lines_up "$lines_above"; return 1;;
            "$KEY_ENTER")
                clear_lines_down $((menu_content_lines + lines_below)); clear_lines_up "$lines_above"
                if [[ "$mode" == "multi" ]]; then
                    local has_selection=0
                    for i in "${!options[@]}"; do if [[ ${selected_options[i]} -eq 1 ]]; then has_selection=1; echo "$i"; fi; done
                    if [[ $has_selection -eq 1 ]]; then return 0; else return 1; fi
                else echo "$current_option"; return 0; fi
                ;;
            ' ')
                if [[ "$mode" == "multi" ]]; then
                    selected_options[current_option]=$(( 1 - selected_options[current_option] ))
                    if [[ "${options[0]}" == "All" ]]; then
                        if (( current_option == 0 )); then local all_state=${selected_options[0]}; for i in "${!options[@]}"; do selected_options[i]=$all_state; done
                        else local all_selected=1; for ((i=1; i<num_options; i++)); do if (( selected_options[i] == 0 )); then all_selected=0; break; fi; done; selected_options[0]=$all_selected; fi
                    fi
                else
                    clear_lines_down $((menu_content_lines + lines_below)); clear_lines_up "$lines_above"
                    echo "$current_option"; return 0
                fi
                ;;
        esac
        _draw_menu_options >/dev/tty;
    done
}

interactive_multi_select_menu() {
    local prompt="$1"; local header="$2"; shift 2
    interactive_menu "multi" "$prompt" "$header" "$@"
}

_interactive_list_view() {
    local banner="$1" header_func="$2" refresh_func="$3" key_handler_func="$4" viewport_calc_func="$5"
    local -n list_offset_ref="$6" # Nameref for scroll offset
    local footer_func="$7" is_multi_select="${8:-false}"

    local current_option=0; local -a menu_options=(); local -a data_payloads=(); local -a selected_options=();
    local num_options=0; local viewport_height=0

    # Flag to signal that the terminal has been resized.
    local _tui_resized=0
    # Trap the WINCH signal (window change) and set the flag.
    # Scroll indicators
    local scroll_up_indicator=" "
    local scroll_down_indicator=" "
    # The actual redraw will happen on the next key press.
    trap '_tui_resized=1' WINCH

    # --- State ---
    local _tui_is_loading=true # Add a loading state flag

    _refresh_data() {
        "$refresh_func" menu_options data_payloads selected_options
        num_options=${#data_payloads[@]}
        if (( current_option >= num_options )); then current_option=$(( num_options - 1 )); fi
        if (( current_option < 0 )); then current_option=0; fi
    }

    # A more advanced refresh function can also populate the selected_options array
    _refresh_data_multi() {
        "$refresh_func" menu_options data_payloads selected_options; num_options=${#menu_options[@]}
        if (( current_option >= num_options )); then current_option=$(( num_options - 1 )); fi
        if (( current_option < 0 )); then current_option=0; fi
    }

    _update_scroll_offset() {
        # Scroll down if selection moves past the bottom of the viewport
        if (( current_option >= list_offset_ref + viewport_height )); then
            list_offset_ref=$(( current_option - viewport_height + 1 ))
        fi
        # Scroll up if selection moves before the top of the viewport
        if (( current_option < list_offset_ref )); then
            list_offset_ref=$current_option
        fi
        # Don't scroll past the end of the list
        local max_offset=$(( num_options - viewport_height ))
        if (( max_offset < 0 )); then max_offset=0; fi # Handle lists smaller than viewport
        if (( list_offset_ref > max_offset )); then
            list_offset_ref=$max_offset
        fi
        # Ensure offset is 0 if list is smaller than viewport
        if (( num_options < viewport_height )); then list_offset_ref=0; fi
    }
    
    _update_scroll_indicators() {
        scroll_up_indicator=" "
        scroll_down_indicator=" "
        if (( list_offset_ref > 0 )); then scroll_up_indicator="${C_L_CYAN}▲"; fi
        if (( list_offset_ref + viewport_height < num_options )); then scroll_down_indicator="${C_L_CYAN}▼"; fi
    }

    _draw_list() {
        local list_content=""
        local start_index=$list_offset_ref
        local end_index=$(( list_offset_ref + viewport_height - 1 ))
        if (( end_index >= num_options )); then end_index=$(( num_options - 1 )); fi

        _update_scroll_indicators

        if [[ $num_options -gt 0 ]]; then
            # Only loop through the visible items
            for (( i=start_index; i<=end_index; i++ )); do
                # Add newline before the item, but not for the very first one in the viewport.
                # The check should be against start_index, not just i > 0.
                if [[ ${#list_content} -gt 0 ]]; then list_content+='\n'; fi
                local is_current="false"; if (( i == current_option )); then is_current="true"; fi
                local is_selected="false"; if [[ "$is_multi_select" == "true" && "${selected_options[i]}" -eq 1 ]]; then is_selected="true"; fi
                
                local scroll_indicator=" "
                if (( i == start_index )); then scroll_indicator="$scroll_up_indicator"; fi
                if (( i == end_index )); then scroll_indicator="$scroll_down_indicator"; fi
                _draw_menu_item "$is_current" "$is_selected" "$is_multi_select" "${menu_options[i]}" list_content
                list_content+="${scroll_indicator}${T_RESET}"
            done
        else
            if [[ "$_tui_is_loading" != "true" ]]; then
                list_content+=$(printf "  %s" "${C_GRAY}(No items found. Press 'A' to add a model.)${T_CLEAR_LINE}${T_RESET}")
            else
                list_content+=$(printf "  %s" "${C_YELLOW}(Loading...)${T_CLEAR_LINE}${T_RESET}")
            fi
        fi

        # Directly calculate the number of lines that were just added to the list_content.
        # This is more reliable than using `wc -l` on a string with ANSI codes.
        local list_draw_height=$(( end_index - start_index + 1 ))
        if (( num_options <= 0 )); then list_draw_height=1; fi # "No items" is 1 line.


        # If the list is shorter than the viewport, add blank lines to fill the space.
        # This prevents old content from being left behind on the screen.
        local lines_to_fill=$(( viewport_height - list_draw_height ))
        if (( lines_to_fill > 0 )); then
            for ((i=0; i<lines_to_fill; i++)); do list_content+=$(printf '\n%s' "${T_CLEAR_LINE}"); done
        fi

        printf "%b" "$list_content"
    }
    
    _redraw_all() {
        # Double-buffering approach to eliminate flicker.
        # 1. Build the entire screen content in a single variable.
        local screen_buffer=""
        screen_buffer+=$(generate_banner_string "$banner")
        screen_buffer+=$'\n' # Add the newline the layout calculation expects
        screen_buffer+=$("$header_func")
        screen_buffer+='\n'
        screen_buffer+="${C_GRAY}${DIV}${T_RESET}\n"
        screen_buffer+=$(_draw_list)
        screen_buffer+="\n${C_GRAY}${DIV}${T_RESET}" # Moved divider from _draw_list

        local footer_content; footer_content=$("$footer_func")
        screen_buffer+="\n$footer_content"

        # 2. Move cursor to home and print the entire buffer in one go.
        # This is the key to a flicker-free update.
        printf '\033[H%b' "$screen_buffer"
    }

    # --- Initial Data Load & Draw ---
    printMsgNoNewline "${T_CURSOR_HIDE}" >/dev/tty
    _redraw_all # Draw skeleton UI. _tui_is_loading is true, so list is empty.
    #printInfoMsg "Loading..." >/dev/tty # Show loading message over it

    # Load initial data
    if [[ "$is_multi_select" == "true" ]]; then _refresh_data_multi; else _refresh_data; fi
    _tui_is_loading=false # Mark loading as complete
    viewport_height=$("$viewport_calc_func")
    _redraw_all # Redraw with actual data

    while true; do
        # If a resize was detected, force a full redraw and recalculate height.
        if [[ $_tui_resized -eq 1 ]]; then
            _tui_resized=0
            viewport_height=$("$viewport_calc_func")
            _redraw_all
        fi

        local key; key=$(read_single_char)
        local handler_result="noop" # Default to no action

        case "$key" in
            "$KEY_UP"|"k") if (( num_options > 0 )); then current_option=$(( (current_option - 1 + num_options) % num_options )); handler_result="redraw"; fi ;;
            "$KEY_DOWN"|"j") if (( num_options > 0 )); then current_option=$(( (current_option + 1) % num_options )); handler_result="redraw"; fi ;;
            "$KEY_PGUP")
                if (( num_options > 0 )); then current_option=$(( current_option - viewport_height )); if (( current_option < 0 )); then current_option=0; fi; handler_result="redraw"; fi ;;
            "$KEY_PGDN")
                if (( num_options > 0 )); then current_option=$(( current_option + viewport_height )); if (( current_option >= num_options )); then current_option=$(( num_options - 1 )); fi; handler_result="redraw"; fi ;;
            "$KEY_HOME")
                if (( num_options > 0 )); then current_option=0; handler_result="redraw"; fi ;;
            "$KEY_END")
                if (( num_options > 0 )); then current_option=$(( num_options - 1 )); handler_result="redraw"; fi ;;
            *)
                # # For other keys, we assume they might trigger a prompt that needs to draw
                # # in the footer area. We prepare the screen by moving the cursor to the
                # # start of the footer and clearing it.
                # local footer_height; footer_height=$($footer_func | wc -l)
                # local footer_start_line=$(( 2 + 1 + 1 + viewport_height + 1 + 1 )) # banner, header, div, list, div, newline
                # move_cursor_to "$footer_start_line" 1
                # clear_lines_down "$footer_height"

                "$key_handler_func" \
                    "$key" \
                    data_payloads \
                    selected_options \
                    current_option \
                    num_options \
                    handler_result \
                    "$footer_height" # Pass footer height to handler
                ;;
        esac

        if [[ "$handler_result" == "exit" ]]; then break

        elif [[ "$handler_result" == "refresh_data" ]]; then
            #_redraw_all
            clear_lines_up 1
            printInfoMsg "Refreshing..." >/dev/tty
            if [[ "$is_multi_select" == "true" ]]; then _refresh_data_multi; else _refresh_data; fi
            viewport_height=$("$viewport_calc_func") # Recalculate in case footer changed
            _redraw_all
        elif [[ "$handler_result" == "redraw" ]]; then
            _update_scroll_offset
            _redraw_all
        elif [[ "$handler_result" == "recalculate_viewport" ]]; then
            viewport_height=$("$viewport_calc_func")
            _update_scroll_offset
            _redraw_all
        fi
        #debug_show_cursor_pos
    done
}

# Restore default trap behavior when the script exits.
trap - WINCH

#endregion Interactive Menus
# (Private) A wrapper for running a menu action.
# It clears the screen, runs the function, and then prompts to continue.
run_menu_action() {
    local action_func="$1"; shift; clear_screen; printMsgNoNewline "${T_CURSOR_SHOW}" >/dev/tty
    "$action_func" "$@"; local exit_code=$?
    printMsgNoNewline "${T_CURSOR_HIDE}" >/dev/tty # Hide cursor before prompt
    # If the exit code is 2, it's a signal that the action handled its own
    # "cancellation" feedback and we should skip the prompt.
    if [[ $exit_code -ne 2 ]]; then prompt_to_continue; fi
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
        return 0
    fi
}

#region Spinners
SPINNER_OUTPUT=""
_run_with_spinner_non_interactive() {
    local desc="$1"; shift; local cmd=("$@"); printMsgNoNewline "${desc} " >&2
    if SPINNER_OUTPUT=$("${cmd[@]}" 2>&1); then printf '%s\n' "${C_L_GREEN}Done.${T_RESET}" >&2; return 0
    else local exit_code=$?; printf '%s\n' "${C_RED}Failed.${T_RESET}" >&2
        while IFS= read -r line; do printf '    %s\n' "$line"; done <<< "$SPINNER_OUTPUT" >&2; return $exit_code; fi
}

_run_with_spinner_interactive() {
    local desc="$1"; shift; local cmd=("$@"); local temp_output_file; temp_output_file=$(mktemp)
    if [[ ! -f "$temp_output_file" ]]; then printErrMsg "Failed to create temp file."; return 1; fi
    local spinner_chars="⣾⣷⣯⣟⡿⢿⣻⣽"; local i=0; "${cmd[@]}" &> "$temp_output_file" &
    local pid=$!; printMsgNoNewline "${T_CURSOR_HIDE}" >&2; trap 'printMsgNoNewline "${T_CURSOR_SHOW}" >&2; rm -f "$temp_output_file"; exit 130' INT TERM
    while ps -p $pid > /dev/null; do
        printf '\r\033[2K' >&2; local line; line=$(tail -n 1 "$temp_output_file" 2>/dev/null | tr -d '\r' || true)
        printf ' %s%s%s  %s' "${C_L_BLUE}" "${spinner_chars:$i:1}" "${T_RESET}" "${desc}" >&2
        if [[ -n "$line" ]]; then printf ' %s[%s]%s' "${C_GRAY}" "${line:0:70}" "${T_RESET}" >&2; fi
        i=$(((i + 1) % ${#spinner_chars})); sleep 0.1; done
    wait $pid; local exit_code=$?; SPINNER_OUTPUT=$(<"$temp_output_file"); rm "$temp_output_file";
    printMsgNoNewline "${T_CURSOR_SHOW}" >&2; trap - INT TERM; clear_current_line >&2
    if [[ $exit_code -eq 0 ]]; then printOkMsg "${desc}" >&2
    else printErrMsg "Task failed: ${desc}" >&2
        while IFS= read -r line; do printf '    %s\n' "$line"; done <<< "$SPINNER_OUTPUT" >&2; fi
    return $exit_code
}

run_with_spinner() {
    if [[ ! -t 1 ]]; then _run_with_spinner_non_interactive "$@"; else _run_with_spinner_interactive "$@"; fi
}

wait_for_pids_with_spinner() {
    local desc="$1"; shift; local pids_to_wait_for=("$@")
    if [[ ! -t 1 ]]; then
        printMsgNoNewline "    ${T_INFO_ICON} ${desc}... " >&2;
        if wait "${pids_to_wait_for[@]}"; then printf '%s\n' "${C_L_GREEN}Done.${T_RESET}" >&2; return 0
        else local exit_code=$?; printf '%s\n' "${C_RED}Failed (wait command exit code: $exit_code).${T_RESET}" >&2; return $exit_code; fi
    fi
    _spinner() {
        local spinner_chars="⣾⣷⣯⣟⡿⢿⣻⣽"; local i=0;
        while true; do printf '\r\033[2K' >&2; printf '    %s%s%s %s' "${C_L_BLUE}" "${spinner_chars:$i:1}" "${T_RESET}" "${desc}" >&2; i=$(((i + 1) % ${#spinner_chars})); sleep 0.1; done;
    }
    printMsgNoNewline "${T_CURSOR_HIDE}" >&2
    _spinner &
    local spinner_pid=$!
    trap 'kill "$spinner_pid" &>/dev/null; printMsgNoNewline "${T_CURSOR_SHOW}" >&2; exit 130' INT TERM
    wait "${pids_to_wait_for[@]}"; local exit_code=$?
    kill "$spinner_pid" &>/dev/null; printMsgNoNewline "${T_CURSOR_SHOW}" >&2; trap - INT TERM; clear_current_line >&2
    if [[ $exit_code -eq 0 ]]; then printOkMsg "${desc}" >&2
    else printErrMsg "Wait command failed with exit code ${exit_code} for task: ${desc}" >&2; fi
    return $exit_code
}

# The core of the interactive model management UI.
# This function provides a full-screen, list-based interface where users can
# navigate, select, and perform actions (pull, delete, update) on models.
# It encapsulates the entire interactive session.
#
# ## Usage:
#   interactive_model_manager "$models_json"
#
# ## Arguments:
#  $1 - The initial JSON string of models from the Ollama API.
#
interactive_model_manager() {
    local models_json="$1"

    # --- State Variables ---
    local -a model_names model_sizes model_dates formatted_sizes bg_colors pre_rendered_lines
    local -a selected_options=()
    local current_option=0
    local num_options=0

    # --- Helper: Parse model data ---
    # Repopulates all model-related arrays from a JSON string.
    _parse_model_data() {
        local json_data="$1"
        # Clear old data
        model_names=()
        model_sizes=()
        model_dates=()
        formatted_sizes=()
        bg_colors=()
        pre_rendered_lines=()

        # Use the existing helper to parse the data into our local arrays
        if ! _parse_model_data_for_menu "$json_data" "false" model_names model_sizes \
            model_dates formatted_sizes bg_colors pre_rendered_lines; then
            num_options=0
            return 1 # No models found
        fi

        num_options=${#model_names[@]}
        # Reset selections
        selected_options=()
        for ((i=0; i<num_options; i++)); do selected_options[i]=0; done
        # Ensure current_option is within bounds
        if (( current_option >= num_options )); then
            current_option=$(( num_options > 0 ? num_options - 1 : 0 ))
        fi
        return 0
    }

    # --- Helper: Redraw the entire screen ---
    _redraw_screen() {
        # This function now just prints the content. The caller handles clearing and cursor position.
        printBanner "Ollama Interactive Model Manager" >/dev/tty
        if [[ $num_options -eq 0 ]]; then
            printWarnMsg "No local models found." >/dev/tty
        else
            # Use the existing table renderer, but in multi-select mode to show checkboxes
            _render_model_list_table "Local Models" "multi" "$current_option" \
                model_names model_dates formatted_sizes bg_colors selected_options pre_rendered_lines
        fi

        local help_nav="  ${C_L_GRAY}Navigation:${T_RESET} ${C_L_MAGENTA}↑↓${C_WHITE} Move | ${C_L_MAGENTA}SPACE${C_WHITE} Select | ${C_L_YELLOW}(Q)uit${T_RESET}"
        local help_actions="  ${C_L_GRAY}Actions:${T_RESET}    ${C_L_GREEN}(N)ew Model${C_WHITE} | ${C_L_RED}(D)elete${C_WHITE} | ${C_MAGENTA}(U)pdate/Pull${T_RESET}"
        printMsg "${help_nav}" >/dev/tty
        printMsg "${help_actions}" >/dev/tty
        printMsg "${C_BLUE}${DIV}${T_RESET}" >/dev/tty
    }

    # --- Helper: A special version of pull_model for this UI ---
    # This function replaces the help text with a prompt, avoiding a full screen clear.
    _interactive_pull_model_inline() {
        # The help text is 3 lines tall.
        # We move the cursor up and clear from there to the end of the screen.
        move_cursor_up 3
        tput ed

        local model_name=""
        local prompt_str=" ${T_QST_ICON} Name of model to pull (e.g., llama3): "
        printMsgNoNewline "$prompt_str"

        # Show cursor for input
        tput cnorm

        local key
        local cancelled=false
        while true; do
            key=$(read_single_char </dev/tty)

            if [[ "$key" == "$KEY_ENTER" ]]; then
                break
            elif [[ "$key" == "$KEY_ESC" ]]; then
                cancelled=true
                break
            elif [[ "$key" == "$KEY_BACKSPACE" ]]; then
                if [[ -n "$model_name" ]]; then
                    # Remove last character from variable
                    model_name=${model_name%?}
                    # Move cursor left, print space, move cursor left again
                    echo -ne "\b \b"
                fi
            else
                # Append printable characters. Filter out control sequences.
                if [[ ${#key} -eq 1 ]]; then
                    model_name+="$key"
                    echo -n "$key"
                fi
            fi
        done

        # Hide cursor again for the pull process
        tput civis

        # After loop, the cursor is on the same line. Add a newline for spacing.
        echo
        printMsg "${C_BLUE}${DIV}${T_RESET}"

        # Now, clean up the prompt area before the real pull starts.
        move_cursor_up 2 # Move up past the DIV and the prompt line.
        tput ed # Clear it all.

        if [[ "$cancelled" == "true" || -z "$model_name" ]]; then
            printWarnMsg "No model name entered or pull cancelled. No action taken."
            sleep 1.5
            return 1 # Indicates no action was taken
        fi

        # Call the core pull logic. It will print its own status messages.
        # If the pull fails, pause so the user can see the error message.
        if ! _execute_pull "$model_name"; then
            prompt_to_continue
        fi
        return 0 # Indicates an action was attempted.
    }

    # --- Helper: Refresh model data from API ---
    _refresh_models() {
        local new_json
        if new_json=$(fetch_models_with_spinner "Refreshing model list..."); then
            models_json="$new_json"
            _parse_model_data "$models_json"
        else
            # On failure, pause so user can see the error from the spinner.
            prompt_to_continue
        fi
    }

    # --- Initial Setup ---
    _parse_model_data "$models_json"

    # --- Main Interactive Loop ---
    tput civis # Hide cursor
    trap 'tput cnorm; script_interrupt_handler' INT TERM

    # Helper to calculate menu height for flicker-free redrawing.
    _get_menu_height() {
        # Banner(2) + Table(N+3) + Help(3) = N+8
        # Or for no models: Banner(2) + Warn(1) + Help(3) = 6
        if (( num_options > 0 )); then
            echo $(( num_options + 8 ))
        else
            echo 6
        fi
    }

    # Initial draw
    clear
    _redraw_screen

    while true; do
        local key
        key=$(read_single_char </dev/tty)
        local state_changed=false

        case "$key" in
            "$KEY_UP"|"k")
                if (( num_options > 0 )); then
                    current_option=$(( (current_option - 1 + num_options) % num_options ))
                    state_changed=true
                fi
                ;;
            "$KEY_DOWN"|"j")
                if (( num_options > 0 )); then
                    current_option=$(( (current_option + 1) % num_options ))
                    state_changed=true
                fi
                ;;
            ' ')
                if (( num_options > 0 )); then
                    selected_options[current_option]=$(( 1 - selected_options[current_option] ))
                    state_changed=true
                fi
                ;;
            'n'|'N')
                _interactive_pull_model_inline
                _refresh_models
                clear && _redraw_screen # Redraw after action
                ;;
            'd'|'D')
                local -a to_delete=()
                for i in "${!selected_options[@]}"; do
                    if [[ ${selected_options[i]} -eq 1 ]]; then
                        to_delete+=("${model_names[i]}")
                    fi
                done
                if [[ ${#to_delete[@]} -eq 0 && $num_options -gt 0 ]]; then
                    to_delete=("${model_names[current_option]}")
                fi

                if [[ ${#to_delete[@]} -gt 0 ]]; then
                    clear # Clear screen for the confirmation prompt
                    printInfoMsg "The following models will be deleted: ${C_L_RED}${to_delete[*]}${T_RESET}"
                    if prompt_yes_no "Are you sure you want to delete these ${#to_delete[@]} models?" "n"; then
                        _perform_model_deletions "${to_delete[@]}"
                        _refresh_models
                    fi
                    clear && _redraw_screen # Redraw after action
                else
                    printWarnMsg "No models to delete." && sleep 1
                fi
                ;;            
            'u'|'U'|'p'|'P')
                local -a to_update=()
                for i in "${!selected_options[@]}"; do
                    if [[ ${selected_options[i]} -eq 1 ]]; then
                        to_update+=("${model_names[i]}")
                    fi
                done
                if [[ ${#to_update[@]} -eq 0 && $num_options -gt 0 ]]; then
                    to_update=("${model_names[current_option]}")
                fi

                if [[ ${#to_update[@]} -gt 0 ]]; then
                    clear # Clear screen for the confirmation prompt
                    _perform_model_updates "${to_update[@]}"
                    _refresh_models
                    clear && _redraw_screen # Redraw after action
                else
                    printWarnMsg "No models to update." && sleep 1
                fi
                ;;
            'q'|'Q'|"$KEY_ESC")
                clear # Clean up screen on exit
                break
                ;;
            *)
                continue # Ignore other keys, no need to redraw
                ;;
        esac
        if [[ "$state_changed" == "true" ]]; then
            move_cursor_up "$(_get_menu_height)" >/dev/tty
            _redraw_screen
        fi
    done

    # --- Cleanup ---
    tput cnorm
    trap - INT TERM
    clear
    printOkMsg "Goodbye!"
}

# Private helper to render the interactive model selection table.
# This is a pure display function that handles both single and multi-select modes.
# Usage: _render_model_list_table "Prompt" mode current_opt_idx names_ref dates_ref formatted_sizes_ref bg_colors_ref [selected_ref] pre_rendered_lines_ref
_render_model_list_table() {
    local prompt="$1"
    local mode="$2"
    local current_option="$3"
    local -n names_ref="$4"
    local -n _dates_ref="$5" # No longer used directly, but keep for arg position
    local -n _formatted_sizes_ref="$6" # No longer used directly
    local -n _bg_colors_ref="$7" # No longer used directly
    # The 'selected' array is only passed in multi-select mode.
    local -a _dummy_selected_ref=()
    local -n selected_ref="${8:-_dummy_selected_ref}" # For multi-select
    local -n pre_rendered_lines_ref="$9" # The new pre-rendered lines
    local output=""

    local with_all_option=false
    if [[ "$mode" == "multi" && "${names_ref[0]}" == "All" ]]; then
        with_all_option=true
    fi

    # --- Header ---
    # Adjust header padding based on mode
    local header_padding="%-1s"
    if [[ "$mode" == "multi" ]]; then header_padding="%-3s"; fi
    output+=$(printf " ${header_padding} %-40s %10s  %-15s" "" "NAME" "SIZE" "MODIFIED")
    output+="\n${C_BLUE}${DIV}${T_RESET}\n"

    # --- Body ---
    for i in "${!names_ref[@]}"; do
        local pointer=" "; local highlight_start=""; local highlight_end=""
        if [[ $i -eq $current_option ]]; then
            pointer="${T_BOLD}${C_L_MAGENTA}❯${T_RESET}"; highlight_start="${T_REVERSE}"; highlight_end="${T_RESET}";
        fi

        local line_prefix=""
        if [[ "$mode" == "multi" ]]; then
            local checkbox="[ ]"
            if [[ ${selected_ref[i]} -eq 1 ]]; then checkbox="${highlight_start}${C_GREEN}${T_BOLD}[✓]"; fi
            line_prefix=$(printf "%-3s " "${checkbox}")
        else
            line_prefix="  " # Two spaces for alignment with multi-select's pointer
        fi

        local line_body="${pre_rendered_lines_ref[i]}"
        output+="${pointer}${line_prefix}${highlight_start}${line_body}${highlight_end}${T_CLEAR_LINE}\n"
    done

    # --- Table Footer ---
    output+="${C_BLUE}${DIV}${T_RESET}\n"

    # Final combined print
    echo -ne "$output" >/dev/tty
}

# Private helper to process the final selections from the multi-select menu.
# Prints selected model names to stdout and returns an appropriate exit code.
# Usage: _process_multi_select_output with_all_flag names_arr_ref selected_arr_ref
_process_multi_select_output() {
    local with_all_option="$1"
    local -n names_ref="$2"
    local -n selected_ref="$3"
    local num_options=${#names_ref[@]}

    local has_selection=0
    # If "All" was an option and it was selected, output all model names.
    if [[ "$with_all_option" == "true" && ${selected_ref[0]} -eq 1 ]]; then
        for ((i=1; i<num_options; i++)); do
            echo "${names_ref[i]}"
        done
        has_selection=1
    else
        # Otherwise, iterate through the selections and output the chosen ones.
        local start_index=0
        if [[ "$with_all_option" == "true" ]]; then
            start_index=1 # Skip the "All" option itself
        fi
        for ((i=start_index; i<num_options; i++)); do
            if [[ ${selected_ref[i]} -eq 1 ]]; then
                has_selection=1
                echo "${names_ref[i]}"
            fi
        done
    fi

    if [[ $has_selection -eq 1 ]]; then return 0; else return 1; fi
}

# (Private) Generic interactive model list. Handles both single and multi-select.
# This is the new core function that consolidates the logic.
# Usage: _interactive_list_models <mode> <prompt> <models_json> [with_all_flag]
_interactive_list_models() {
    local mode="$1" # "single" or "multi"
    local prompt="$2"
    local models_json="$3"
    local with_all_option=false
    # The 'with_all' flag is only relevant for multi-select mode.
    if [[ "$mode" == "multi" && "$4" == "true" ]]; then
        with_all_option=true
    fi

    # 1. Parse model data from JSON into arrays
    local -a model_names model_sizes model_dates formatted_sizes bg_colors pre_rendered_lines
    if ! _parse_model_data_for_menu "$models_json" "$with_all_option" model_names model_sizes \
        model_dates formatted_sizes bg_colors pre_rendered_lines; then
        return 1 # No models found
    fi
    local num_options=${#model_names[@]}

    # 2. Initialize state
    local current_option=0
    local -a selected_options=()
    if [[ "$mode" == "multi" ]]; then
        for ((i=0; i<num_options; i++)); do selected_options[i]=0; done
    fi

    # --- Helper to print the footer for this menu ---
    _print_footer() {
        local help_text="  ${C_L_MAGENTA}↑↓${C_WHITE}(Move)"
        if [[ "$mode" == "multi" ]]; then
            help_text+=" | ${C_L_MAGENTA}SPACE${C_WHITE}(Select)"
        fi
        if [[ "$mode" == "multi" && "$with_all_option" == "true" ]]; then
            help_text+=" | ${C_L_GREEN}(A)ll${C_WHITE}(Toggle)"
        fi
        help_text+=" | ${C_L_MAGENTA}ENTER${C_WHITE}(Confirm) | ${C_L_YELLOW}Q/ESC${C_WHITE}(Cancel)${T_RESET}"
        
        # The table renderer already printed its bottom divider, which acts as our top divider.
        echo -e "${help_text}" >/dev/tty
        echo -e "${C_BLUE}${DIV}${T_RESET}" >/dev/tty
    }

    # 3. Set up interactive environment
    stty -echo
    printMsgNoNewline "${T_CURSOR_HIDE}" >/dev/tty
    trap 'printMsgNoNewline "${T_CURSOR_SHOW}" >/dev/tty; stty echo' EXIT

    # Calculate menu height for cursor control. It's the number of options plus the surrounding chrome.
    # Banner(1) + Header(1) + Div(1) + N lines + Div(1) + Help(1) + Div(1) = N + 6
    local menu_height=$((num_options + 7)) # Using 7 is safe for both banner types.
    printBanner "$prompt" >/dev/tty
    # The prompt argument to _render_model_list_table is now unused, but harmless to keep.
    _render_model_list_table "$prompt" "$mode" "$current_option" model_names model_dates formatted_sizes bg_colors selected_options pre_rendered_lines
    _print_footer

    # 4. Main interactive loop
    local key
    while true; do
        key=$(read_single_char </dev/tty)
        local state_changed=false

        case "$key" in
            "$KEY_UP"|"k")
                current_option=$(( (current_option - 1 + num_options) % num_options ))
                state_changed=true
                ;;
            "$KEY_DOWN"|"j")
                current_option=$(( (current_option + 1) % num_options ))
                state_changed=true
                ;;
            ' '|"h"|"l")
                if [[ "$mode" == "multi" ]]; then
                    _handle_multi_select_toggle "$with_all_option" "$current_option" "$num_options" selected_options
                    state_changed=true
                fi
                ;;
            "a"|"A")
                if [[ "$mode" == "multi" && "$with_all_option" == "true" ]]; then
                    _handle_multi_select_toggle "$with_all_option" "0" "$num_options" selected_options
                    state_changed=true
                fi
                ;;
            "$KEY_ENTER")
                break # Exit loop to process selections
                ;;
            "$KEY_ESC"|"q")
                clear_lines_up "$menu_height" >/dev/tty
                return 1
                ;;
            *)
                continue # Ignore other keys and loop without redrawing
                ;;
        esac
        if [[ "$state_changed" == "true" ]]; then
            move_cursor_up "$menu_height" >/dev/tty
            printBanner "$prompt" >/dev/tty
            _render_model_list_table "$prompt" "$mode" "$current_option" model_names model_dates formatted_sizes bg_colors selected_options pre_rendered_lines
            _print_footer
        fi
    done

    # 5. Clean up screen and process output
    clear_lines_up "$menu_height" >/dev/tty # This already uses ANSI codes

    if [[ "$mode" == "multi" ]]; then
        _process_multi_select_output "$with_all_option" model_names selected_options
        return $?
    else # single mode
        echo "${model_names[current_option]}"
        return 0
    fi
}

interactive_multi_select_list_models() {
    if ! [[ -t 0 ]]; then
        printErrMsg "Not an interactive session." >&2
        return 1
    fi

    local prompt="$1"
    local models_json="$2"
    local with_all_option=false
    [[ "$3" == "--with-all" ]] && with_all_option=true

    # Call the new consolidated function
    _interactive_list_models "multi" "$prompt" "$models_json" "$with_all_option"
}

interactive_single_select_list_models() {
    if ! [[ -t 0 ]]; then
        printErrMsg "Not an interactive session." >&2
        return 1
    fi

    local prompt="$1"
    local models_json="$2"

    # Call the new consolidated function
    _interactive_list_models "single" "$prompt" "$models_json"
}
#endregion Spinners
