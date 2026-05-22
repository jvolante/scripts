# shellinit:contexts=any

# Function to parse a flake file and print entries in the format:
# "Original flake URL#Flake attribute"
list-profile-install-targets() {
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

check-flake-input-version() {
  jq ".nodes.\"$1\".locked.rev" flake.lock
}

