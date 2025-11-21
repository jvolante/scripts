export PROMPT_COMMAND='history -a'

shopt -s globstar

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=20000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

alias make="make -j $(nproc)"
alias bush="rg --files | tree --fromfile"
alias mv="omnimv"
alias e="$EDITOR"

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# Function to replace pattern in text files
# Usage: replace_in_files <pattern> <replacement> <file_or_directory> [<file_or_directory2> ...]
#
# This function safely replaces all occurrences of a pattern with a replacement
# in text files only. It can operate on multiple files or directories at once,
# automatically detecting and skipping binary/non-text files.
replace_in_files() {
    local pattern="$1"      # The pattern (regex) to search for
    local replacement="$2"  # The text to replace the pattern with

    # Check if required arguments are provided
    if [ -z "$pattern" ] || [ -z "$replacement" ] || [ -z "$3" ]; then
        echo "Usage: replace_in_files <pattern> <replacement> <file_or_directory> [<file_or_directory2> ...]"
        return 1
    fi

    # Shift the first two arguments, leaving file/directory paths
    shift 2

    # Loop through each target file/directory
    for target in "$@"; do
        # Verify the target exists
        if [ ! -e "$target" ]; then
            echo "Error: '$target' does not exist"
            continue
        fi

        # Function to process a single file
        process_file() {
            local file="$1"
            # Check if the file is a text file using the 'file' command
            # This detects if file is binary or text based on content, not extension
            if file --mime-type "$file" | grep -q "text/"; then
                # -i flag makes sed edit the file in-place
                sed -i "s|$pattern|$replacement|g" "$file"
                if [ $? -ne 0 ]; then
                    echo "Error: sed command failed for $file"
                fi
            fi
        }

        if [ -f "$target" ]; then
            # For a single file
            process_file "$target"
        elif [ -d "$target" ]; then
            # For a directory - find all regular files and process them if they're text files
            # This complex pipeline safely handles filenames with spaces, newlines, and special characters
            # find "$target" -type f -print0: Outputs filenames terminated by null bytes instead of newlines
            # while IFS= read -r -d '' file:
            #   IFS=        : Prevents leading/trailing whitespace from being trimmed
            #   read -r     : Preserves backslashes in filenames, doesn't treat them as escape characters
            #   -d ''       : Sets the delimiter to the null character (what find -print0 outputs)
            #   file        : Variable to store each filename
            find "$target" -type f -print0 | while IFS= read -r -d '' file; do
                process_file "$file"
            done
        else
            echo "Error: '$target' is neither a regular file nor a directory"
            return 1
        fi
    done
}

# Function to parse a flake file and print entries in the format:
# "Original flake URL#Flake attribute"
list_profile_install_targets() {
  # Use the first argument as input file; if not given, default to standard input.
  local input="${1:-/dev/stdin}"

  # Use AWK to process the file block by block.
  awk '
    BEGIN {
      # Initialize variables to hold the attribute and URL.
      attr = "";
      url  = "";
    }
    # When an "Index:" line is encountered, it marks the start of a new block.
    /^Index:/ {
      # If both attribute and URL were captured in the previous block, print them.
      if (attr != "" && url != "")
        print url "#" attr;
      # Reset the variables for the new block.
      attr = "";
      url  = "";
    }
    # Extract the "Flake attribute:" value by removing the label.
    /Flake attribute:/ {
      sub(/^[ \t]*Flake attribute:[ \t]+/, "", $0);
      attr = $0;
    }
    # Extract the "Original flake URL:" value by removing the label.
    /Original flake URL:/ {
      sub(/^[ \t]*Original flake URL:[ \t]+/, "", $0);
      url = $0;
    }
    END {
      # Process the final block if it contains both values.
      if (attr != "" && url != "")
        print url "#" attr;
    }
  ' "$input"
}

