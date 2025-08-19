#!/bin/bash

# Checks the status of both the Ollama service and the OpenWebUI containers.

# Source common utilities for colors and functions
# shellcheck source=./shared.sh
if ! source "$(dirname "$0")/shared.sh"; then
    echo "Error: Could not source shared.sh. Make sure it's in the same directory." >&2
    exit 1
fi

# shellcheck source=./ollama-helpers.sh
if ! source "$(dirname "$0")/ollama-helpers.sh"; then
    echo "Error: Could not source ollama-helpers.sh. Make sure it's in the same directory." >&2
    exit 1
fi

show_help() {
    printBanner "Ollama & OpenWebUI Status Checker"
    printMsg "Checks the status of the Ollama service and OpenWebUI containers."
    printMsg "It can also list installed models or watch loaded models in real-time."

    printMsg "\n${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [-m | -w | -h]"

    printMsg "\n${T_ULINE}Options:${T_RESET}"
    printMsg "  ${C_L_BLUE}-m, --models${T_RESET}   List all installed Ollama models."
    printMsg "  ${C_L_BLUE}-w, --watch${T_RESET}    Watch currently loaded models, updating every second."
    printMsg "  ${C_L_BLUE}-h, --help${T_RESET}      Shows this help message."
    printMsg "  ${C_L_BLUE}-t, --test${T_RESET}      Run internal self-tests for script logic."

    printMsg "\n${T_ULINE}Examples:${T_RESET}"
    printMsg "  ${C_GRAY}# Run the standard status check${T_RESET}"
    printMsg "  $(basename "$0")"
    printMsg "  ${C_GRAY}# List installed models${T_RESET}"
    printMsg "  $(basename "$0") --models"
    printMsg "  ${C_GRAY}# Watch loaded models in real-time${T_RESET}"
    printMsg "  $(basename "$0") --watch"
    printMsg "  ${C_GRAY}# Run internal script tests${T_RESET}"
    printMsg "  $(basename "$0") --test"
}

