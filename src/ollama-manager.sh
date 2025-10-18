#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
# --- Source the shared libraries from the new lib folder ---
# shellcheck source=./lib/shared.lib.sh
if ! source "${SCRIPT_DIR}/lib/shared.lib.sh"; then
    echo "Error: Could not source shared.lib.sh. Make sure it's in the 'src/lib' directory." >&2
    exit 1
fi
# shellcheck source=./lib/ollama.lib.sh
if ! source "${SCRIPT_DIR}/lib/ollama.lib.sh"; then
    echo "Error: Could not source ollama.lib.sh. Make sure it's in the 'src/lib' directory." >&2
    exit 1
fi

show_help() {
    printBanner "Ollama Manager"
    printMsg "A unified, interactive TUI to manage all aspects of Ollama."
    printMsg "\n${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [-h]"
    printMsg "\n${T_ULINE}Commands:${T_RESET}"
    printMsg "  ${C_L_BLUE}-h, --help${T_RESET}           Show this help message."
}

# --- State Variables ---
_VIEW_MODEL_FILTER=""
_FOOTER_EXPANDED=0
_LIST_VIEW_OFFSET=0 # For scrolling

# --- UI Drawing Functions ---

_draw_header() {
    printf "    %-41s %10s   %-10s%s\n" "MODEL NAME" "SIZE" "MODIFIED" "${T_RESET}"
}

_draw_footer() {
    local footer_content=""
    local model_actions="  ${C_L_GRAY}Model Actions:${T_RESET} ${C_L_GREEN}(A)dd${T_RESET} | ${C_L_RED}(D)elete${T_RESET} | ${C_L_MAGENTA}(U)pdate${T_RESET} | ${C_L_CYAN}(R)un${T_RESET}"
    local filter_text="${_VIEW_MODEL_FILTER:-}"
    local filter_display; filter_display=$(printf "%-32s" "${filter_text}")
    local filter_line="  ${C_L_YELLOW}(F)ilter/C(l)ear:${T_RESET} ${C_L_CYAN}${filter_display}${T_RESET}"

    if [[ $_FOOTER_EXPANDED -eq 0 ]]; then
        model_actions+=" │ ${C_L_YELLOW}?${T_RESET} more options"
        filter_line+=" │ ${C_L_YELLOW}Q/ESC${T_RESET} (Q)uit${T_CLEAR_LINE}"
        footer_content="${model_actions}${T_CLEAR_LINE}\n${filter_line}"
    else
        model_actions+=" │ ${C_L_YELLOW}?${T_RESET} fewer options"
        filter_line+=" │ ${C_L_YELLOW}Q/ESC${T_RESET} (Q)uit${T_CLEAR_LINE}"
        local manage_actions="  ${C_L_GRAY}Ollama Manage:${T_RESET} ${C_L_BLUE}(C)onfig${T_RESET} | ${C_L_YELLOW}(S)top${T_RESET} | R(${C_L_YELLOW}e${T_RESET})start | ${C_L_GREEN}(I)nstall${T_RESET}${T_CLEAR_LINE}"
        local nav_actions="  ${C_L_GRAY}Navigation:   ${T_RESET} ${C_L_MAGENTA}↓/j${T_RESET} Move Down | ${C_L_MAGENTA}↑/k${T_RESET} Move Up | ${C_L_MAGENTA}SPACE${T_RESET} Select${T_CLEAR_LINE}"
        footer_content="${model_actions}${T_CLEAR_LINE}\n${filter_line}\n${manage_actions}\n${nav_actions}"
    fi

    printf '%b' "${footer_content}"
}

