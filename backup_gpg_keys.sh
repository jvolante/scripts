#!/bin/sh
#
# A script to walk through backing up GPG keys.

set -e

echo " GPG Key Backup Script"
echo "========================="
echo
echo "This script will back up your GPG public keys, private (secret) keys,"
echo "and the owner trust database. The private keys will remain encrypted"
echo "with their current passphrase."
echo

# Create a timestamped directory for the backup
BACKUP_DIR="gpg_backup_$(date +%Y-%m-%d_%H-%M-%S)"
ARCHIVE_NAME="${BACKUP_DIR}.tar.gz"

mkdir "$BACKUP_DIR"

# List keys for the user to see
echo "Found the following GPG public keys:"
gpg --list-keys --keyid-format=long
echo
echo "Found the following GPG private (secret) keys:"
gpg --list-secret-keys --keyid-format=long
echo

printf "Press Enter to continue with the backup... "
read -r _

# Export public keys
echo "Backing up public keys..."
gpg --export --armor > "${BACKUP_DIR}/public-keys.asc"
echo "Public keys backed up to ${BACKUP_DIR}/public-keys.asc"
echo

# Export private keys
echo "Backing up private keys (these remain encrypted)..."
gpg --batch --export-secret-keys --armor > "${BACKUP_DIR}/private-keys.asc"
echo "Private keys backed up to ${BACKUP_DIR}/private-keys.asc"
echo

# Export ownertrust database
echo "Backing up owner trust database..."
gpg --export-ownertrust > "${BACKUP_DIR}/trustdb.txt"
echo "Owner trust backed up to ${BACKUP_DIR}/trustdb.txt"
echo

# Create a compressed archive
echo "Creating compressed archive..."
tar -czf "${ARCHIVE_NAME}" "${BACKUP_DIR}"

# Clean up the temporary directory
rm -r "${BACKUP_DIR}"

echo "===================================================================="
echo " Backup Complete!"
echo
echo "Your GPG keys are backed up in the file: ${ARCHIVE_NAME}"
echo "Store this file in a safe and secure location (e.g., an encrypted USB drive)."
echo "===================================================================="