# Formats the raw JSON from the /api/ps endpoint into a human-readable table.
# This function is separated from the watch loop to make it testable.
# Usage: _format_ps_output <json_string>
_format_ps_output() {
    local raw_output="$1"

    # 1. First, validate that the input is valid JSON and has the .models array.
    # This prevents jq from erroring out on malformed data.
    if ! echo "$raw_output" | jq -e '.models | (type == "array")' > /dev/null 2>&1; then
        # If the JSON is invalid, we treat it as if no models are loaded.
        echo "   ${C_L_YELLOW}No models are currently loaded.${T_RESET}"
        return
    fi

    # Use jq to parse the JSON response from the /api/ps endpoint.
    # This is far more robust than parsing the CLI's text output.
    # The jq query creates a header and then TSV rows for each model.
    local tsv_output
    tsv_output=$(echo "$raw_output" | jq -r '
        # Header
        ["NAME", "SIZE", "PROCESSOR", "CONTEXT"],
        # Data rows from the .models array, sorted by name
        (.models | sort_by(.name)[] | [
            .name,
            # Convert size in bytes to a human-readable GB format, formatted to one decimal place
            ((.size / 1e9 | (. * 10 | floor) / 10 | tostring | if test("\\.") then . else . + ".0" end) + " GB"),
            # Determine processor by checking if size_vram is greater than 0
            (if .size_vram > 0 then "GPU" else "CPU" end),
            .context_length
        ])
        # Format the result as Tab-Separated Values (TSV)
        | @tsv
    ')

    # If jq produces no output or only a header, no models are loaded.
    if [[ -z "$tsv_output" || $(echo "$tsv_output" | wc -l) -lt 2 ]]; then
         echo "   ${C_L_YELLOW}No models are currently loaded.${T_RESET}"
    else
        # Format the TSV from jq into a clean, aligned table using a two-pass awk script.
        # This is more robust than `column -t` as it gives us full control over formatting.
        # The BEGIN block sets the field separator to a tab and defines padding.
        # The first block reads all data and finds the max width for each column.
        # The END block prints the formatted data, left-aligned, with padding.
        echo -e "$tsv_output" | awk 'BEGIN { FS="\t"; PADDING=4 } { for(i=1; i<=NF; i++) { if(length($i) > width[i]) { width[i] = length($i) } } data[NR] = $0 } END { for(row=1; row<=NR; row++) { split(data[row], fields, FS); for(col=1; col<=NF; col++) { printf "%-" (width[col] + PADDING) "s", fields[col] } printf "\n" } }'
    fi
}

# --- Watch Function ---
watch_ollama_ps() {
    # 1. Prerequisites
    check_ollama_installed
    check_ollama_installed --silent
    verify_ollama_api_responsive
    check_jq_installed --silent

    # 2. Setup UI
    printBanner "Watching Ollama Processes (Ctrl+C to exit)"
    tput civis # Hide cursor
    trap 'tput cnorm; script_interrupt_handler' INT TERM

    local old_output=""
    local old_lines=0
    local ollama_port=${OLLAMA_PORT:-11434}
    local ps_url="http://localhost:${ollama_port}/api/ps"

    # 3. Watch loop
    while true; do
        local new_output raw_output
        # Capture stdout and stderr from curl. Use -sS for silent mode but show errors.
        raw_output=$(curl -sS "$ps_url" 2>&1)
        local exit_code=$?

        if [[ $exit_code -ne 0 ]]; then
            # If curl fails, format it as an error.
            new_output="${T_ERR_ICON}${T_ERR} Could not connect to Ollama API at ${ps_url}${T_RESET}"
        else
            new_output=$(_format_ps_output "$raw_output")
        fi

        # Add a timestamped footer to the output
        local footer
        footer="$(getPrettyDate) ${C_WHITE}Watching for loaded models...${T_RESET}"
        local full_output="${new_output}\n${footer}"

        # Only redraw the screen if the output has actually changed
        if [[ "$full_output" != "$old_output" ]]; then
            if [[ $old_lines -gt 0 ]]; then
                clear_lines_up "$old_lines"
            fi
            printMsg "${full_output}"
            old_output="$full_output"
            old_lines=$(echo -e "${full_output}" | wc -l)
        fi

        sleep 1
    done
}

# --- Ollama Status ---
check_ollama_status() {
    printMsg "${T_BOLD}--- Ollama Status ---${T_RESET}"

    local is_systemd=false
    local service_known=false
    if _is_systemd_system; then
        is_systemd=true
        if _is_ollama_service_known; then
            service_known=true
        fi
    fi

    # 1. Check systemd service status
    if ! $is_systemd; then
        printInfoMsg "Service:  Not a systemd system. Skipping service check."
    elif ! $service_known; then
        printInfoMsg "Service:  Ollama systemd service not found."
    else
        # It is a systemd system and the service is known
        if systemctl is-active --quiet ollama.service; then
            printOkMsg "Service:  ${C_GREEN}Active${T_RESET} (via systemd)"
        else
            local state
            state=$(systemctl is-active ollama.service || true)
            printErrMsg "Service:  ${C_RED}Inactive (${state})${T_RESET} (via systemd)"
        fi
    fi

    # 2. Check API responsiveness
    local ollama_port=${OLLAMA_PORT:-11434}
    local ollama_url="http://localhost:${ollama_port}"
    if check_endpoint_status "$ollama_url" 3; then # 3-second timeout
        printOkMsg "API:      ${C_GREEN}Responsive${T_RESET} at ${C_L_BLUE}${ollama_url}${T_RESET}"
    else
        printErrMsg "API:      ${C_RED}Not Responding${T_RESET} at ${C_L_BLUE}${ollama_url}${T_RESET}"
    fi

    # 3. Check network exposure
    if ! $is_systemd; then
        printInfoMsg "Network:  Cannot determine exposure (not a systemd system)."
    elif ! $service_known; then
        printInfoMsg "Network:  Cannot determine exposure (Ollama service not found)."
    elif check_network_exposure; then
        printOkMsg "Network:  ${C_L_YELLOW}Exposed (0.0.0.0)${T_RESET}"
    else
        printOkMsg "Network:  ${C_L_BLUE}Localhost Only${T_RESET}"
    fi
}

# --- GPU Status ---
check_gpu_status() {
    # Only run if nvidia-smi is available
    if ! _check_command_exists "nvidia-smi"; then
        return
    fi

    printMsg "\n${T_BOLD}--- GPU Status (NVIDIA) ---${T_RESET}"

    # Use a timeout to prevent the script from hanging if nvidia-smi is slow
    local smi_output
        # nvidia-smi has a bug where querying driver_version and cuda_version can fail.
    # We'll get them separately for robustness.
    local driver_version cuda_version
    driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits | head -n 1)
    cuda_version=$(nvidia-smi | grep -oP 'CUDA Version: \K[^ ]+' | head -n 1)
    
    printInfoMsg "Driver:   ${C_L_BLUE}${driver_version:-N/A}${T_RESET} (CUDA: ${C_L_BLUE}${cuda_version:-N/A}${T_RESET})"

    # Use a timeout to prevent the script from hanging if nvidia-smi is slow
    local smi_output
    smi_output=$(timeout 5 nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu,temperature.gpu --format=csv,noheader,nounits)

    if [[ -z "$smi_output" ]]; then
        printErrMsg "Could not retrieve GPU information from nvidia-smi."
        return
    fi

    # The query command will output one line per GPU. We'll process each one.
    local gpu_index=0
    while IFS=',' read -r gpu_name mem_used mem_total gpu_util temp_gpu; do
        # Trim leading/trailing whitespace that might sneak in
        gpu_name=$(echo "$gpu_name" | xargs)
        mem_used=$(echo "$mem_used" | xargs)
        mem_total=$(echo "$mem_total" | xargs)
        gpu_util=$(echo "$gpu_util" | xargs)
        temp_gpu=$(echo "$temp_gpu" | xargs)

        printOkMsg "GPU ${gpu_index}:    ${C_L_CYAN}${gpu_name}${T_RESET}"
        printMsg "      - Memory: ${C_L_YELLOW}${mem_used} MiB / ${mem_total} MiB${T_RESET}"
        printMsg "      - Usage:  ${C_L_YELLOW}${gpu_util}%${T_RESET} (Temp: ${C_L_YELLOW}${temp_gpu}°C${T_RESET})"
        ((gpu_index++))
    done <<< "$smi_output"
}