_refresh_model_data() {
    local -n out_menu_options="$1"
    local -n out_data_payloads="$2"
    local -n out_selected_options="$3"

    local models_json=""
    if ! models_json=$(get_ollama_models_json); then
        out_menu_options=("${T_ERR}Could not fetch models from Ollama API.${T_RESET}")
        out_data_payloads=("")
        return
    fi

    # Parse models into arrays. Sorting is done by jq.
    local -a names sizes dates formatted_sizes bg_colors pre_rendered_lines
    if ! _parse_model_data_for_menu_optimized "$models_json" "true" names sizes dates formatted_sizes bg_colors pre_rendered_lines; then
        out_menu_options=()
        out_data_payloads=("")
        return
    fi

    # Apply filter if it exists
    if [[ -n "$_VIEW_MODEL_FILTER" ]]; then
        local -a filtered_names=() filtered_payloads=() filtered_prerendered=()
        # Always keep "All"
        filtered_names+=("${names[0]}")
        filtered_payloads+=("${names[0]}")
        filtered_prerendered+=("${pre_rendered_lines[0]}")

        for i in "${!names[@]}"; do
            if (( i == 0 )); then continue; fi # Skip "All"
            if [[ "${names[i]}" == *"${_VIEW_MODEL_FILTER}"* ]]; then
                filtered_names+=("${names[i]}")
                filtered_payloads+=("${names[i]}")
                filtered_prerendered+=("${pre_rendered_lines[i]}")
            fi
        done
        names=("${filtered_names[@]}")
        pre_rendered_lines=("${filtered_prerendered[@]}")
    fi

    # Populate output arrays
    out_menu_options=()
    out_data_payloads=()
    out_selected_options=()
    for i in "${!names[@]}"; do
        out_menu_options+=("${pre_rendered_lines[i]}")
        out_data_payloads+=("${names[i]}")
        out_selected_options+=(0)
    done
}

# --- Scrolling and Viewport Logic ---

_calculate_viewport_height() {
    local footer_height
    footer_height=$(_draw_footer | wc -l)
    local terminal_height
    terminal_height=$(tput lines)
    # Calculate total static lines:
    # 1 (banner) + 1 (header) + 1 (top divider) + 1 (bottom divider) + footer_height
    local static_lines=$(( 4 + footer_height ))
    echo $(( terminal_height - static_lines ))
}

_update_scroll_offset() {
    local current_option="$1"
    local num_options="$2"
    local viewport_height="$3"

    # Scroll down if selection moves past the bottom of the viewport
    if (( current_option >= _LIST_VIEW_OFFSET + viewport_height )); then
        _LIST_VIEW_OFFSET=$(( current_option - viewport_height + 1 ))
    fi

    # Scroll up if selection moves before the top of the viewport
    if (( current_option < _LIST_VIEW_OFFSET )); then
        _LIST_VIEW_OFFSET=$current_option
    fi

    # Don't scroll past the end of the list
    local max_offset=$(( num_options - viewport_height ))
    if (( max_offset < 0 )); then max_offset=0; fi # Handle lists smaller than viewport
    if (( _LIST_VIEW_OFFSET > max_offset )); then
        _LIST_VIEW_OFFSET=$max_offset
    fi

    # Ensure the cursor position is within the visible viewport if the list is smaller than the viewport
    if (( num_options < viewport_height )); then
        _LIST_VIEW_OFFSET=0
    fi
}

# --- Action Handlers ---

