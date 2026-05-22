#!/usr/bin/env bash
# Switch nix profile packages from nixpkgs-unstable to nixpkgs
set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

DRY_RUN=false

usage() {
	printf "Usage: %s [OPTIONS]\n" "$0"
	printf "Switch nix profile packages from nixpkgs-unstable to nixpkgs\n\n"
	printf "Options:\n"
	printf "  --dry-run    Show what would be changed without making changes\n"
	printf "  -h, --help   Show this help message\n"
	exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
	case $1 in
	--dry-run)
		DRY_RUN=true
		shift
		;;
	-h | --help)
		usage
		;;
	*)
		printf "${RED}Error: Unknown option: %s${NC}\n" "$1" >&2
		usage
		;;
	esac
done

# Check if nix is available
if ! command -v nix &>/dev/null; then
	printf "${RED}Error: nix command not found${NC}\n" >&2
	exit 1
fi

# Get profile list and parse it
printf "${GREEN}Scanning nix profile for nixpkgs-unstable packages...${NC}\n\n"

declare -a indices=()
declare -a attributes=()
declare -a urls=()

current_index=""
current_attr=""
current_url=""

while IFS= read -r line; do
	# Strip ANSI color codes
	line=$(printf '%s' "$line" | sed 's/\x1b\[[0-9;]*m//g')

	if [[ $line =~ ^Index:[[:space:]]+([0-9]+) ]]; then
		# Save previous entry if it matches
		if [[ -n "$current_index" && "$current_url" == "flake:nixpkgs-unstable" ]]; then
			indices+=("$current_index")
			attributes+=("$current_attr")
			urls+=("$current_url")
		fi

		# Start new entry
		current_index="${BASH_REMATCH[1]}"
		current_attr=""
		current_url=""
	elif [[ $line =~ ^Flake\ attribute:[[:space:]]+(.+)$ ]]; then
		current_attr="${BASH_REMATCH[1]}"
	elif [[ $line =~ ^Original\ flake\ URL:[[:space:]]+(.+)$ ]]; then
		current_url="${BASH_REMATCH[1]}"
	fi
done < <(nix profile list 2>&1 | grep -v "^warning:")

# Don't forget the last entry
if [[ -n "$current_index" && "$current_url" == "flake:nixpkgs-unstable" ]]; then
	indices+=("$current_index")
	attributes+=("$current_attr")
	urls+=("$current_url")
fi

# Check if we found any packages to switch
if [[ ${#indices[@]} -eq 0 ]]; then
	printf "${YELLOW}No packages found using nixpkgs-unstable${NC}\n"
	exit 0
fi

# Display what will be changed
printf "Found %d package(s) to switch:\n\n" "${#indices[@]}"
for i in "${!indices[@]}"; do
	printf "  [%s] %s\n" "${indices[$i]}" "${attributes[$i]}"
done
printf "\n"

if [[ "$DRY_RUN" == true ]]; then
	printf "${YELLOW}DRY RUN: Would execute the following commands:${NC}\n\n"
	for i in "${!indices[@]}"; do
		package_name="${attributes[$i]#legacyPackages.*.}"
		printf "  nix profile remove %s && nix profile install 'nixpkgs#%s'\n" "${indices[$i]}" "$package_name"
	done
	exit 0
fi

# Confirm with user
printf "${YELLOW}This will remove and reinstall packages to use nixpkgs (stable) instead of nixpkgs-unstable.${NC}\n"
printf "${YELLOW}Note: This will temporarily uninstall each package before reinstalling.${NC}\n"
printf "Continue? [y/N] "
read -r response

if [[ ! "$response" =~ ^[Yy]$ ]]; then
	printf "Aborted.\n"
	exit 0
fi

printf "\n"

# Perform the switches
failed_count=0
success_count=0

# Process indices in reverse order to avoid index shifting issues
for ((i = ${#indices[@]} - 1; i >= 0; i--)); do
	index="${indices[$i]}"
	attr="${attributes[$i]}"

	# Extract the package name from the attribute (remove legacyPackages.x86_64-linux. prefix)
	package_name="${attr#legacyPackages.*.}"

	printf "${GREEN}[%s/%s]${NC} Switching %s (index %s)...\n" "$((${#indices[@]} - i))" "${#indices[@]}" "$package_name" "$index"

	# Remove the old package
	if ! nix profile remove "$index" 2>&1; then
		printf "  ${RED}✗${NC} Failed to remove\n"
		failed_count=$((failed_count + 1))
		printf "\n"
		continue
	fi

	# Install from nixpkgs
	if nix profile install "nixpkgs#$package_name" 2>&1; then
		printf "  ${GREEN}✓${NC} Success\n"
		success_count=$((success_count + 1))
	else
		printf "  ${RED}✗${NC} Failed to install (package was removed!)\n"
		failed_count=$((failed_count + 1))
	fi
	printf "\n"
done

# Summary
printf "${GREEN}=== Summary ===${NC}\n"
printf "Successfully switched: %d\n" "$success_count"
if [[ $failed_count -gt 0 ]]; then
	printf "${RED}Failed: %d${NC}\n" "$failed_count"
fi