# --- OpenWebUI Status ---
check_openwebui_status() {
    printMsg "\n${T_BOLD}--- OpenWebUI Status ---${T_RESET}"

    # Check for docker first
    if ! _check_command_exists "docker"; then
        printInfoMsg "Docker not found. Skipping OpenWebUI check."
        return
    fi

    local compose_cmd
    compose_cmd=$(get_docker_compose_cmd)
    if [[ -z "$compose_cmd" ]]; then
        printInfoMsg "Docker Compose not found. Skipping OpenWebUI check."
        return
    fi

    local webui_dir
    webui_dir="$(dirname "$0")/openwebui"
    if [[ ! -d "$webui_dir" ]]; then
        printErrMsg "Directory 'openwebui' not found. Cannot check status."
        return
    fi

    # 1. Check container status
    # Use --project-directory to avoid cd'ing
    if $compose_cmd --project-directory "$webui_dir" ps --filter "status=running" --services | grep -q "open-webui"; then
        printOkMsg "Container: ${C_GREEN}Running${T_RESET}"
    else
        printErrMsg "Container: ${C_RED}Not Running${T_RESET}"
    fi

    # 2. Check UI responsiveness
    local webui_port=${OPEN_WEBUI_PORT:-3000}
    local webui_url="http://localhost:${webui_port}"
    if check_endpoint_status "$webui_url" 5; then
        printOkMsg "UI:        ${C_GREEN}Responsive${T_RESET} at ${C_L_BLUE}${webui_url}${T_RESET}"
    else
        printErrMsg "UI:        ${C_RED}Not Responding${T_RESET} at ${C_L_BLUE}${webui_url}${T_RESET}"
    fi
}

# --- Test Suites ---

