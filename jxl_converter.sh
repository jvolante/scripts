#!/usr/bin/env bash

# Default number of parallel jobs to the number of CPU cores
DEFAULT_JOBS=$(nproc 2>/dev/null || printf 4)
MAX_JOBS=${MAX_JOBS:-$DEFAULT_JOBS}

# --- Helper Functions ---

# Function to show usage information
usage() {
    printf "Usage: %s [options] <directory1> [directory2] ... -- [cjxl_options]\n\n" "$0"
    printf "Recursively finds and converts images to JXL in the specified directories.\n\n"
    printf "Options:\n"
    printf "  -j, --jobs <num>   Number of parallel cjxl jobs to run. Defaults to the number of CPU cores (%s).\n" "$DEFAULT_JOBS"
    printf "  -h, --help         Show this help message.\n\n"
    printf "Arguments:\n"
    printf "  <directory1>...    One or more directories to search for images.\n"
    printf "  [cjxl_options]     All arguments after '--' are passed directly to the cjxl command.\n"
    printf "\n"
    printf "Behavior:\n"
    printf "  - Finds images (.jpg, .jpeg, .png, .gif, .apng, .webp, .bmp, .tiff, .tif, .ppm, .pfm, .pgx).\n"
    printf "  - If a .jxl file with the same name already exists, the original is deleted.\n"
    printf "  - If conversion is successful, the original file is deleted.\n"
    printf "  - If conversion fails, the original is kept and any partial .jxl file is removed.\n"
    printf "  - A list of failed conversions is printed at the end.\n"
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
        printf "[EXISTS] JXL found for '%s'. Deleting original.\n" "$image_file"
        if ! rm "$image_file"; then
            printf "[ERROR] Failed to delete original file '%s'.\n" "$image_file"
            printf "%s (failed to delete original)\n" "$image_file" >> "$failure_log"
        fi
        return
    fi

    printf "[CONVERTING] '%s' -> '%s'\n" "$image_file" "$jxl_file"

    # Attempt conversion
    if cjxl "$image_file" "$jxl_file" "${cjxl_args[@]}" 2> /dev/null; then
        printf "[SUCCESS] Converted '%s'. Deleting original.\n" "$image_file"
        if ! rm "$image_file"; then
            printf "[ERROR] Failed to delete original file '%s' after successful conversion.\n" "$image_file"
            printf "%s (failed to delete original after conversion)\n" "$image_file" >> "$failure_log"
        fi
    else
        printf "[FAILED] Conversion failed for '%s'.\n" "$image_file"
        printf "%s\n" "$image_file" >> "$failure_log"
        # Clean up the failed/partial JXL file
        rm -f "$jxl_file"
    fi
}

# --- Main Script Logic ---

# Check for cjxl dependency
if ! command -v cjxl &> /dev/null; then
    printf "Error: 'cjxl' command not found.\n"
    printf "Please install jpeg-xl from https://github.com/libjxl/libjxl\n"
    exit 1
fi

# --- Argument Parsing ---
directories=()
cjxl_options=(-q 80 -e 9)
# Separate directories from cjxl options based on '--'
while [[ $# -gt 0 ]]; do
    case "$1" in
        -j|--jobs)
            if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                MAX_JOBS="$2"
                shift 2
            else
                printf "Error: --jobs requires a numeric argument.\n" >&2
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
            printf "Unknown option: %s\n" "$1"
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
    printf "Error: No directories specified.\n"
    usage
    exit 1
fi

# Validate directories
for dir in "${directories[@]}"; do
    if [[ ! -d "$dir" ]]; then
        printf "Error: Directory '%s' not found.\n" "$dir"
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
printf "Starting conversion with up to %s parallel jobs...\n" "$MAX_JOBS"
if [[ ${#cjxl_options[@]} -gt 0 ]]; then
    printf "Passing additional arguments to cjxl: %s\n" "${cjxl_options[*]}"
fi
printf "---------------------------------\n"

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
    printf "\n---------------------------------\n"
    printf "The following conversions failed:\n"
    printf "---------------------------------\n"
    sort -u "$failure_log"
    printf "---------------------------------\n"
    # The trap will handle cleanup of the failure_log
    exit 1
else
    printf "\n---------------------------------\n"
    printf "All conversions completed successfully.\n"
    printf "---------------------------------\n"
    exit 0
fi
