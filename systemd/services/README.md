# Systemd User Services

This directory contains systemd user services for automated workflows.

## Services

1. **NAS Backup** - Automated hourly backup to NAS (office LAN only)
2. **Git Auto-Save** - Save uncommitted work to automation branches on logout

---

# NAS Backup Service

Automated hourly backup service that syncs configured paths to a NAS, but only when connected to the office LAN (not via Cloudflare VPN).

## Files

- `nas-backup.sh` - Main backup script
- `nas-backup.service` - Systemd service unit
- `nas-backup.timer` - Systemd timer unit (runs hourly)

## Features

- Runs hourly automatically
- Only backs up when on office LAN (skips when on VPN)
- Uses rsync over SSH with compression
- Deletes files on NAS that were removed locally (--delete)
- Logs all activity to `~/nas-backup.log`
- No root/admin privileges required

## Setup

### 1. Configure the Script

Edit `nas-backup.sh` and update these variables:

```bash
OFFICE_SUBNET_PREFIX="192.168.1"  # Your office network prefix
NAS_IP="192.168.1.100"             # Your NAS IP
NAS_USER="youruser"                # Your NAS username
NAS_PATH="/volume1/backups/laptop" # Backup destination on NAS

# Add/remove paths to backup
BACKUP_PATHS=(
    "$HOME/Documents"
    "$HOME/Projects"
    "$HOME/.config"
)
```

### 2. Set Up SSH Keys

Copy your SSH key to the NAS (so backups can run without password):

```bash
ssh-copy-id youruser@192.168.1.100
```

Test the connection:

```bash
ssh youruser@192.168.1.100 exit
```

### 3. Install the Systemd Service

Create symlinks in your user systemd directory:

```bash
mkdir -p ~/.config/systemd/user
ln -sf ~/jvscripts/systemd/services/nas-backup.service ~/.config/systemd/user/
ln -sf ~/jvscripts/systemd/services/nas-backup.timer ~/.config/systemd/user/
```

### 4. Enable and Start the Timer

```bash
# Reload systemd to recognize the new service
systemctl --user daemon-reload

# Enable the timer to start on boot
systemctl --user enable nas-backup.timer

# Start the timer now
systemctl --user start nas-backup.timer
```

### 5. Enable Lingering (Optional but Recommended)

This allows your user services to run even when you're not logged in:

```bash
loginctl enable-linger $USER
```

## Usage

### Check Timer Status

```bash
# See when the next backup will run
systemctl --user status nas-backup.timer

# List all timers
systemctl --user list-timers
```

### Run Backup Manually

```bash
# Run the service immediately (bypasses timer)
systemctl --user start nas-backup.service

# Or run the script directly
~/jvscripts/systemd/services/nas-backup.sh
```

### View Logs

```bash
# View systemd journal logs
journalctl --user -u nas-backup.service -f

# View the backup log file
tail -f ~/nas-backup.log
```

### Stop/Disable the Service

```bash
# Stop the timer
systemctl --user stop nas-backup.timer

# Disable it from starting on boot
systemctl --user disable nas-backup.timer
```

## How It Works

1. **Timer triggers hourly** - The systemd timer runs the service every hour
2. **Network detection** - Script checks if:
   - Cloudflare WARP interface is NOT present
   - Current IP is on the office subnet
   - NAS is directly reachable via ping
3. **Backup execution** - If on office LAN:
   - Tests SSH connection
   - Rsyncs each configured path to NAS
   - Logs all activity
4. **Silent skip** - If on VPN or not on office network, exits silently

## Troubleshooting

### Backup not running?

```bash
# Check timer is active
systemctl --user is-active nas-backup.timer

# Check for errors
journalctl --user -u nas-backup.service --since today
```

### SSH authentication fails?

```bash
# Test SSH connection manually
ssh -v youruser@192.168.1.100

# Make sure SSH keys are set up
ssh-copy-id youruser@192.168.1.100
```

### Not detecting office network?

Edit `nas-backup.sh` and check:
- `OFFICE_SUBNET_PREFIX` matches your network
- Run `ip addr` to see your current IP addresses
- Run `ip link show` to check for VPN interfaces

### View detailed logs

```bash
# Backup script logs
cat ~/nas-backup.log

# Systemd logs with full output
journalctl --user -u nas-backup.service -n 100 --no-pager
```

## Customization

### Change backup frequency

Edit `nas-backup.timer` and modify the `OnCalendar` line:

```ini
# Every 2 hours
OnCalendar=0/2:00

# Twice daily (8am and 8pm)
OnCalendar=08,20:00

# Every 30 minutes
OnCalendar=*:0/30
```

