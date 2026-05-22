#!/bin/bash

# NAS Backup Script
# Backs up configured paths to NAS only when on office LAN (not via VPN)

# Configuration
OFFICE_SUBNET_PREFIX="192.168.1"  # Adjust to your office network (e.g., "10.0.0" for 10.0.0.0/24)
NAS_IP="192.168.1.100"             # Your NAS IP address
NAS_USER="youruser"                # Your username on the NAS
NAS_PATH="/volume1/backups/laptop" # Backup destination path on NAS
LOG_FILE="$HOME/nas-backup.log"

# Paths to backup (add/remove as needed)
BACKUP_PATHS=(
    "$HOME/Documents"
    "$HOME/Projects"
    "$HOME/.config"
)

# Function to log with timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
}

# Function to check if we're on office LAN (not VPN)
is_on_office_lan() {
    # 1. Check for Cloudflare WARP interface (common names)
    if ip link show 2>/dev/null | grep -qE "(warp|CloudflareWARP|WARP)"; then
        log "Cloudflare VPN detected, skipping backup"
        return 1
    fi

    # 2. Check if any of our IPs are in office subnet
    local ips=$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1')
    local on_office_network=false

    while IFS= read -r ip; do
        if [[ "$ip" == ${OFFICE_SUBNET_PREFIX}.* ]]; then
            on_office_network=true
            log "Detected office network IP: $ip"
            break
        fi
    done <<< "$ips"

    if [ "$on_office_network" = false ]; then
        log "Not on office subnet (${OFFICE_SUBNET_PREFIX}.*), skipping backup"
        return 1
    fi

    # 3. Verify NAS is directly reachable (not just routed via VPN)
    if ! ping -c 1 -W 2 "$NAS_IP" >/dev/null 2>&1; then
        log "Cannot reach NAS at $NAS_IP, skipping backup"
        return 1
    fi

    log "On office LAN, proceeding with backup"
    return 0
}

# Main backup function
perform_backup() {
    log "=== Starting backup process ==="

    # Test SSH connectivity
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$NAS_USER@$NAS_IP" exit 2>/dev/null; then
        log "ERROR: SSH connection to $NAS_USER@$NAS_IP failed"
        log "Make sure SSH keys are set up: ssh-copy-id $NAS_USER@$NAS_IP"
        return 1
    fi

    log "SSH connection successful"

    # Rsync each configured path
    local success_count=0
    local fail_count=0

    for path in "${BACKUP_PATHS[@]}"; do
        if [ ! -e "$path" ]; then
            log "WARNING: Path does not exist: $path (skipping)"
            continue
        fi

        log "Backing up: $path"

        # Use rsync with archive mode, compression, and deletion of removed files
        if rsync -avz --delete "$path" "$NAS_USER@$NAS_IP:$NAS_PATH/" >> "$LOG_FILE" 2>&1; then
            ((success_count++))
            log "Successfully backed up: $path"
        else
            ((fail_count++))
            log "ERROR: Failed to backup: $path"
        fi
    done

    log "=== Backup completed: $success_count succeeded, $fail_count failed ==="

    if [ $fail_count -gt 0 ]; then
        return 1
    fi
    return 0
}

# Main script execution
if is_on_office_lan; then
    perform_backup
    exit_code=$?
    exit $exit_code
else
    # Not on office LAN, exit silently (already logged)
    exit 0
fi
