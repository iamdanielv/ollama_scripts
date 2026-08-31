# src/lib/tui_constants.sh
# Centralized constants for TUI layout dimensions and styling.
# Updates to this file should be done with extreme care.

# Global Padding
export COLUMN_PADDING=2
export ROW_PADDING=1

# Screen/Container Dimensions (based on assumption of standard terminal size)
export HEADER_HEIGHT=1
export FOOTER_HEIGHT=1
export MAIN_CONTAINER_WIDTH=80
export MAIN_CONTAINER_HEIGHT=20

# Colors (Example pattern, expand as needed)
export COLOR_SUCCESS="[32m"
export COLOR_ERROR="[31m"
export COLOR_WARN="[33m"
export COLOR_RESET="[0m"