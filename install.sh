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

# ── Stow packages ─────────────────────────────────────────────────
echo "Stowing dotfiles..."
for pkg in nvim tmux zsh git claude; do
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
