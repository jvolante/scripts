#!/bin/sh
#
# A script to walk through restoring GPG keys from a backup.

set -e

printf " GPG Key Restore Script\n"
printf "==========================\n\n"

# --- Argument Parsing ---
dry_run=false
BACKUP_ARCHIVE=""

if [ "$1" = "--dry-run" ]; then
  dry_run=true
  printf "=== Dry Run Mode Activated ===\n"
  printf "The script will display keys from the archive without importing them.\n\n"
  BACKUP_ARCHIVE="$2"
else
  BACKUP_ARCHIVE="$1"
fi
# --- End Argument Parsing ---

# Check for backup file argument
if [ -z "$BACKUP_ARCHIVE" ]; then
  if [ "$dry_run" = true ]; then
    printf "Please enter the path to the backup archive for the dry run: "
  else
    printf "Please enter the path to the backup archive (e.g., gpg_backup_....tar.gz): "
  fi
  read -r BACKUP_ARCHIVE
else
  # This case is for when the path is passed as the first arg without the flag
  # or as the second arg with the flag.
  :
fi


if [ ! -f "$BACKUP_ARCHIVE" ]; then
  printf "Error: Backup file not found at '%s'\n" "$BACKUP_ARCHIVE"
  exit 1
fi

# Create a temporary directory for extraction. mktemp is not in POSIX, but is
# the only secure way. We avoid non-portable flags like -t.
RESTORE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/gpg-restore.XXXXXX")
printf "Extracting backup archive to temporary directory: %s\n" "$RESTORE_DIR"

# To avoid non-POSIX tar flags, use a subshell to change directory for extraction.
# We also ensure we have an absolute path to the archive.
case "$BACKUP_ARCHIVE" in
  /*) abs_archive_path="$BACKUP_ARCHIVE" ;;
  *) abs_archive_path="$(pwd)/$BACKUP_ARCHIVE" ;;
esac

(cd "$RESTORE_DIR" && tar -xzf "$abs_archive_path")

# The archive contains a single directory; find its name.
SUBDIR=$(ls "$RESTORE_DIR")

# Define file paths
PUBLIC_KEYS_FILE="${RESTORE_DIR}/${SUBDIR}/public-keys.asc"
PRIVATE_KEYS_FILE="${RESTORE_DIR}/${SUBDIR}/private-keys.asc"
TRUSTDB_FILE="${RESTORE_DIR}/${SUBDIR}/trustdb.txt"

if [ ! -f "$PUBLIC_KEYS_FILE" ] || [ ! -f "$PRIVATE_KEYS_FILE" ] || [ ! -f "$TRUSTDB_FILE" ]; then
    printf "Error: One or more required files not found in the archive.\n"
    rm -r "$RESTORE_DIR"
    exit 1
fi

if [ "$dry_run" = true ]; then
  printf "\n=== Dry Run Results ===\n"
  printf "The following PUBLIC keys would be imported:\n"
  gpg --show-keys "${PUBLIC_KEYS_FILE}"
  printf "\nThe following PRIVATE keys would be imported:\n"
  gpg --show-keys "${PRIVATE_KEYS_FILE}"
  printf "\nThe owner trust database would also be imported.\n"
  printf "=== End of Dry Run ===\n"
else
  printf "\nBackup extracted. Press Enter to begin importing the keys... "
  read -r _

  # Import keys and trust database
  printf "\nImporting public keys...\n"
  gpg --import "${PUBLIC_KEYS_FILE}"

  printf "\nImporting private keys...\n"
  printf "You may be prompted to enter the passphrase for each key.\n"
  gpg --import "${PRIVATE_KEYS_FILE}"

  printf "\nImporting owner trust database...\n"
  gpg --import-ownertrust "${TRUSTDB_FILE}"
fi


# Clean up
rm -r "$RESTORE_DIR"

if [ "$dry_run" = false ]; then
  printf "\n====================================================================\n"
  printf " Restore Complete!\n"
  printf "\n"
  printf "You can verify the imported keys by running:\n"
  printf "  gpg --list-keys\n"
  printf "  gpg --list-secret-keys\n"
  printf "====================================================================\n"
fi
