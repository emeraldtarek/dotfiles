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