After editing, reload systemd:

```bash
systemctl --user daemon-reload
systemctl --user restart nas-backup.timer
```

### Add/remove backup paths

Edit the `BACKUP_PATHS` array in `nas-backup.sh`:

```bash
BACKUP_PATHS=(
    "$HOME/Documents"
    "$HOME/Projects"
    "$HOME/.config"
    "$HOME/Pictures"  # Added
)
```

### Customize rsync options

Modify the `rsync` command in `nas-backup.sh`. Current options:
- `-a` - Archive mode (preserves permissions, timestamps, etc.)
- `-v` - Verbose output
- `-z` - Compress during transfer
- `--delete` - Remove files on destination that don't exist locally

Example additions:
- `--exclude='*.tmp'` - Exclude temporary files
- `--max-size=100M` - Skip files larger than 100MB
- `--dry-run` - Test without actually copying

---

# Git Auto-Save Service

Automatically saves uncommitted work to automation branches on logout. Searches configured directories for git repositories with untracked or uncommitted changes, creates dated automation branches, and pushes them to origin.

## Files

- `git-autosave.sh` - Main auto-save script
- `git-autosave.service` - Systemd service unit (runs on logout)

## Features

- Runs automatically on logout/shutdown
- Only processes repos with valid origin remotes
- Only saves repos with untracked or uncommitted changes
- Creates branches named: `$USER/automations/backup/yyyy-mm-dd_ORIGINAL_BRANCH`
- **Respects `.gitignore`** - ignored files are never committed
- **Automatically excludes**:
  - Binary files
  - Files larger than 1MB
- Commits all changes with descriptive message
- Pushes to origin and returns to original branch
- **Preserves working directory state** - untracked files remain untracked on original branch
- Logs all activity to `~/git-autosave.log`
- No root/admin privileges required
- Won't prevent logout if errors occur

## Setup

### 1. Configure the Script

Edit `git-autosave.sh` and update the search directories:

```bash
# Directories to search for git repositories
SEARCH_DIRS=(
    "$HOME/Projects"
    "$HOME/Code"
    "$HOME/work"
)
```

### 2. Ensure Git Authentication

Make sure you can push to your git remotes without password prompts. For GitHub/GitLab, use:

**SSH keys** (recommended):
```bash
# Generate key if needed
ssh-keygen -t ed25519 -C "your_email@example.com"

# Add to GitHub/GitLab via web UI
cat ~/.ssh/id_ed25519.pub
```

**Or credential helper** (HTTPS):
```bash
# For GitHub
gh auth login

# For other Git services
git config --global credential.helper store
```

### 3. Install the Systemd Service

Create symlink in your user systemd directory:

```bash
mkdir -p ~/.config/systemd/user
ln -sf ~/jvscripts/systemd/services/git-autosave.service ~/.config/systemd/user/
```

### 4. Enable the Service

```bash
# Reload systemd to recognize the new service
systemctl --user daemon-reload

# Enable the service to run on logout
systemctl --user enable git-autosave.service

# Start it now (so it's ready for next logout)
systemctl --user start git-autosave.service
```

## Usage

### Check Service Status

```bash
# See if service is active and ready
systemctl --user status git-autosave.service
```

### Test Run Manually

```bash
# Run the script directly (simulates logout)
~/jvscripts/systemd/services/git-autosave.sh

# Or stop the service (triggers ExecStop)
systemctl --user stop git-autosave.service
```

### View Logs

```bash
# View the auto-save log file
tail -f ~/git-autosave.log

# View systemd journal logs
journalctl --user -u git-autosave.service -n 50
```

### Disable the Service

```bash
# Stop and disable
systemctl --user disable --now git-autosave.service
```

## How It Works

1. **Service starts** - When you log in, the service becomes "active" (but does nothing)
2. **Logout trigger** - When you log out, systemd runs the `ExecStop` command
3. **Repository search** - Script finds all git repos in configured directories
4. **Change detection** - For each repo, checks for:
   - Valid origin remote
   - Untracked files or uncommitted changes
5. **Branch creation and backup**:
   - Stashes all changes (including untracked files)
   - Creates branch: `$USER/automations/backup/2025-01-21_main`
   - Applies stashed changes to automation branch
   - Filters out binary files and files > 1MB
   - Commits remaining changes with descriptive message
   - Pushes to origin
6. **State restoration**:
   - Returns to original branch
   - Restores working directory to pre-logout state
   - Untracked files remain untracked
   - Uncommitted changes remain uncommitted
7. **Logging** - All actions logged to `~/git-autosave.log`

