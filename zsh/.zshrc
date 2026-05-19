# Homebrew PATH (Apple Silicon / Intel / Linux)
if [ -f /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -f /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
elif [ -f /home/linuxbrew/.linuxbrew/bin/brew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

export PATH="$HOME/.local/bin:$PATH"

# fnm (Fast Node Manager) — used on Linux; no-op if not installed
if command -v fnm &>/dev/null; then
    eval "$(fnm env --use-on-cd --shell zsh)"
fi

export EDITOR="nvim"

alias updateclaude='rm -rf /opt/homebrew/lib/node_modules/@anthropic-ai/claude-code && npm i -g @anthropic-ai/claude-code'

ts() {
    # Function to print usage
    print_usage() {
        echo "Usage: ts <session_name> [-d <directory>]"
        echo "  session_name: Name of the tmux session"
        echo "  -d: Working directory (optional, defaults to current directory)"
        return 1
    }

    # Store the initial directory
    WORKING_DIR=$(pwd)

    # Check if session name is provided as first argument
    SESSION_NAME=$1
    if [ -z "$SESSION_NAME" ]; then
        print_usage
        return 1
    fi
    shift  # Remove first argument (session name) from argument list

    # Parse remaining arguments for directory if -d is provided
    OPTIND=1  # Reset OPTIND
    while getopts ":d:" opt; do
        case $opt in
            d) WORKING_DIR=$OPTARG ;;
            \?) print_usage ;;
        esac
    done

    # Verify the working directory exists
    if [ ! -d "$WORKING_DIR" ]; then
        echo "Error: Directory '$WORKING_DIR' does not exist"
        return 1
    fi

    # Convert working directory to absolute path
    WORKING_DIR=$(cd "$WORKING_DIR" && pwd)

    # Function to create new session
    create_session() {
        # Create new session with first window
        tmux new-session -d -s "$SESSION_NAME" -c "$WORKING_DIR"

        tmux rename-window -t "$SESSION_NAME:1" 'vim'
        tmux split-window -t "$SESSION_NAME:vim" -v -c "$WORKING_DIR"

        tmux new-window -t "$SESSION_NAME:2" -n 'servers' -c "$WORKING_DIR"
        tmux split-window -t "$SESSION_NAME:2" -h -c "$WORKING_DIR"
        tmux split-window -t "$SESSION_NAME:2.0" -v -c "$WORKING_DIR"
        tmux split-window -t "$SESSION_NAME:2.2" -v -c "$WORKING_DIR"
        tmux new-window -t "$SESSION_NAME:3" -n 'extra' -c "$WORKING_DIR"

        tmux select-window -t "$SESSION_NAME:1"
    }

    # Check if target session exists
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        # Session exists
        if [ -n "$TMUX" ]; then
            # We're in a tmux session - switch to the target session
            tmux switch-client -t "$SESSION_NAME"
        else
            # We're not in tmux - just attach
            tmux attach-session -t "$SESSION_NAME"
        fi
    else
        # Session doesn't exist - create it
        create_session
        if [ -n "$TMUX" ]; then
            # We're in a tmux session - switch to the new session
            tmux switch-client -t "$SESSION_NAME"
        else
            # We're not in tmux - attach to the new session
            tmux attach-session -t "$SESSION_NAME"
        fi
    fi
}

ZSH_THEME="robbyrussell"

plugins=(git zsh-vi-mode)

source $ZSH/oh-my-zsh.sh

alias vim='nvim'
alias dotfiles='make -C ~/Documents/dotfiles'
alias ralph='~/.claude/skills/ralph/scripts/ralph.sh'

