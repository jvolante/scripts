#!/bin/bash
# Script to list unique #include paths for C++ source and header files in directories
# Usage: ./list_cpp_includes.sh [-g|--global] [-l|--local] [--no-stl] [-H|--headers-only] <dir1> [dir2] [dir3] ...

set -euo pipefail

# Default: show both global and local includes
SHOW_GLOBAL=1
SHOW_LOCAL=1
FILTER_STL=0
HEADERS_ONLY=0

# Function to get STL headers from the system at runtime
get_stl_headers() {
    local stl_headers=()

    # Try to find C++ standard library include directories
    local cpp_dirs=()

    # Method 1: Use g++ or clang++ to find system include paths
    if command -v g++ &> /dev/null; then
        while IFS= read -r line; do
            cpp_dirs+=("$line")
        done < <(echo | g++ -x c++ -E -v - 2>&1 | sed -n '/^#include <...> search starts here:/,/^End of search list./p' | grep -E '^\s+/' | sed 's/^[[:space:]]*//' | grep -E 'c\+\+|g\+\+')
    elif command -v clang++ &> /dev/null; then
        while IFS= read -r line; do
            cpp_dirs+=("$line")
        done < <(echo | clang++ -x c++ -E -v - 2>&1 | sed -n '/^#include <...> search starts here:/,/^End of search list./p' | grep -E '^\s+/' | sed 's/^[[:space:]]*//' | grep -E 'c\+\+|clang')
    fi

    # Method 2: Check common standard library locations
    for base_dir in /usr/include/c++/* /usr/local/include/c++/*; do
        if [ -d "$base_dir" ]; then
            cpp_dirs+=("$base_dir")
        fi
    done

    # Scan directories for headers (files without extensions or with common extensions)
    for dir in "${cpp_dirs[@]}"; do
        if [ -d "$dir" ]; then
            # Find files in the directory (not subdirectories) that look like headers
            while IFS= read -r file; do
                local header_name
                header_name=$(basename "$file")
                # Only include files without extensions or common C++ header patterns
                if [[ ! "$header_name" =~ \. ]] || [[ "$header_name" =~ ^c[a-z]+$ ]]; then
                    stl_headers+=("$header_name")
                fi
            done < <(find "$dir" -maxdepth 1 -type f 2>/dev/null)
        fi
    done

    # Remove duplicates and return
    printf '%s\n' "${stl_headers[@]}" | sort -u
}

# Cache STL headers list
STL_HEADERS_CACHE=""

# Function to filter out STL headers from a list of includes
filter_stl_headers() {
    local includes="$1"
    local filtered=""

    while IFS= read -r include; do
        [ -z "$include" ] && continue
        base_include=$(basename "$include")

        IS_STL=0
        if echo "$STL_HEADERS_CACHE" | grep -qFx "$base_include"; then
            IS_STL=1
        fi

        if [ $IS_STL -eq 0 ]; then
            if [ -z "$filtered" ]; then
                filtered="$include"
            else
                filtered="${filtered}"$'\n'"${include}"
            fi
        fi
    done <<< "$includes"

    echo "$filtered"
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -g|--global)
            SHOW_GLOBAL=1
            SHOW_LOCAL=0
            shift
            ;;
        -l|--local)
            SHOW_GLOBAL=0
            SHOW_LOCAL=1
            shift
            ;;
        --no-stl)
            FILTER_STL=1
            shift
            ;;
        -H|--headers-only)
            HEADERS_ONLY=1
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [-g|--global] [-l|--local] [--no-stl] [-H|--headers-only] <directory1> [directory2] [directory3] ..."
            echo ""
            echo "Lists unique #include paths for all C++ source and header files in the specified directories"
            echo ""
            echo "By default, includes are categorized into:"
            echo "  - Headers (propagated dependencies): All includes found in header files"
            echo "  - Sources only (implementation details): Includes found only in source files"
            echo ""
            echo "Options:"
            echo "  -g, --global        Show only global includes (angle brackets: <header.h>)"
            echo "  -l, --local         Show only local includes (quotes: \"header.h\")"
            echo "  --no-stl            Filter out C++ standard library headers"
            echo "  -H, --headers-only  Only show header file includes (disables categorization)"
            echo "  -h, --help          Show this help message"
            exit 0
            ;;
        -*)
            echo "Error: Unknown option '$1'"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

if [ $# -eq 0 ]; then
    echo "Usage: $0 [-g|--global] [-l|--local] [--no-stl] [-H|--headers-only] <directory1> [directory2] [directory3] ..."
    echo "Use -h or --help for more information"
    exit 1
fi

# Build STL headers cache if filtering is requested
if [ $FILTER_STL -eq 1 ]; then
    STL_HEADERS_CACHE=$(get_stl_headers)
fi

for dir in "$@"; do
    if [ ! -d "$dir" ]; then
        echo "Error: Directory '$dir' does not exist"
        continue
    fi

    # Print directory name in bold (using ANSI escape codes)
    echo -e "\033[1m${dir}\033[0m"

    if [ $HEADERS_ONLY -eq 1 ]; then
        # Original behavior: just show header includes
        RG_OPTS=(--type cpp --type c --no-heading --no-filename --only-matching)
        RG_OPTS+=(--glob '*.h' --glob '*.hpp' --glob '*.hxx' --glob '*.hh' --glob '*.H')

        RESULTS=""
        if [ $SHOW_GLOBAL -eq 1 ]; then
            GLOBAL_RESULTS=$(rg "${RG_OPTS[@]}" \
               '^[[:space:]]*#[[:space:]]*include[[:space:]]+<([^>]+)>' \
               --replace '$1' \
               "$dir" 2>/dev/null || true)
            RESULTS="$GLOBAL_RESULTS"
        fi

        if [ $SHOW_LOCAL -eq 1 ]; then
            LOCAL_RESULTS=$(rg "${RG_OPTS[@]}" \
               '^[[:space:]]*#[[:space:]]*include[[:space:]]+"([^"]+)"' \
               --replace '$1' \
               "$dir" 2>/dev/null || true)
            if [ -n "$RESULTS" ]; then
                RESULTS="${RESULTS}"$'\n'"${LOCAL_RESULTS}"
            else
                RESULTS="$LOCAL_RESULTS"
            fi
        fi

        if [ -n "$RESULTS" ]; then
            SORTED_RESULTS=$(echo "$RESULTS" | sort -u)
            if [ $FILTER_STL -eq 1 ]; then
                SORTED_RESULTS=$(filter_stl_headers "$SORTED_RESULTS")
            fi
            if [ -n "$SORTED_RESULTS" ]; then
                echo "$SORTED_RESULTS"
            else
                echo "  (no includes found)"
            fi
        else
            echo "  (no includes found)"
        fi
    else
        # New behavior: categorize by file type
        # Search headers
        HEADER_RG_OPTS=(--type cpp --type c --no-heading --no-filename --only-matching)
        HEADER_RG_OPTS+=(--glob '*.h' --glob '*.hpp' --glob '*.hxx' --glob '*.hh' --glob '*.H')

        # Search sources (exclude headers)
        SOURCE_RG_OPTS=(--type cpp --type c --no-heading --no-filename --only-matching)
        SOURCE_RG_OPTS+=(--glob '!*.h' --glob '!*.hpp' --glob '!*.hxx' --glob '!*.hh' --glob '!*.H')

        # Get includes from headers
        HEADER_INCLUDES=""
        if [ $SHOW_GLOBAL -eq 1 ]; then
            HEADER_GLOBAL=$(rg "${HEADER_RG_OPTS[@]}" \
               '^[[:space:]]*#[[:space:]]*include[[:space:]]+<([^>]+)>' \
               --replace '$1' \
               "$dir" 2>/dev/null || true)
            HEADER_INCLUDES="$HEADER_GLOBAL"
        fi
        if [ $SHOW_LOCAL -eq 1 ]; then
            HEADER_LOCAL=$(rg "${HEADER_RG_OPTS[@]}" \
               '^[[:space:]]*#[[:space:]]*include[[:space:]]+"([^"]+)"' \
               --replace '$1' \
               "$dir" 2>/dev/null || true)
            if [ -n "$HEADER_INCLUDES" ]; then
                HEADER_INCLUDES="${HEADER_INCLUDES}"$'\n'"${HEADER_LOCAL}"
            else
                HEADER_INCLUDES="$HEADER_LOCAL"
            fi
        fi
        HEADER_INCLUDES=$(echo "$HEADER_INCLUDES" | sort -u)

        # Get includes from sources
        SOURCE_INCLUDES=""
        if [ $SHOW_GLOBAL -eq 1 ]; then
            SOURCE_GLOBAL=$(rg "${SOURCE_RG_OPTS[@]}" \
               '^[[:space:]]*#[[:space:]]*include[[:space:]]+<([^>]+)>' \
               --replace '$1' \
               "$dir" 2>/dev/null || true)
            SOURCE_INCLUDES="$SOURCE_GLOBAL"
        fi
        if [ $SHOW_LOCAL -eq 1 ]; then
            SOURCE_LOCAL=$(rg "${SOURCE_RG_OPTS[@]}" \
               '^[[:space:]]*#[[:space:]]*include[[:space:]]+"([^"]+)"' \
               --replace '$1' \
               "$dir" 2>/dev/null || true)
            if [ -n "$SOURCE_INCLUDES" ]; then
                SOURCE_INCLUDES="${SOURCE_INCLUDES}"$'\n'"${SOURCE_LOCAL}"
            else
                SOURCE_INCLUDES="$SOURCE_LOCAL"
            fi
        fi
        SOURCE_INCLUDES=$(echo "$SOURCE_INCLUDES" | sort -u)

        # Categorize includes
        IN_HEADERS=""
        ONLY_IN_SOURCES=""

        # All includes found in headers (propagated dependencies)
        IN_HEADERS="$HEADER_INCLUDES"

        # Find includes only in sources (implementation-only dependencies)
        if [ -n "$SOURCE_INCLUDES" ]; then
            if [ -n "$HEADER_INCLUDES" ]; then
                ONLY_IN_SOURCES=$(comm -13 <(echo "$HEADER_INCLUDES") <(echo "$SOURCE_INCLUDES"))
            else
                ONLY_IN_SOURCES="$SOURCE_INCLUDES"
            fi
        fi

        # Filter STL if requested
        if [ $FILTER_STL -eq 1 ]; then
            if [ -n "$IN_HEADERS" ]; then
                IN_HEADERS=$(filter_stl_headers "$IN_HEADERS")
            fi
            if [ -n "$ONLY_IN_SOURCES" ]; then
                ONLY_IN_SOURCES=$(filter_stl_headers "$ONLY_IN_SOURCES")
            fi
        fi

        # Display results
        if [ -n "$IN_HEADERS" ]; then
            echo "  Headers (propagated dependencies):"
            echo "$IN_HEADERS" | sed 's/^/    /'
        fi

        if [ -n "$ONLY_IN_SOURCES" ]; then
            echo "  Sources only (implementation details):"
            echo "$ONLY_IN_SOURCES" | sed 's/^/    /'
        fi

        if [ -z "$IN_HEADERS" ] && [ -z "$ONLY_IN_SOURCES" ]; then
            echo "  (no includes found)"
        fi
    fi

    # Blank line between directories
    echo
done