test_format_ps_output() {
    printTestSectionHeader "Testing _format_ps_output function:"

    # Scenario 1: Two models are loaded
    local two_models_json='{
        "models": [
            { "name": "llama3:latest", "size": 8000000000, "size_vram": 8000000000, "context_length": 8192 },
            { "name": "gemma:2b", "size": 2900000000, "size_vram": 0, "context_length": 4096 }
        ]
    }'
    # Use $'...' to interpret escape sequences like \n.
    # The awk script adds 4 spaces of padding.
    local expected_two_models_output=$'NAME             SIZE      PROCESSOR    CONTEXT    \ngemma:2b         2.9 GB    CPU          4096       \nllama3:latest    8.0 GB    GPU          8192       '
    local actual_two_models_output
    actual_two_models_output="$(_format_ps_output "$two_models_json")"
    _run_string_test "$actual_two_models_output" "$expected_two_models_output" "Formats multiple loaded models correctly"

    # Scenario 2: No models are loaded
    local no_models_json='{"models": []}'
    local expected_no_models_output="   ${C_L_YELLOW}No models are currently loaded.${T_RESET}"
    _run_string_test "$(_format_ps_output "$no_models_json")" "$expected_no_models_output" "Handles empty model list"

    # Scenario 3: Invalid JSON input
    printTestSectionHeader "--- Corner Cases ---"
    local invalid_json='this is not json'
    # The function should still produce the "no models" message because jq will fail and produce empty output.
    _run_string_test "$(_format_ps_output "$invalid_json")" "$expected_no_models_output" "Handles invalid JSON input gracefully"

    local no_models_key_json='{"data": []}'
    _run_string_test "$(_format_ps_output "$no_models_key_json")" "$expected_no_models_output" "Handles JSON without 'models' key"

    local not_an_array_json='{"models": "not an array"}'
    _run_string_test "$(_format_ps_output "$not_an_array_json")" "$expected_no_models_output" "Handles when .models is not an array"
}

test_check_ollama_status() {
    printTestSectionHeader "Testing check_ollama_status function:"

    # --- Mock dependencies ---
    # These are all the functions that check_ollama_status depends on.
    _is_systemd_system() { [[ "$MOCK_IS_SYSTEMD" == "true" ]]; }
    _is_ollama_service_known() { [[ "$MOCK_SERVICE_KNOWN" == "true" ]]; }
    systemctl() {
        if [[ "$1" == "is-active" && "$2" == "--quiet" ]]; then
            [[ "$MOCK_SERVICE_ACTIVE" == "true" ]] && return 0 || return 1
        fi
        # Return a dummy state for the non-quiet call
        echo "inactive"
    }
    check_endpoint_status() { [[ "$MOCK_API_RESPONSIVE" == "true" ]]; }
    check_network_exposure() { [[ "$MOCK_NETWORK_EXPOSED" == "true" ]]; }
    export -f _is_systemd_system _is_ollama_service_known systemctl check_endpoint_status check_network_exposure

    # --- Test Cases ---
    local actual_output
    local actual_output_no_color

    # Scenario 1: Ideal case - all systems go
    export MOCK_IS_SYSTEMD=true MOCK_SERVICE_KNOWN=true MOCK_SERVICE_ACTIVE=true MOCK_API_RESPONSIVE=true MOCK_NETWORK_EXPOSED=true
    actual_output=$(check_ollama_status)
    actual_output_no_color=$(echo "$actual_output" | sed 's/\x1b\[[0-9;]*m//g')
    _run_test "[[ \"$actual_output_no_color\" == *\"Service:  Active\"* ]]" 0 "Reports Active service"
    _run_test "[[ \"$actual_output_no_color\" == *\"API:      Responsive\"* ]]" 0 "Reports Responsive API"
    _run_test "[[ \"$actual_output_no_color\" == *\"Network:  Exposed\"* ]]" 0 "Reports Exposed network"

    # Scenario 2: Service is inactive
    export MOCK_SERVICE_ACTIVE=false
    actual_output=$(check_ollama_status)
    actual_output_no_color=$(echo "$actual_output" | sed 's/\x1b\[[0-9;]*m//g')
    _run_test "[[ \"$actual_output_no_color\" == *\"Service:  Inactive\"* ]]" 0 "Reports Inactive service"

    # Scenario 3: API is not responsive
    export MOCK_SERVICE_ACTIVE=true MOCK_API_RESPONSIVE=false
    actual_output=$(check_ollama_status)
    actual_output_no_color=$(echo "$actual_output" | sed 's/\x1b\[[0-9;]*m//g')
    _run_test "[[ \"$actual_output_no_color\" == *\"API:      Not Responding\"* ]]" 0 "Reports unresponsive API"

    # Scenario 4: Network is restricted
    export MOCK_API_RESPONSIVE=true MOCK_NETWORK_EXPOSED=false
    actual_output=$(check_ollama_status)
    actual_output_no_color=$(echo "$actual_output" | sed 's/\x1b\[[0-9;]*m//g')
    _run_test "[[ \"$actual_output_no_color\" == *\"Network:  Localhost Only\"* ]]" 0 "Reports restricted network"

    # Scenario 5: Not a systemd system
    export MOCK_IS_SYSTEMD=false
    actual_output=$(check_ollama_status)
    _run_test "[[ \"$actual_output\" == *\"Not a systemd system\"* ]]" 0 "Handles non-systemd systems"

    # Scenario 6: Service not found on a systemd system
    export MOCK_IS_SYSTEMD=true MOCK_SERVICE_KNOWN=false
    actual_output=$(check_ollama_status)
    _run_test "[[ \"$actual_output\" == *\"Ollama systemd service not found\"* ]]" 0 "Handles missing service file"
}

