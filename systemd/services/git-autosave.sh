#!/usr/bin/env bash

# Git Auto-Save on Logout
# Searches for git repos with untracked/uncommitted changes and pushes them to automation branches

# Configuration
# Directories to search for git repositories (supports ~ expansion)
SEARCH_DIRS=(
    "$HOME/Projects"
    "$HOME/Code"
    "$HOME/work"
)

LOG_FILE="$HOME/git-autosave.log"
CURRENT_USER="${USER:-$(whoami)}"
CURRENT_DATE=$(date '+%Y-%m-%d')

# Function to log with timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
}

# Function to find all git repositories in a directory
find_git_repos() {
    local search_dir="$1"

    if [ ! -d "$search_dir" ]; then
        log "WARNING: Directory does not exist: $search_dir"
        return
    fi

    # Find all .git directories (excluding nested .git in submodules)
    find "$search_dir" -name ".git" -type d 2>/dev/null | while read -r git_dir; do
        # Get the repo root (parent of .git)
        dirname "$git_dir"
    done
}

# Function to check if repo has uncommitted or untracked changes
has_changes() {
    local repo_path="$1"

    cd "$repo_path" || return 1

    # Check for untracked files
    if [ -n "$(git ls-files --others --exclude-standard)" ]; then
        return 0
    fi

    # Check for uncommitted changes (staged or unstaged)
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        return 0
    fi

    return 1
}

# Function to process a single git repository
process_repo() {
    local repo_path="$1"

    log "Processing: $repo_path"

    cd "$repo_path" || {
        log "ERROR: Cannot access $repo_path"
        return 1
    }

    # Check if origin remote exists
    if ! git remote get-url origin &>/dev/null; then
        log "SKIP: No origin remote in $repo_path"
        return 0
    fi

    # Check for changes
    if ! has_changes "$repo_path"; then
        log "SKIP: No untracked or uncommitted changes in $repo_path"
        return 0
    fi

    # Get current branch name
    local current_branch
    current_branch=$(git symbolic-ref --short HEAD 2>/dev/null)

    if [ -z "$current_branch" ]; then
        # Detached HEAD state
        current_branch="detached-$(git rev-parse --short HEAD)"
        log "WARNING: Detached HEAD in $repo_path, using $current_branch"
    fi

    # Create automation branch name
    local auto_branch="${CURRENT_USER}/automations/backup/${CURRENT_DATE}_${current_branch}"

    log "Creating automation branch: $auto_branch"

    # Check if branch already exists locally
    if git show-ref --verify --quiet "refs/heads/$auto_branch"; then
        log "WARNING: Branch $auto_branch already exists, using timestamp suffix"
        auto_branch="${auto_branch}_$(date '+%H%M%S')"
    fi

    # Stash all changes (including untracked files) to preserve them
    log "Stashing changes..."
    if ! git stash push -u -m "git-autosave temporary stash" 2>&1 | tee -a "$LOG_FILE"; then
        log "ERROR: Failed to stash changes in $repo_path"
        return 1
    fi

    # Create and checkout new branch
    if ! git checkout -b "$auto_branch" 2>&1 | tee -a "$LOG_FILE"; then
        log "ERROR: Failed to create branch $auto_branch in $repo_path"
        # Restore stashed changes before failing
        git stash pop 2>/dev/null
        return 1
    fi

    # Apply stashed changes to automation branch
    if ! git stash pop 2>&1 | tee -a "$LOG_FILE"; then
        log "ERROR: Failed to apply stashed changes in $repo_path"
        git checkout "$current_branch" 2>/dev/null
        git branch -d "$auto_branch" 2>/dev/null
        return 1
    fi

    # Add all changes (tracked, modified, and untracked)
    if ! git add -A 2>&1 | tee -a "$LOG_FILE"; then
        log "ERROR: Failed to add changes in $repo_path"
        git checkout "$current_branch" 2>/dev/null
        git branch -d "$auto_branch" 2>/dev/null
        return 1
    fi

    # Filter out binary files and files > 1MB
    log "Filtering out binary and large files..."
    local excluded_count=0
    git diff --cached --name-only | while read -r file; do
        # Skip if file doesn't exist (might be deleted)
        if [ ! -f "$file" ]; then
            continue
        fi

        # Check if file is binary using git's detection
        # Git marks binary files with "-" in numstat output
        if git diff --cached --numstat "$file" | grep -q "^-"; then
            log "SKIP: Binary file: $file"
            git reset HEAD "$file" 2>/dev/null
            ((excluded_count++))
            continue
        fi

        # Check file size (1MB = 1048576 bytes)
        local size
        size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo 0)
        if [ "$size" -gt 1048576 ]; then
            local size_mb=$(echo "scale=2; $size/1048576" | bc 2>/dev/null || echo "$(($size/1048576))")
            log "SKIP: Large file (${size_mb}MB): $file"
            git reset HEAD "$file" 2>/dev/null
            ((excluded_count++))
        fi
    done

    if [ "$excluded_count" -gt 0 ]; then
        log "Excluded $excluded_count binary/large files from commit"
    fi

    # Check if there's anything to commit after filtering
    if git diff-index --quiet --cached HEAD -- 2>/dev/null; then
        log "INFO: No changes to commit after filtering in $repo_path"
        git checkout "$current_branch" 2>/dev/null
        git branch -d "$auto_branch" 2>/dev/null
        return 0
    fi

    # Commit changes
    local commit_msg="Auto-save on logout at $(date '+%Y-%m-%d %H:%M:%S')

