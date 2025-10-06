#!/bin/bash

# This script generates a standalone shell script from a source script
# that includes other files using a special syntax. It processes all .sh
# files in the `src` directory and places the output in the `dist` directory.
#
# Usage: ./build.sh
#
# The source script can include other files using the following syntax:
# # BUILD_INCLUDE_START: lib/shared.lib.sh
# source "lib/shared.lib.sh"
# # BUILD_INCLUDE_END: lib/shared.lib.sh
#
# The script will replace the block with the content of the included file.

set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
SOURCE_DIR="${SCRIPT_DIR}/src"

# Ensure the output directory exists
DIST_DIR="${SCRIPT_DIR}/dist"
mkdir -p "$DIST_DIR"

echo "Starting build process..."

# Find all shell scripts in the src directory
for source_script in "$SOURCE_DIR"/*.sh; do
    if [ ! -f "$source_script" ]; then continue; fi

    output_script="$DIST_DIR/$(basename "$source_script")"
    echo "Processing: $(basename "$source_script") -> $(basename "$output_script")"

    # Clear the output file before writing
    > "$output_script"

    # Process the source script
    while IFS= read -r line; do
        # Match the include directive. The path is captured in the first group.
        if [[ "$line" =~ ^[[:space:]]*#\ BUILD_INCLUDE_START:\ (.*) ]]; then
            # Extract the file path to include
            include_file_rel_path="${BASH_REMATCH[1]}"
            include_file_full_path="${SOURCE_DIR}/${include_file_rel_path}"
            end_marker="# BUILD_INCLUDE_END: ${include_file_rel_path}"

            if [ ! -f "$include_file_full_path" ]; then
                echo "Error: Included file not found: $include_file_full_path" >&2
                exit 1
            fi

            echo "$line" >> "$output_script"
            cat "$include_file_full_path" >> "$output_script"
            echo "" >> "$output_script"
            echo "$end_marker" >> "$output_script"

            while IFS= read -r skipline && [[ ! "$skipline" =~ ^[[:space:]]*${end_marker} ]]; do
                : # Skip lines until the END marker
            done
        else
            echo "$line" >> "$output_script"
        fi
    done < "$source_script"

    chmod +x "$output_script"
done

echo "Build complete. Output is in the '$DIST_DIR' directory."