test_check_gpu_status() {
    printTestSectionHeader "Testing check_gpu_status function:"

    # --- Mock dependencies ---
    command() {
        if [[ "$1" == "-v" && "$2" == "nvidia-smi" ]]; then
            [[ "$MOCK_NVIDIA_SMI_EXISTS" == "true" ]] && return 0 || return 1
        else
            # Allow other command checks to pass through
            /usr/bin/command "$@"
        fi
    }
    nvidia-smi() {
        case "$*" in
            *"--query-gpu=driver_version"*) 
                echo "$MOCK_DRIVER_VERSION"
                ;;
            *"--query-gpu=name,memory.used"*) 
                echo "$MOCK_GPU_DATA"
                ;;
            *) # This is the plain `nvidia-smi` call for CUDA version
                echo "CUDA Version: $MOCK_CUDA_VERSION"
                ;;
        esac
    }
    timeout() {
        # Mock timeout to just run the command. We simulate a timeout by
        # having the mock nvidia-smi return empty output.
        shift # remove timeout duration
        "$@"
    }
    export -f command nvidia-smi timeout

    # --- Test Cases ---
    local actual_output
    local actual_output_no_color

    # Scenario 1: nvidia-smi is not installed.
    export MOCK_NVIDIA_SMI_EXISTS=false
    _run_string_test "$(check_gpu_status)" "" "Does nothing if nvidia-smi is not found"

    # Scenario 2: nvidia-smi is installed and returns valid data.
    export MOCK_NVIDIA_SMI_EXISTS=true
    export MOCK_DRIVER_VERSION="550.78" MOCK_CUDA_VERSION="12.4"
    export MOCK_GPU_DATA="NVIDIA GeForce RTX 4090, 2048, 24564, 10, 50"
    actual_output=$(check_gpu_status)
    actual_output_no_color=$(echo "$actual_output" | sed 's/\x1b\[[0-9;]*m//g')
    _run_test "[[ \"$actual_output_no_color\" == *\"Driver:   550.78 (CUDA: 12.4)\"* ]]" 0 "Reports correct driver and CUDA versions"
    _run_test "[[ \"$actual_output_no_color\" == *\"GPU 0:    NVIDIA GeForce RTX 4090\"* ]]" 0 "Reports correct GPU name"

    # Scenario 3: nvidia-smi returns empty data for the main query.
    export MOCK_GPU_DATA=""
    _run_test '[[ "$(check_gpu_status)" == *"Could not retrieve GPU information"* ]]' 0 "Handles nvidia-smi failure gracefully"
}