_handle_key_press() {
    local key="$1"
    local -n selected_payloads_ref="$2"
    local -n selected_indices_ref="$3"
    local -n current_option_ref="$4"
    local -n num_options_ref="$5"
    local -n handler_result_ref="$6"
    local viewport_height="$7"

    local current_model="${selected_payloads_ref[$current_option_ref]}"

    case "$key" in
        'a'|'A')
            _clear_list_view_footer "$(_draw_footer | wc -l)"
            local model_to_pull
            if prompt_for_input "Name of model to pull (e.g., llama3)" model_to_pull; then
                run_menu_action _execute_pull "$model_to_pull" && handler_result_ref="refresh_data"
            else
                # On cancel, prompt_for_input handles its own feedback. Redraw the view.
                handler_result_ref="redraw"
                _LIST_VIEW_OFFSET=0 # Reset scroll on data refresh
            fi
            ;;
        'd'|'D')
            local -a models_to_delete=()
            # If "All" is selected (index 0), get all models except "All" itself.
            if [[ ${selected_indices_ref[0]} -eq 1 ]]; then
                for i in "${!selected_payloads_ref[@]}"; do
                    if (( i > 0 )); then # Skip "All" at index 0
                        models_to_delete+=("${selected_payloads_ref[i]}")
                    fi
                done
            else
                # Otherwise, get only the individually selected models.
                for i in "${!selected_indices_ref[@]}"; do
                    if [[ ${selected_indices_ref[i]} -eq 1 && "${selected_payloads_ref[i]}" != "All" ]]; then
                        models_to_delete+=("${selected_payloads_ref[i]}")
                    fi
                done
                # If still no selections, fall back to the current model.
                if [[ ${#models_to_delete[@]} -eq 0 && -n "$current_model" && "$current_model" != "All" ]]; then
                    models_to_delete=("$current_model")
                fi
            fi

            if [[ ${#models_to_delete[@]} -gt 0 ]]; then
                clear_screen
                printBanner "Delete Models"
                local question="Are you sure you want to delete ${#models_to_delete[@]} model(s):\n ${C_L_RED}${models_to_delete[*]}${T_RESET}?"
                if prompt_yes_no "$question" "n"; then
                    run_menu_action _perform_model_deletions "${models_to_delete[@]}"
                    handler_result_ref="refresh_data"
                    _LIST_VIEW_OFFSET=0 # Reset scroll on data refresh
                else
                    handler_result_ref="redraw" # Redraw with cached data
                fi
            else
                _clear_list_view_footer "$(_draw_footer | wc -l)"
                show_timed_message "${T_WARN_ICON} No models selected to delete."
                handler_result_ref="redraw"
            fi
            ;;
        'u'|'U')
            local -a models_to_update=()
            # If "All" is selected (index 0), get all models except "All" itself.
            if [[ ${selected_indices_ref[0]} -eq 1 ]]; then
                for i in "${!selected_payloads_ref[@]}"; do
                    if (( i > 0 )); then # Skip "All" at index 0
                        models_to_update+=("${selected_payloads_ref[i]}")
                    fi
                done
            else
                # Otherwise, get only the individually selected models.
                for i in "${!selected_indices_ref[@]}"; do
                    if [[ ${selected_indices_ref[i]} -eq 1 && "${selected_payloads_ref[i]}" != "All" ]]; then
                        models_to_update+=("${selected_payloads_ref[i]}")
                    fi
                done
                # If still no selections, fall back to the current model.
                if [[ ${#models_to_update[@]} -eq 0 && -n "$current_model" && "$current_model" != "All" ]]; then
                    models_to_update=("$current_model")
                fi
            fi

            if [[ ${#models_to_update[@]} -gt 0 ]]; then
                clear_screen
                printBanner "Update Models"
                local question="Are you sure you want to update ${#models_to_update[@]} model(s):\n ${C_L_MAGENTA}${models_to_update[*]}${T_RESET}?"
                if prompt_yes_no "$question" "y"; then
                    run_menu_action _perform_model_updates "${models_to_update[@]}"
                    handler_result_ref="refresh_data"
                    _LIST_VIEW_OFFSET=0 # Reset scroll on data refresh
                else
                    handler_result_ref="redraw" # Redraw with cached data
                fi
            else
                _clear_list_view_footer "$(_draw_footer | wc -l)"
                show_timed_message "${T_WARN_ICON} No models selected to update."
                handler_result_ref="redraw"
            fi
            ;;
        'r'|'R')
            if [[ "$current_model" != "All" && -n "$current_model" ]]; then
                _clear_list_view_footer "$(_draw_footer | wc -l)"
                if prompt_yes_no "Run model ${C_L_CYAN}${current_model}${T_RESET}?" "y"; then
                    clear_screen
                    printInfoMsg "Starting model: ${C_L_BLUE}${current_model}${T_RESET}"
                    printInfoMsg "Type '/bye' to exit the model chat."
                    printMsg "${C_BLUE}${DIV}${T_RESET}"
                    ollama run "$current_model" # This takes over the terminal
                    _LIST_VIEW_OFFSET=0 # Reset scroll on data refresh
                    handler_result_ref="refresh_data" # Full refresh after returning from model
                else
                    # On cancel, just tell the main loop to redraw the view.
                    handler_result_ref="redraw"
                fi
            else
                _clear_list_view_footer "$(_draw_footer | wc -l)"
                show_timed_message "${T_WARN_ICON} Cannot run 'All' models. Please select an individual model." "2"
                handler_result_ref="redraw"
            fi
            ;;
        'f'|'F')
            _clear_list_view_footer "$(_draw_footer | wc -l)"
            local new_filter
            if prompt_for_input "Filter by name" new_filter "$_VIEW_MODEL_FILTER" "true"; then
                _VIEW_MODEL_FILTER="$new_filter"
                _LIST_VIEW_OFFSET=0 # Reset scroll on data refresh
                handler_result_ref="refresh_data"
            else
                # On cancel, prompt_for_input handles its own feedback. Redraw the view.
                handler_result_ref="redraw"
            fi
            ;;
        'l'|'L')
            if [[ -n "$_VIEW_MODEL_FILTER" ]]; then
                _VIEW_MODEL_FILTER=""
                _LIST_VIEW_OFFSET=0 # Reset scroll on data refresh
                handler_result_ref="refresh_data"
            fi
            ;;
        '?'|'/')
            _FOOTER_EXPANDED=$(( 1 - _FOOTER_EXPANDED ))
            handler_result_ref="redraw"
            # Signal to the TUI that a resize-like event occurred to force a height recalculation.
            #_tui_resized=1
            ;;
        'c'|'C')
            if [[ $_FOOTER_EXPANDED -eq 1 ]]; then
                run_menu_action bash "${SCRIPT_DIR}/../config-ollama.sh"
                handler_result_ref="refresh_data"
                _LIST_VIEW_OFFSET=0 # Reset scroll on data refresh
            fi
            ;;
        's'|'S')
            if [[ $_FOOTER_EXPANDED -eq 1 ]]; then
                _clear_list_view_footer "$(_draw_footer | wc -l)"
                if prompt_yes_no "Are you sure you want to stop the Ollama service?" "n"; then
                    run_menu_action bash "${SCRIPT_DIR}/../stop-ollama.sh"
                    _LIST_VIEW_OFFSET=0 # Reset scroll on data refresh
                    handler_result_ref="refresh_data"
                else
                    # On cancel, just tell the main loop to redraw the view.
                    handler_result_ref="redraw"
                fi
            fi
            ;;
        'e'|'E')
            if [[ $_FOOTER_EXPANDED -eq 1 ]]; then
                _clear_list_view_footer "$(_draw_footer | wc -l)"
                if prompt_yes_no "Are you sure you want to restart the Ollama service?" "y"; then
                    run_menu_action bash "${SCRIPT_DIR}/../restart-ollama.sh"
                    _LIST_VIEW_OFFSET=0 # Reset scroll on data refresh
                    handler_result_ref="refresh_data"
                else
                    # On cancel, just tell the main loop to redraw the view.
                    handler_result_ref="redraw"
                fi
            fi
            ;;
        'i'|'I')
            if [[ $_FOOTER_EXPANDED -eq 1 ]]; then
                _clear_list_view_footer "$(_draw_footer | wc -l)"
                if prompt_yes_no "This will run the Ollama installer. Continue?" "y"; then
                    run_menu_action bash "${SCRIPT_DIR}/../install-ollama.sh"
                    _LIST_VIEW_OFFSET=0 # Reset scroll on data refresh
                    handler_result_ref="refresh_data"
                else
                    # On cancel, just tell the main loop to redraw the view.
                    handler_result_ref="redraw"
                fi
            fi
            ;;
        'q'|'Q'|"$KEY_ESC")
            handler_result_ref="exit"
            ;;
        ' ') # Spacebar for multi-select
            if (( num_options_ref > 0 )); then
                _handle_multi_select_toggle "true" "$current_option_ref" "$num_options_ref" selected_indices_ref
                _update_scroll_offset "$current_option_ref" "$num_options_ref" "$viewport_height"
                handler_result_ref="redraw"
            fi
            ;;
        *)
            handler_result_ref="noop" # Explicitly do nothing for unhandled keys
            ;;
    esac

    # After handling the key, update scroll position for navigation keys
    case "$key" in
        "$KEY_UP"|"k"|"$KEY_DOWN"|"j")
            if (( num_options_ref > 0 )); then
                _update_scroll_offset "$current_option_ref" "$num_options_ref" "$viewport_height"
            fi
            ;;
        "$KEY_PGUP")
            _LIST_VIEW_OFFSET=$((_LIST_VIEW_OFFSET - viewport_height))
            if (( _LIST_VIEW_OFFSET < 0 )); then _LIST_VIEW_OFFSET=0; fi
            ;;
        "$KEY_PGDN")
            _LIST_VIEW_OFFSET=$((_LIST_VIEW_OFFSET + viewport_height)); _update_scroll_offset "$current_option_ref" "$num_options_ref" "$viewport_height"
            ;;
        "$KEY_HOME")
            _LIST_VIEW_OFFSET=0
            ;;
        "$KEY_END")
            _LIST_VIEW_OFFSET=$(( num_options_ref > viewport_height ? num_options_ref - viewport_height : 0 ))
    esac
}

main() {
    case "$1" in
        -h|--help) show_help; exit 0;;
    esac

    load_project_env "${SCRIPT_DIR}/../.env"

    # --- Pre-flight checks ---
    check_ollama_installed --silent
    check_jq_installed --silent
    verify_ollama_api_responsive

    _interactive_list_view \
        "Ollama Manager" \
        _draw_header \
        _refresh_model_data \
        _handle_key_press \
        _calculate_viewport_height \
        _LIST_VIEW_OFFSET \
        _draw_footer \
        "true" # Enable multi-select

    clear_screen
    printOkMsg "Goodbye!"
}

main "$@"