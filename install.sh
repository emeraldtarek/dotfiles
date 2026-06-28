#!/bin/bash

set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$DOTFILES_DIR"

# ── OS-specific packages ───────────────────────────────────────────
if [[ "$OSTYPE" == darwin* ]]; then
    source "$DOTFILES_DIR/scripts/macos.sh"
elif [[ "$OSTYPE" == linux-gnu* ]]; then
    source "$DOTFILES_DIR/scripts/linux.sh"
fi

# ── Pre-stow: ensure directories exist to prevent tree folding ────
mkdir -p "$HOME/.claude"

# ── Tool cache dirs ────────────────────────────────────────────────
# Terragrunt provider cache (referenced by TG_PROVIDER_CACHE_DIR in zsh/.zshrc)
mkdir -p "$HOME/.cache/terragrunt/providers"
# Terraform filesystem mirror (used by repos that pre-populate with
# `terraform providers mirror` for fast multi-leaf lock regen)
mkdir -p "$HOME/tf-mirror"

# ── Stow packages ─────────────────────────────────────────────────
echo "Stowing dotfiles..."
for pkg in nvim tmux zsh git claude direnv ssh; do
    # Back up existing files that would conflict with stow
    for f in $(stow --no --verbose --target="$HOME" "$pkg" 2>&1 | grep "existing target" | sed 's/.*: //'); do
        if [ -e "$HOME/$f" ] && [ ! -L "$HOME/$f" ]; then
            echo "  backing up ~/$f → ~/${f}.backup"
            mv "$HOME/$f" "$HOME/${f}.backup"
        fi
    done
    stow --restow --target="$HOME" "$pkg"
    echo "  stowed $pkg"
done

# ── SSH config (remote dev) ───────────────────────────────────────
# The `ssh` package stows ~/.ssh/config.d/dev.conf. We do NOT stow ~/.ssh/config
# itself (it's often a real, machine-specific file) — instead we make sure it
# Includes our drop-in + the untracked config.local, prepending so first-match
# precedence works as intended.
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
touch "$HOME/.ssh/config" && chmod 600 "$HOME/.ssh/config"
if ! grep -q 'config.d/\*.conf' "$HOME/.ssh/config"; then
    # Back up the original before prepending Include lines (content is otherwise
    # preserved verbatim — we only add two lines at the top).
    if [ -s "$HOME/.ssh/config" ] && [ ! -f "$HOME/.ssh/config.pre-dotfiles.backup" ]; then
        cp "$HOME/.ssh/config" "$HOME/.ssh/config.pre-dotfiles.backup"
        echo "  backed up ~/.ssh/config → ~/.ssh/config.pre-dotfiles.backup"
    fi
    { printf 'Include ~/.ssh/config.local\nInclude ~/.ssh/config.d/*.conf\n\n'; \
      cat "$HOME/.ssh/config"; } > "$HOME/.ssh/config.tmp"
    mv "$HOME/.ssh/config.tmp" "$HOME/.ssh/config"
    chmod 600 "$HOME/.ssh/config"
    echo "  added Include lines to ~/.ssh/config"
fi
if [ ! -f "$HOME/.ssh/config.local" ]; then
    cat > "$HOME/.ssh/config.local" <<'EOF'
# Machine-specific SSH hosts (not tracked in git).
# Shared `dev` options (Port 443, ControlMaster, keepalives) live in
# ~/.ssh/config.d/dev.conf — only put your VPS specifics here:
#
# Host dev
#     HostName 203.0.113.10
#     User tarek
EOF
    chmod 600 "$HOME/.ssh/config.local"
    echo "Created ~/.ssh/config.local template (fill in your VPS)"
fi

# ── Oh My Zsh ──────────────────────────────────────────────────────
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "Installing Oh My Zsh..."
    KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# ── zsh-vi-mode plugin ────────────────────────────────────────────
ZVM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-vi-mode"
if [ ! -d "$ZVM_DIR" ]; then
    echo "Installing zsh-vi-mode..."
    git clone https://github.com/jeffreytse/zsh-vi-mode "$ZVM_DIR"
fi

# ── TPM + tmux plugins ────────────────────────────────────────────
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    echo "Installing TPM..."
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
fi

echo "Installing tmux plugins..."
tmux new-session -d -s _tpm_install 2>/dev/null && \
    "$HOME/.tmux/plugins/tpm/bin/install_plugins" && \
    tmux kill-session -t _tpm_install 2>/dev/null || \
    echo "  skipped (will auto-install on first tmux launch — press prefix + I)"

# ── Local config templates ─────────────────────────────────────────
if [ ! -f "$HOME/.zshrc.local" ]; then
    cat > "$HOME/.zshrc.local" <<'EOF'
# Machine-specific shell config (not tracked in git)
# Examples:
# export GEMINI_API_KEY="..."
# export GOOGLE_CLOUD_PROJECT="..."
# export PATH="$PATH:$HOME/.pulumi/bin"
EOF
    echo "Created ~/.zshrc.local template"
fi

# ── Claude Code plugins ───────────────────────────────────────────
if command -v claude &> /dev/null; then
    echo "Installing Claude Code plugins..."
    claude plugin install typescript-lsp@claude-plugins-official 2>/dev/null || true
    claude plugin install pyright-lsp@claude-plugins-official 2>/dev/null || true
    claude plugin install sanity-plugin@sanity-agent-toolkit 2>/dev/null || true
    echo "  done"
else
    echo "Skipping Claude Code plugins (claude not installed)"
fi

if [ ! -f "$HOME/.claude/settings.local.json" ]; then
    cat > "$HOME/.claude/settings.local.json" <<'EOF'
{
  "permissions": {
    "allow": []
  }
}
EOF
    echo "Created ~/.claude/settings.local.json template"
fi

if [ ! -f "$HOME/.gitconfig-local" ]; then
    cat > "$HOME/.gitconfig-local" <<'EOF'
# Machine-specific git config (not tracked in git)
# Examples:
# [includeIf "gitdir:~/work/"]
#     path = ~/.gitconfig-work
EOF
    echo "Created ~/.gitconfig-local template"
fi

# ── Default shell ──────────────────────────────────────────────────
ZSH_PATH="$(which zsh)"
if [ "$SHELL" != "$ZSH_PATH" ]; then
    echo "Changing default shell to zsh..."
    if ! grep -q "$ZSH_PATH" /etc/shells; then
        echo "$ZSH_PATH" | sudo tee -a /etc/shells
    fi
    chsh -s "$ZSH_PATH"
fi

echo ""
echo "Done! Restart your terminal or run: exec zsh"
