#!/usr/bin/env bash

# Default number of parallel jobs to the number of CPU cores
DEFAULT_JOBS=$(nproc 2>/dev/null || echo 4)
MAX_JOBS=${MAX_JOBS:-$DEFAULT_JOBS}

# --- Helper Functions ---

# Function to show usage information
usage() {
    echo "Usage: $0 [options] <directory1> [directory2] ... -- [cjxl_options]"
    echo
    echo "Recursively finds and converts images to JXL in the specified directories."
    echo
    echo "Options:"
    echo "  -j, --jobs <num>   Number of parallel cjxl jobs to run. Defaults to the number of CPU cores ($DEFAULT_JOBS)."
    echo "  -h, --help         Show this help message."
    echo
    echo "Arguments:"
    echo "  <directory1>...    One or more directories to search for images."
    echo "  [cjxl_options]     All arguments after '--' are passed directly to the cjxl command."
    echo
    echo "Behavior:"
    echo "  - Finds images (.jpg, .jpeg, .png, .gif, .apng, .webp, .bmp, .tiff, .tif, .ppm, .pfm, .pgx)."
    echo "  - If a .jxl file with the same name already exists, the original is deleted."
    echo "  - If conversion is successful, the original file is deleted."
    echo "  - If conversion fails, the original is kept and any partial .jxl file is removed."
    echo "  - A list of failed conversions is printed at the end."
}

# Function to handle the conversion of a single file
# This function is designed to be run in the background
convert_one() {
    local image_file="$1"
    local failure_log="$2"
    shift 2
    local cjxl_args=($@)
    local base_name="${image_file%.*}"
    local jxl_file="${base_name}.jxl"

    # Check if JXL file already exists
    if [[ -f "$jxl_file" ]]; then
        echo "[EXISTS] JXL found for '$image_file'. Deleting original."
        if ! rm "$image_file"; then
            echo "[ERROR] Failed to delete original file '$image_file'."
            echo "$image_file (failed to delete original)" >> "$failure_log"
        fi
        return
    fi

    echo "[CONVERTING] '$image_file' -> '$jxl_file'"

    # Attempt conversion
    if cjxl "$image_file" "$jxl_file" "${cjxl_args[@]}" 2> /dev/null; then
        echo "[SUCCESS] Converted '$image_file'. Deleting original."
        if ! rm "$image_file"; then
            echo "[ERROR] Failed to delete original file '$image_file' after successful conversion."
            echo "$image_file (failed to delete original after conversion)" >> "$failure_log"
        fi
    else
        echo "[FAILED] Conversion failed for '$image_file'."
        echo "$image_file" >> "$failure_log"
        # Clean up the failed/partial JXL file
        rm -f "$jxl_file"
    fi
}

# --- Main Script Logic ---

# Check for cjxl dependency
if ! command -v cjxl &> /dev/null; then
    echo "Error: 'cjxl' command not found."
    echo "Please install jpeg-xl from https://github.com/libjxl/libjxl"
    exit 1
fi

# --- Argument Parsing ---
directories=()
cjxl_options=()
# Separate directories from cjxl options based on '--'
while [[ $# -gt 0 ]]; do
    case "$1" in
        -j|--jobs)
            if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                MAX_JOBS="$2"
                shift 2
            else
                echo "Error: --jobs requires a numeric argument." >&2
                exit 1
            fi
            ;; 
        -h|--help)
            usage
            exit 0
            ;; 
        --)
            shift
            cjxl_options=($@)
            break
            ;; 
        -*)
            echo "Unknown option: $1"
            usage
            exit 1
            ;; 
        *)
            directories+=("$1")
            shift
            ;; 
    esac
done

if [[ ${#directories[@]} -eq 0 ]]; then
    echo "Error: No directories specified."
    usage
    exit 1
fi

# Validate directories
for dir in "${directories[@]}"; do
    if [[ ! -d "$dir" ]]; then
        echo "Error: Directory '$dir' not found."
        exit 1
    fi
done

# --- Execution ---

# Temporary file to log failures from parallel jobs
failure_log=$(mktemp)
# Ensure the log is cleaned up on script exit
trap 'rm -f "$failure_log"' EXIT

# Export the conversion function and failure log path so background shells can use it
export -f convert_one
export failure_log

# Find all relevant image files and process them
# The -print0 and read -d '' handles filenames with spaces or special characters.
echo "Starting conversion with up to $MAX_JOBS parallel jobs..."
if [[ ${#cjxl_options[@]} -gt 0 ]]; then
    echo "Passing additional arguments to cjxl: ${cjxl_options[*]}"
fi
echo "---------------------------------"

find "${directories[@]}" -type f \( \
    -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o \
    -iname "*.gif" -o -iname "*.apng" -o \
    -iname "*.bmp" -o -iname "*.tiff" -o -iname "*.tif" -o \
    -iname "*.ppm" -o -iname "*.pfm" -o -iname "*.pgx" \
\) -print0 | while IFS= read -r -d '' file; do
    # Run the conversion in the background
    convert_one "$file" "$failure_log" "${cjxl_options[@]}" &

    # Simple job management: if we've hit the max, wait for one to finish
    while [[ $(jobs -p | wc -l) -ge $MAX_JOBS ]]; do
        wait -n # Waits for the next background job to terminate
    done
done

# Wait for all remaining background jobs to complete
wait
sleep .1

# --- Report Failures ---
if [[ -s "$failure_log" ]]; then
    echo
    echo "---------------------------------"
    echo "The following conversions failed:"
    echo "---------------------------------"
    sort -u "$failure_log"
    echo "---------------------------------"
    # The trap will handle cleanup of the failure_log
    exit 1
else
    echo
    echo "---------------------------------"
    echo "All conversions completed successfully."
    echo "---------------------------------"
    exit 0
fi