test_check_openwebui_status() {
    printTestSectionHeader "Testing check_openwebui_status function:"

    # --- Mock dependencies ---
    command() {
        if [[ "$1" == "-v" && "$2" == "docker" ]]; then
            [[ "$MOCK_DOCKER_EXISTS" == "true" ]] && return 0 || return 1
        else
            # Allow other command checks to pass through
            /usr/bin/command "$@"
        fi
    }
    get_docker_compose_cmd() {
        if [[ "$MOCK_COMPOSE_EXISTS" == "true" ]]; then
            echo "mock_compose_cmd"
        else
            echo ""
        fi
    }
    mock_compose_cmd() {
        # We only care about the 'ps' subcommand for this test
        if [[ "$3" == "ps" ]]; then
            echo "$MOCK_COMPOSE_PS_OUTPUT"
        fi
    }
    # This mock is already used by test_check_ollama_status, but we redefine it here
    # to control it for our specific scenarios.
    check_endpoint_status() { [[ "$MOCK_WEBUI_RESPONSIVE" == "true" ]]; }
    export -f command get_docker_compose_cmd mock_compose_cmd check_endpoint_status

    # --- Test Cases ---
    local actual_output
    local actual_output_no_color

    # Scenario 1: All good
    export MOCK_DOCKER_EXISTS=true MOCK_COMPOSE_EXISTS=true MOCK_COMPOSE_PS_OUTPUT="open-webui" MOCK_WEBUI_RESPONSIVE=true
    actual_output=$(check_openwebui_status)
    actual_output_no_color=$(echo "$actual_output" | sed 's/\x1b\[[0-9;]*m//g')
    _run_test "[[ \"$actual_output_no_color\" == *\"Container: Running\"* ]]" 0 "Reports running container"
    _run_test "[[ \"$actual_output_no_color\" == *\"UI:        Responsive\"* ]]" 0 "Reports responsive UI"

    # Scenario 2: Docker not installed
    export MOCK_DOCKER_EXISTS=false
    actual_output=$(check_openwebui_status)
    actual_output_no_color=$(echo "$actual_output" | sed 's/\x1b\[[0-9;]*m//g')
    _run_test "[[ \"$actual_output_no_color\" == *\"Docker not found\"* ]]" 0 "Handles missing Docker"

    # Scenario 3: Container is not running
    export MOCK_DOCKER_EXISTS=true MOCK_COMPOSE_EXISTS=true MOCK_COMPOSE_PS_OUTPUT="" MOCK_WEBUI_RESPONSIVE=false
    actual_output=$(check_openwebui_status)
    actual_output_no_color=$(echo "$actual_output" | sed 's/\x1b\[[0-9;]*m//g')
    _run_test "[[ \"$actual_output_no_color\" == *\"Container: Not Running\"* ]]" 0 "Reports not running container"
    _run_test "[[ \"$actual_output_no_color\" == *\"UI:        Not Responding\"* ]]" 0 "Reports unresponsive UI when container is down"
}

# A function to run internal self-tests for the script's logic.
run_tests() {
    printBanner "Running Self-Tests for check-status.sh"
    test_count=0
    failures=0

    # --- Run Suites ---
    test_format_ps_output
    test_check_ollama_status
    test_check_gpu_status
    test_check_openwebui_status

    print_test_summary \
        _is_systemd_system _is_ollama_service_known systemctl \
        check_endpoint_status check_network_exposure \
        command nvidia-smi timeout \
        get_docker_compose_cmd mock_compose_cmd
}

main() {
    load_project_env "$(dirname "$0")/.env"

    if [[ -n "$1" ]]; then
        case "$1" in
            -m|--models) display_installed_models; exit 0;; 
            -w|--watch)  watch_ollama_ps; exit 0;; 
            -h|--help)   show_help; exit 0;; 
            -t|--test)   run_tests; exit 0;; 
            *)
                show_help
                printErrMsg "Invalid option: $1"
                exit 1
                ;; 
        esac
    fi

    printBanner "Ollama & OpenWebUI Status"
    check_ollama_status
    check_gpu_status
    check_openwebui_status
    printMsg "" # Final newline
}

main "$@"
