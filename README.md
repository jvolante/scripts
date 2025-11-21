# jvscripts

Personal collection of utility scripts and systemd user services for Linux.

## Contents

- [Systemd Services](#systemd-services) - Automated background services
- [Shell Scripts](#shell-scripts) - Command-line utilities
- [Bash Configuration](#bash-configuration) - Shell environment setup

---

## Systemd Services

User-level systemd services for automated workflows. No root/admin privileges required.

Located in: `systemd/services/`

### NAS Backup Service

Automated hourly backup to NAS (office LAN only, skips VPN).

**Features:**
- Runs every hour automatically
- Only backs up when on office LAN (detects Cloudflare VPN)
- Uses rsync over SSH with compression
- Logs all activity

**Quick Start:**
```bash
# Configure settings
nano systemd/services/nas-backup.sh

# Install and enable
mkdir -p ~/.config/systemd/user
ln -sf ~/jvscripts/systemd/services/nas-backup.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now nas-backup.timer
```

[Full documentation →](systemd/services/README.md#nas-backup-service)

### Git Auto-Save Service

Automatically saves uncommitted work to backup branches on logout.

**Features:**
- Runs on logout/shutdown
- Creates dated branches: `$USER/automations/backup/YYYY-MM-DD_BRANCH`
- Respects `.gitignore`
- Excludes binary files and files > 1MB
- Preserves working directory state (untracked files stay untracked)

**Quick Start:**
```bash
# Configure search directories
nano systemd/services/git-autosave.sh

# Install and enable
mkdir -p ~/.config/systemd/user
ln -sf ~/jvscripts/systemd/services/git-autosave.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now git-autosave.service
```

[Full documentation →](systemd/services/README.md#git-auto-save-service)

---

## Shell Scripts

### omnimv

Intelligent move command that automatically uses `git mv` for tracked files, regular `mv` otherwise.

**Usage:**
```bash
# Add to PATH or create alias
alias mv="~/jvscripts/omnimv"

# Works like regular mv, but git-aware
mv tracked-file.txt new-location/
mv untracked-file.txt another-location/
```

**Features:**
- Detects git repositories automatically
- Uses `git mv` for tracked files (preserves history)
- Uses regular `mv` for untracked files
- Supports all standard mv flags
- Drop-in replacement for mv

### plantpreview

Watch PlantUML files and display live terminal previews using `timg`.

**Usage:**
```bash
# Watch current directory
~/jvscripts/plantpreview

# Watch specific directory
~/jvscripts/plantpreview ~/diagrams/
```

**Features:**
- Watches for `.puml` file changes
- Automatically renders to PNG
- Displays in terminal using timg
- Shows all existing diagrams on startup

**Dependencies:**
- `inotifywait` (inotify-tools)
- `plantuml`
- `timg`

### list_cpp_includes.sh

List all unique `#include` statements from C++ source files in directories.

**Usage:**
```bash
# List all includes
~/jvscripts/list_cpp_includes.sh src/ include/

# Global includes only (<...>)
~/jvscripts/list_cpp_includes.sh -g src/

# Local includes only ("...")
~/jvscripts/list_cpp_includes.sh -l src/

# Filter out STL headers
~/jvscripts/list_cpp_includes.sh --no-stl src/

# Headers only (from .h/.hpp files)
~/jvscripts/list_cpp_includes.sh -H src/
```

**Features:**
- Scans `.cpp`, `.hpp`, `.h`, `.cc`, `.cxx` files
- Separates global and local includes
- Can filter out STL headers
- Useful for dependency analysis

---

## Bash Configuration

### mybashrc.sh

Personal bash configuration with useful aliases and settings.

**Usage:**
```bash
# Source in your ~/.bashrc
echo "source ~/jvscripts/mybashrc.sh" >> ~/.bashrc
```

**Features:**

**History:**
- Extended history (20,000 lines)
- Immediate history append
- No duplicate lines

**Aliases:**
- `ll`, `la`, `l` - ls variants
- `make` - Parallel make with `nproc` jobs
- `bush` - Tree view of files (using rg and tree)
- `mv` - Aliased to omnimv
- `e` - Opens `$EDITOR`
- `alert` - Desktop notifications for long commands

**Shell options:**
- `globstar` - `**` recursive glob patterns
- `histappend` - Append to history
- `checkwinsize` - Auto-update terminal size
- Color support for ls, grep, etc.

---

## Installation

### Clone Repository

```bash
git clone <repo-url> ~/jvscripts
```

### Make Scripts Executable

```bash
chmod +x ~/jvscripts/{omnimv,plantpreview,list_cpp_includes.sh}
chmod +x ~/jvscripts/systemd/services/*.sh
```

### Add to PATH (Optional)

```bash
echo 'export PATH="$HOME/jvscripts:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

Or create individual aliases/symlinks as needed.

---

## Requirements

### Core
- Bash 4.0+
- Linux with systemd (for services)

### Optional Dependencies
- **NAS Backup:** `rsync`, `ssh`
- **Git Auto-Save:** `git`
- **plantpreview:** `inotifywait`, `plantuml`, `timg`
- **mybashrc bush alias:** `ripgrep`, `tree`

---

## License

Personal scripts - use at your own risk.

---

## Contributing

These are personal scripts, but feel free to fork and adapt to your needs!

For issues or suggestions, open an issue or PR.
