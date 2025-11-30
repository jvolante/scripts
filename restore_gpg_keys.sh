#!/bin/sh
#
# A script to walk through restoring GPG keys from a backup.

set -e

echo " GPG Key Restore Script"
echo "=========================="
echo

# --- Argument Parsing ---
dry_run=false
BACKUP_ARCHIVE=""

if [ "$1" = "--dry-run" ]; then
  dry_run=true
  echo "--- Dry Run Mode Activated ---"
  echo "The script will display keys from the archive without importing them."
  echo
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
  echo "Error: Backup file not found at '${BACKUP_ARCHIVE}'"
  exit 1
fi

# Create a temporary directory for extraction. mktemp is not in POSIX, but is
# the only secure way. We avoid non-portable flags like -t.
RESTORE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/gpg-restore.XXXXXX")
echo "Extracting backup archive to temporary directory: ${RESTORE_DIR}"

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
    echo "Error: One or more required files not found in the archive."
    rm -r "$RESTORE_DIR"
    exit 1
fi

if [ "$dry_run" = true ]; then
  echo
  echo "--- Dry Run Results ---"
  echo "The following PUBLIC keys would be imported:"
  gpg --show-keys "${PUBLIC_KEYS_FILE}"
  echo
  echo "The following PRIVATE keys would be imported:"
  gpg --show-keys "${PRIVATE_KEYS_FILE}"
  echo
  echo "The owner trust database would also be imported."
  echo "--- End of Dry Run ---"
else
  echo
  printf "Backup extracted. Press Enter to begin importing the keys... "
  read -r _
  echo

  # Import keys and trust database
  echo "Importing public keys..."
  gpg --import "${PUBLIC_KEYS_FILE}"
  echo

  echo "Importing private keys..."
  echo "You may be prompted to enter the passphrase for each key."
  gpg --import "${PRIVATE_KEYS_FILE}"
  echo

  echo "Importing owner trust database..."
  gpg --import-ownertrust "${TRUSTDB_FILE}"
  echo
fi


# Clean up
rm -r "$RESTORE_DIR"

if [ "$dry_run" = false ]; then
  echo "===================================================================="
  echo " Restore Complete!"
  echo
  echo "You can verify the imported keys by running:"
  echo "  gpg --list-keys"
  echo "  gpg --list-secret-keys"
  echo "===================================================================="
fi