# Create a git worktree in /tmp/gitworktrees and copy .env files from a source folder
# Usage: gwtc <src_folder> <worktree_name> [branch_name]
gwtc() {
  local src_folder="$1"
  local wt_name="$2"
  local branch_name="$3"

  if [[ -z "$src_folder" || -z "$wt_name" ]]; then
    echo "Usage: gwtc <src_folder_path> <worktree_name> [branch_name]"
    echo "  src_folder_path  Path to the repo (relative or absolute)"
    echo "  worktree_name    Name for the worktree directory"
    echo "  branch_name      Branch to create (default: wt/<worktree_name>)"
    return 1
  fi

  # Resolve to absolute path
  local abs_src
  abs_src="$(cd "$src_folder" 2>/dev/null && pwd)"
  if [[ $? -ne 0 ]]; then
    echo "Error: '$src_folder' is not a valid directory"
    return 1
  fi

  # Verify it's inside a git repo
  if ! git -C "$abs_src" rev-parse --is-inside-work-tree &>/dev/null; then
    echo "Error: '$abs_src' is not inside a git repository"
    return 1
  fi

  # Auto-generate branch name if not provided
  if [[ -z "$branch_name" ]]; then
    branch_name="wt/${wt_name}"
  fi

  local wt_base="/tmp/gitworktrees"
  local wt_path="${wt_base}/${wt_name}"

  if [[ -d "$wt_path" ]]; then
    echo "Error: worktree path '$wt_path' already exists"
    return 1
  fi

  mkdir -p "$wt_base"

  # Fetch latest remote so we branch from origin/main, not local HEAD
  echo "Fetching latest from origin..."
  git -C "$abs_src" fetch origin main --quiet

  # Check if branch already exists (local or remote)
  if git -C "$abs_src" show-ref --verify --quiet "refs/heads/$branch_name" 2>/dev/null; then
    echo "Creating worktree at: $wt_path (existing branch: $branch_name)"
    if ! git -C "$abs_src" worktree add "$wt_path" "$branch_name"; then
      echo "Error: failed to create worktree"
      return 1
    fi
  else
    echo "Creating worktree at: $wt_path (new branch: $branch_name) from origin/main"
    if ! git -C "$abs_src" worktree add "$wt_path" -b "$branch_name" origin/main; then
      echo "Error: failed to create worktree"
      return 1
    fi
  fi

  # Copy .env files preserving relative paths
  local env_count=0
  while IFS= read -r -d '' env_file; do
    local rel_path="${env_file#$abs_src/}"
    local dest_dir="${wt_path}/$(dirname "$rel_path")"
    mkdir -p "$dest_dir"
    cp "$env_file" "${wt_path}/${rel_path}"
    echo "  Copied: $rel_path"
    ((env_count++))
  done < <(find "$abs_src" -name '.env*' -not -path '*node_modules*' -not -path '*.git/*' -not -path '*/.venv/*' -print0)

  echo ""
  echo "Worktree ready: $wt_path"
  echo "Branch: $branch_name"
  echo "Env files copied: $env_count"
}