## Branch Naming

Branches follow this pattern:
```
{username}/automations/backup/{date}_{original_branch}
```

Examples:
- `jvolante/automations/backup/2025-01-21_main`
- `jvolante/automations/backup/2025-01-21_feature-new-ui`
- `jvolante/automations/backup/2025-01-21_detached-abc1234` (if in detached HEAD)

If a branch already exists, a timestamp is appended:
- `jvolante/automations/backup/2025-01-21_main_143052`

## Troubleshooting

### Auto-save not running on logout?

```bash
# Check service is enabled
systemctl --user is-enabled git-autosave.service

# Check service status
systemctl --user status git-autosave.service

# Try stopping to test (triggers the script)
systemctl --user stop git-autosave.service
```

### Git push fails with authentication?

```bash
# Test pushing manually from a repo
cd ~/Projects/some-repo
git push

# Set up credential helper
git config --global credential.helper store

# Or use SSH keys (see Setup section)
```

### Script takes too long?

The service has a 5-minute timeout. If you have many large repos:

1. Reduce `SEARCH_DIRS` to only essential directories
2. Add repos with large untracked files to `.gitignore`
3. Increase timeout in `git-autosave.service`:
   ```ini
   TimeoutStopSec=600  # 10 minutes
   ```

### View what was saved

Check the log:
```bash
grep "SUCCESS: Pushed" ~/git-autosave.log
```

Or view your automation branches on GitHub:
```bash
# List all automation branches in a repo
cd ~/Projects/some-repo
git branch -r | grep "$USER/automations/backup"
```

### Will gitignored files be committed?

No. The script uses `git add -A` which automatically respects your `.gitignore` file. Files listed in `.gitignore` will never be added to the automation branch commits, even if they're untracked in your working directory.

This means:
- `node_modules/` - Won't be committed (if in .gitignore)
- `.env` files - Won't be committed (if in .gitignore)
- Build artifacts - Won't be committed (if in .gitignore)
- Temp files - Won't be committed (if in .gitignore)

### Cleanup old automation branches

After reviewing and recovering your work:

```bash
# Delete local automation branches
git branch -D jvolante/automations/backup/2025-01-21_main

# Delete from remote
git push origin --delete jvolante/automations/backup/2025-01-21_main

# Or use a script to clean up old ones
git branch -r | grep "$USER/automations/backup" | grep "2025-01" | \
  sed 's/origin\///' | xargs -I {} git push origin --delete {}
```

## Customization

### Change search directories

Edit the `SEARCH_DIRS` array in `git-autosave.sh`:

```bash
SEARCH_DIRS=(
    "$HOME/Projects"
    "$HOME/Code"
    "$HOME/work"
    "$HOME/github-repos"  # Added
)
```

### Exclude certain repositories

You can modify the script to skip certain repos. Add this after the "Check if origin remote exists" section:

```bash
# Skip certain repos
repo_name=$(basename "$repo_path")
if [[ "$repo_name" == "dotfiles" || "$repo_name" == "private" ]]; then
    log "SKIP: Excluded repository $repo_path"
    return 0
fi
```

### Change branch naming pattern

Edit the branch name format in `git-autosave.sh`:

```bash
# Original
local auto_branch="${CURRENT_USER}/automations/backup/${CURRENT_DATE}_${current_branch}"

# Examples:
# Shorter: backup/2025-01-21/main
local auto_branch="backup/${CURRENT_DATE}/${current_branch}"

# With time: jvolante/automations/backup/2025-01-21-1430/main
local auto_branch="${CURRENT_USER}/automations/backup/${CURRENT_DATE}-$(date +%H%M)/${current_branch}"
```

### Customize commit message

Edit the `commit_msg` variable in `git-autosave.sh` to change the commit message format.

### Change file size limit

By default, files larger than 1MB are excluded. To change this limit, edit the size check in `git-autosave.sh`:

```bash
# Original (1MB)
if [ "$size" -gt 1048576 ]; then

# Examples:
# 5MB
if [ "$size" -gt 5242880 ]; then

# 10MB
if [ "$size" -gt 10485760 ]; then

# 500KB
if [ "$size" -gt 512000 ]; then
```

### Include binary files

To include binary files in auto-saves, comment out the binary file check in `git-autosave.sh`:

```bash
# Check if file is binary using git's detection
# Git marks binary files with "-" in numstat output
# if git diff --cached --numstat "$file" | grep -q "^-"; then
#     log "SKIP: Binary file: $file"
#     git reset HEAD "$file" 2>/dev/null
#     ((excluded_count++))
#     continue
# fi
```