Branch: $current_branch
User: $CURRENT_USER
Host: $(hostname)

This is an automatic save of uncommitted work."

    if ! git commit -m "$commit_msg" 2>&1 | tee -a "$LOG_FILE"; then
        log "ERROR: Failed to commit changes in $repo_path"
        git checkout "$current_branch" 2>/dev/null
        git branch -d "$auto_branch" 2>/dev/null
        return 1
    fi

    # Push to remote
    log "Pushing $auto_branch to origin..."
    if ! git push -u origin "$auto_branch" 2>&1 | tee -a "$LOG_FILE"; then
        log "ERROR: Failed to push $auto_branch in $repo_path"
        git checkout "$current_branch" 2>/dev/null
        return 1
    fi

    log "SUCCESS: Pushed $auto_branch from $repo_path"

    # Go back to original branch
    if ! git checkout "$current_branch" 2>&1 | tee -a "$LOG_FILE"; then
        log "ERROR: Failed to checkout original branch $current_branch"
        return 1
    fi

    # Cherry-pick the automation commit to restore working directory state
    # but then reset to undo the commit (keeping working directory changes)
    log "Restoring working directory state on $current_branch..."
    if git cherry-pick --no-commit "$auto_branch" 2>&1 | tee -a "$LOG_FILE"; then
        # Reset the index but keep working directory changes
        git reset HEAD 2>&1 | tee -a "$LOG_FILE"
        log "Working directory state restored on $current_branch"
    else
        log "WARNING: Failed to restore exact working directory state in $repo_path"
        # Clean up failed cherry-pick
        git cherry-pick --abort 2>/dev/null
    fi

    return 0
}

# Main execution
main() {
    log "=== Git Auto-Save Started ==="
    log "User: $CURRENT_USER"
    log "Date: $CURRENT_DATE"
    log "Hostname: $(hostname)"

    local total_repos=0
    local processed_repos=0
    local saved_repos=0

    # Process each search directory
    for search_dir in "${SEARCH_DIRS[@]}"; do
        # Expand tilde
        search_dir="${search_dir/#\~/$HOME}"

        log "Searching for repositories in: $search_dir"

        # Find and process all git repos
        while IFS= read -r repo_path; do
            ((total_repos++))

            if process_repo "$repo_path"; then
                ((processed_repos++))

                # Check if we actually saved (not just skipped)
                if grep -q "SUCCESS: Pushed" "$LOG_FILE" | tail -1; then
                    ((saved_repos++))
                fi
            fi
        done < <(find_git_repos "$search_dir")
    done

    log "=== Git Auto-Save Completed ==="
    log "Total repositories found: $total_repos"
    log "Successfully processed: $processed_repos"
    log "Repositories saved: $saved_repos"

    # Return success even if some repos failed
    # (we don't want to prevent logout)
    return 0
}

# Run main function
main
exit 0