# List all worktrees created via gwtc
# Usage: gwtl
gwtl() {
  local wt_base="/tmp/gitworktrees"

  if [[ ! -d "$wt_base" ]] || [[ -z "$(ls -A "$wt_base" 2>/dev/null)" ]]; then
    echo "No worktrees in $wt_base"
    return 0
  fi

  printf "%-20s %-30s %s\n" "NAME" "BRANCH" "PATH"
  printf "%-20s %-30s %s\n" "----" "------" "----"

  for wt_dir in "$wt_base"/*/; do
    [[ -d "$wt_dir" ]] || continue
    local name="$(basename "$wt_dir")"
    local branch=""
    if git -C "$wt_dir" rev-parse --abbrev-ref HEAD &>/dev/null; then
      branch="$(git -C "$wt_dir" rev-parse --abbrev-ref HEAD)"
    else
      branch="(detached/broken)"
    fi
    printf "%-20s %-30s %s\n" "$name" "$branch" "$wt_dir"
  done
}

# Delete a worktree created via gwtc (keeps branch by default)
# Usage: gwtd <worktree_name> [--delete-branch]
gwtd() {
  local wt_name="$1"
  local delete_branch=false

  if [[ -z "$wt_name" ]]; then
    echo "Usage: gwtd <worktree_name> [--delete-branch]"
    echo "  Removes the worktree. Use --delete-branch to also delete the branch."
    echo ""
    echo "Available worktrees:"
    gwtl
    return 1
  fi

  if [[ "$2" == "--delete-branch" ]]; then
    delete_branch=true
  fi

  local wt_base="/tmp/gitworktrees"
  local wt_path="${wt_base}/${wt_name}"

  if [[ ! -d "$wt_path" ]]; then
    echo "Error: worktree '$wt_name' not found at $wt_path"
    return 1
  fi

  # Get the branch name before removing
  local branch=""
  if git -C "$wt_path" rev-parse --abbrev-ref HEAD &>/dev/null; then
    branch="$(git -C "$wt_path" rev-parse --abbrev-ref HEAD)"
  fi

  # Find the main repo this worktree belongs to
  local main_repo=""
  main_repo="$(git -C "$wt_path" worktree list --porcelain | head -1 | sed 's/^worktree //')"

  # Remove the worktree via git
  if ! git -C "$main_repo" worktree remove "$wt_path" --force; then
    echo "Error: failed to remove worktree"
    return 1
  fi

  echo "Removed worktree: $wt_path"

  # Only delete the branch if --delete-branch was passed
  if [[ "$delete_branch" == true && -n "$branch" && "$branch" != "HEAD" ]]; then
    if git -C "$main_repo" branch -d "$branch" 2>/dev/null; then
      echo "Deleted branch: $branch"
    else
      echo "Branch '$branch' has unmerged changes. Use 'git -C $main_repo branch -D $branch' to force delete."
    fi
  else
    echo "Kept branch: $branch"
  fi
}

# CD into a worktree and run Claude Code with --dangerously-skip-permissions
# Usage: gwtclaude <worktree_name>
gwtclaude() {
  local wt_name="$1"

  if [[ -z "$wt_name" ]]; then
    echo "Usage: gwtclaude <worktree_name>"
    echo "  Opens a worktree in Claude Code with --dangerously-skip-permissions."
    echo ""
    echo "Available worktrees:"
    gwtl
    return 1
  fi

  local wt_base="/tmp/gitworktrees"
  local wt_path="${wt_base}/${wt_name}"

  if [[ ! -d "$wt_path" ]]; then
    echo "Error: worktree '$wt_name' not found at $wt_path"
    return 1
  fi

  cd "$wt_path" && claude --dangerously-skip-permissions
}

# direnv hook — auto-loads .envrc when you cd into a project
if command -v direnv &>/dev/null; then
    eval "$(direnv hook zsh)"
fi

# macOS Keychain helpers — store/retrieve secrets so they never live in
# .env files or shell history. Pair with `from_keychain` / `keychain_export`
# in ~/.config/direnv/direnvrc to load them per-project via direnv.
#
#   kc-set myproject-db        # prompts silently, stores under your user
#   kc-get myproject-db        # prints the value
#   kc-rm  myproject-db        # deletes it
kc-set() {
    local name="$1"
    local value="$2"
    if [[ -z "$name" ]]; then
        echo "Usage: kc-set <name> [value]"
        echo "  Stores a secret in macOS Keychain. Omits value to prompt silently."
        return 1
    fi
    if [[ -z "$value" ]]; then
        printf "Value for %s: " "$name"
        read -rs value
        echo
    fi
    if security add-generic-password -U -a "$USER" -s "$name" -w "$value"; then
        echo "Stored '$name' in Keychain"
        kc-redact-add "$name" >/dev/null
    fi
}

kc-get() {
    local name="$1"
    if [[ -z "$name" ]]; then
        echo "Usage: kc-get <name>"
        return 1
    fi
    security find-generic-password -a "$USER" -s "$name" -w
}

kc-rm() {
    local name="$1"
    if [[ -z "$name" ]]; then
        echo "Usage: kc-rm <name>"
        return 1
    fi
    if security delete-generic-password -a "$USER" -s "$name"; then
        local config="${CLAUDE_REDACT_CONFIG:-$HOME/.config/claude-redact/secrets}"
        if [[ -f "$config" ]] && grep -Fxq "$name" "$config" 2>/dev/null; then
            grep -Fvx "$name" "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"
            echo "Removed '$name' from redact list"
        fi
    fi
}

# Add a Keychain entry name to the redact-secrets.py hook's watchlist.
# The hook then redacts any occurrence of that secret's value from
# Bash/Read/WebFetch tool output before Claude sees it.
kc-redact-add() {
    local name="$1"
    if [[ -z "$name" ]]; then
        echo "Usage: kc-redact-add <keychain-name>"
        return 1
    fi
    local config="${CLAUDE_REDACT_CONFIG:-$HOME/.config/claude-redact/secrets}"
    mkdir -p "$(dirname "$config")"
    touch "$config"
    if grep -Fxq "$name" "$config" 2>/dev/null; then
        echo "Already on redact list: $name"
    else
        echo "$name" >> "$config"
        echo "Added to redact list: $name"
    fi
}

# Remove a name from the redact list WITHOUT deleting the keychain entry.
# Use this for entries that aren't actually secret-shaped (ports, sizes,
# IDs) — they cause false-positive matches and slow the hook down.
kc-redact-rm() {
    local name="$1"
    if [[ -z "$name" ]]; then
        echo "Usage: kc-redact-rm <keychain-name>"
        return 1
    fi
    local config="${CLAUDE_REDACT_CONFIG:-$HOME/.config/claude-redact/secrets}"
    if [[ ! -f "$config" ]] || ! grep -Fxq "$name" "$config"; then
        echo "Not on redact list: $name"
        return 0
    fi
    grep -Fvx "$name" "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"
    echo "Removed from redact list: $name (keychain entry unchanged)"
}

# Show every entry on the redact list with the length of its keychain value.
# Short values (<8 chars) are skipped by the hook anyway. Use this to find
# entries to prune via kc-redact-rm.
kc-redact-list() {
    local config="${CLAUDE_REDACT_CONFIG:-$HOME/.config/claude-redact/secrets}"
    if [[ ! -f "$config" ]]; then
        echo "No redact list at: $config"
        return 0
    fi
    printf "%-50s %s\n" "NAME" "VALUE_LEN"
    printf "%-50s %s\n" "----" "---------"
    while IFS= read -r name; do
        [[ -z "$name" || "$name" =~ ^[[:space:]]*# ]] && continue
        local value
        value=$(security find-generic-password -a "$USER" -s "$name" -w 2>/dev/null)
        local len=${#value}
        local marker=""
        (( len < 8 )) && marker="  (skipped: too short)"
        printf "%-50s %d%s\n" "$name" "$len" "$marker"
    done < "$config"
}

# List every generic-password service name in your login keychain.
kc-list() {
    security dump-keychain 2>/dev/null \
        | awk -F\" '/"svce"<blob>="/ {print $4}' \
        | sort -u
}

# One-shot: scan the login keychain for entries whose names start with
# the given prefix and add each to the redact-secrets watchlist.
# Use this once after enabling the hook to backfill existing Keychain entries.
kc-redact-import-existing() {
    local prefix="$1"
    if [[ -z "$prefix" ]]; then
        echo "Usage: kc-redact-import-existing <prefix>"
        echo "  Adds every keychain entry whose name starts with <prefix> to the redact list."
        echo "  Tip: run 'kc-list' first to see what's in your keychain."
        return 1
    fi
    local matches found=0 already=0
    matches=$(kc-list | grep "^${prefix}" || true)
    if [[ -z "$matches" ]]; then
        echo "No keychain entries start with '$prefix'"
        return 0
    fi
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        local config="${CLAUDE_REDACT_CONFIG:-$HOME/.config/claude-redact/secrets}"
        mkdir -p "$(dirname "$config")"
        touch "$config"
        if grep -Fxq "$name" "$config" 2>/dev/null; then
            ((already++))
        else
            echo "$name" >> "$config"
            echo "  added: $name"
            ((found++))
        fi
    done <<< "$matches"
    echo "Done — added $found, already had $already"
}

# Import secrets from a .env file into Keychain in bulk. Asks for a project
# prefix (e.g. fahad-api), picks up only UPPERCASE_KEY=value lines, stores
# each as <prefix>-<kebab-key>, writes keychain_export lines to .envrc, and
# strips the moved lines from .env. Non-matching lines (comments, blanks,
# lowercase keys) are left in .env untouched.
#
#   cd into project, then: kc-import           # uses ./.env
#                          kc-import path/.env
kc-import() {
    local env_file="${1:-.env}"
    if [[ ! -f "$env_file" ]]; then
        echo "Error: $env_file not found"
        return 1
    fi

    printf "Project key prefix (e.g. fahad-api): "
    local prefix
    read -r prefix
    if [[ -z "$prefix" ]]; then
        echo "Error: prefix is required"
        return 1
    fi

    local -a keys values names
    local line key value kebab kc_name

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        if [[ "$line" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]]; then
            key="${match[1]}"
            value="${match[2]}"
            if [[ "$value" =~ ^\"(.*)\"$ ]]; then
                value="${match[1]}"
            elif [[ "$value" =~ ^\'(.*)\'$ ]]; then
                value="${match[1]}"
            fi
            kebab="${(L)key//_/-}"
            kc_name="${prefix}-${kebab}"
            keys+=("$key")
            values+=("$value")
            names+=("$kc_name")
        fi
    done < "$env_file"

    if [[ ${#keys[@]} -eq 0 ]]; then
        echo "No matching UPPERCASE_NAME=value lines in $env_file"
        return 0
    fi

    echo
    echo "Will move ${#keys[@]} secret(s) from $env_file to Keychain:"
    local i
    for ((i = 1; i <= ${#keys[@]}; i++)); do
        printf "  %-32s -> %s\n" "${keys[i]}" "${names[i]}"
    done
    echo
    printf "Proceed? [y/N] "
    local ans
    read -r ans
    if [[ "$ans" != "y" && "$ans" != "Y" ]]; then
        echo "Aborted"
        return 1
    fi

    local backup="${env_file}.bak.$(date +%s)"
    cp "$env_file" "$backup"
    echo "Backup: $backup"

    local failed=0
    for ((i = 1; i <= ${#keys[@]}; i++)); do
        if security add-generic-password -U -a "$USER" -s "${names[i]}" -w "${values[i]}" 2>/dev/null; then
            echo "  stored ${names[i]}"
        else
            echo "  FAILED ${names[i]}"
            ((failed++))
        fi
    done
    if (( failed > 0 )); then
        echo "Aborted: $failed Keychain write(s) failed. $env_file unchanged."
        return 1
    fi

    local envrc=".envrc"
    touch "$envrc"
    for ((i = 1; i <= ${#keys[@]}; i++)); do
        local export_line="keychain_export ${keys[i]} ${names[i]}"
        grep -Fxq "$export_line" "$envrc" || echo "$export_line" >> "$envrc"
    done
    echo "Updated: $envrc"

    local redact_cfg="${CLAUDE_REDACT_CONFIG:-$HOME/.config/claude-redact/secrets}"
    mkdir -p "$(dirname "$redact_cfg")"
    touch "$redact_cfg"
    local added=0
    for ((i = 1; i <= ${#names[@]}; i++)); do
        if ! grep -Fxq "${names[i]}" "$redact_cfg" 2>/dev/null; then
            echo "${names[i]}" >> "$redact_cfg"
            ((added++))
        fi
    done
    [[ $added -gt 0 ]] && echo "Added $added entry(s) to redact list: $redact_cfg"

    local tmp
    tmp="$(mktemp)"
    while IFS= read -r line || [[ -n "$line" ]]; do
        local stripped="${line%$'\r'}"
        if [[ "$stripped" =~ ^[A-Z][A-Z0-9_]*= ]]; then
            continue
        fi
        printf '%s\n' "$line"
    done < "$env_file" > "$tmp"
    mv "$tmp" "$env_file"
    echo "Cleaned: $env_file (matched lines removed)"

    echo
    echo "Next: direnv allow"
}

# Machine-specific overrides (API keys, local paths, etc.)
[ -f ~/.zshrc.local ] && source ~/.zshrc.local

# AWS CLI completion (v2 ships aws_completer)
if command -v aws_completer &>/dev/null; then
    autoload -U +X bashcompinit && bashcompinit
    complete -C "$(command -v aws_completer)" aws
fi
# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/tarekkekhia/Downloads/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/tarekkekhia/Downloads/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/Users/tarekkekhia/Downloads/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/tarekkekhia/Downloads/google-cloud-sdk/completion.zsh.inc'; fi

# Terragrunt provider cache server — downloads each Terraform provider once
# and serves it to all leaves (safe for parallel `run --all`, unlike plain
# TF_PLUGIN_CACHE_DIR). Saves ~10 GB of redundant AWS provider downloads in
# multi-leaf repos like iac-adadvisor.
export TG_PROVIDER_CACHE=1
export TG_PROVIDER_CACHE_DIR="$HOME/.cache/terragrunt/providers"

# Fetch dependency outputs directly from S3 state instead of running
# `terraform output` in each dep's .terragrunt-cache. Drops dependency
# resolution from ~90s to ~5s on multi-dep leaves like ecs/.
export TG_EXPERIMENT=dependency-fetch-output-from-state
export TG_DEPENDENCY_FETCH_OUTPUT_FROM_STATE=true
