#!/bin/sh
#
# A script to walk through backing up GPG keys.

set -e

printf " GPG Key Backup Script\n"
printf "=========================\n\n"
printf "This script will back up your GPG public keys, private (secret) keys,\n"
printf "and the owner trust database. The private keys will remain encrypted\n"
printf "with their current passphrase.\n\n"

# Create a timestamped directory for the backup
BACKUP_DIR="gpg_backup_$(date --utc +%Y-%m-%d_%H-%M-%S)"
ARCHIVE_NAME="${BACKUP_DIR}.tar.gz"

mkdir "$BACKUP_DIR"

# List keys for the user to see
printf "Found the following GPG public keys:\n"
gpg --list-keys --keyid-format=long
printf "\nFound the following GPG private (secret) keys:\n"
gpg --list-secret-keys --keyid-format=long

printf "\nPress Enter to continue with the backup... "
read -r _

# Export public keys
printf "Backing up public keys...\n"
gpg --export --armor > "%s/public-keys.asc" "${BACKUP_DIR}"
printf "Public keys backed up to %s/public-keys.asc\n\n" "${BACKUP_DIR}"

# Export private keys
printf "Backing up private keys (these remain encrypted)...\n"
gpg --batch --export-secret-keys --armor > "${BACKUP_DIR}/private-keys.asc"
printf "Private keys backed up to %s/private-keys.asc\n\n" "${BACKUP_DIR}"

# Export ownertrust database
printf "Backing up owner trust database...\n"
gpg --export-ownertrust > "${BACKUP_DIR}/trustdb.txt"
printf "Owner trust backed up to %s/trustdb.txt\n\n" "${BACKUP_DIR}"
printf "\n"

# Create a compressed archive
printf "Creating compressed archive...\n"
tar -czf "${ARCHIVE_NAME}" "${BACKUP_DIR}"

# Clean up the temporary directory
rm -r "${BACKUP_DIR}"

printf "====================================================================\n"
printf " Backup Complete!\n\n"
printf "Your GPG keys are backed up in the file: %s\n" "${ARCHIVE_NAME}"
printf "Store this file in a safe and secure location (e.g., an encrypted USB drive).\n"
printf "====================================================================\n"
