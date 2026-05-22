# Scripts Directory

Utility scripts for various tasks.

## Available Scripts

### switch-nixpkgs-unstable-to-stable.sh

Switches Nix profile packages from `nixpkgs-unstable` flake to `nixpkgs` (stable) flake.

**Usage:**
```bash
# Dry run to see what would change
./scripts/switch-nixpkgs-unstable-to-stable.sh --dry-run

# Actually perform the switch
./scripts/switch-nixpkgs-unstable-to-stable.sh
```

**Features:**
- Scans `nix profile list` for packages using `nixpkgs-unstable`
- Shows what will be changed before making modifications
- Includes dry-run mode for safety
- Requires user confirmation before proceeding
- Provides colored output for better readability
- Reports success/failure for each package switched
