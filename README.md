# dotfiles

Personal dev environment managed with [GNU Stow](https://www.gnu.org/software/stow/). One command to bootstrap a fresh Mac or Linux machine.

## Quick Start

```bash
git clone <repo-url> ~/.dotfiles
cd ~/.dotfiles
chmod +x install.sh
./install.sh
```

The install script:
1. Installs packages via Homebrew (macOS) or apt (Linux)
2. Uses `stow --restow` to symlink config packages into `$HOME`
3. Installs Oh My Zsh + zsh-vi-mode plugin
4. Installs TPM and tmux plugins
5. Creates `~/.zshrc.local` and `~/.gitconfig-local` templates for machine-specific settings
6. Sets zsh as default shell

## Structure

| Directory | Stowed? | Description |
|-----------|---------|-------------|
| `nvim/` | Yes | Neovim config → `~/.config/nvim` |
| `tmux/` | Yes | tmux config → `~/.tmux.conf` |
| `zsh/` | Yes | Zsh config → `~/.zshrc` |
| `git/` | Yes | Git config → `~/.gitconfig`, `~/.gitignore_global` |
| `claude/` | Yes | Claude Code config → `~/.claude/` (settings, skills, MCP servers) |
| `iterm2/` | No | iTerm2 color scheme (imported during install) |
| `scripts/` | No | OS-specific install scripts |

## Neovim Plugins

| Plugin | Purpose |
|--------|---------|
| **tokyonight.nvim** | Color scheme |
| **telescope.nvim** | Fuzzy finder (files, grep, buffers) |
| **nvim-treesitter** | Syntax highlighting and code analysis |
| **nvim-lspconfig** + **mason.nvim** | LSP support with auto-installed servers |
| **lsp-zero.nvim** | Simplified LSP configuration |
| **nvim-cmp** | Autocompletion (LSP, buffer, path, snippets) |
| **LuaSnip** + **friendly-snippets** | Snippet engine and library |
| **conform.nvim** | Formatting (prettier, stylua, ruff, djlint, xmlformat) |
| **nvim-lint** | Linting (eslint_d) |
| **nvim-ufo** | Code folding |
| **nvim-autopairs** | Auto-close brackets/quotes |
| **nvim-comment** | Toggle comments |
| **vim-tmux-navigator** | Seamless nav between vim splits and tmux panes |

### LSP Servers (via Mason)

ts_ls, html, cssls, tailwindcss, svelte, lua_ls, graphql, emmet_ls, prismals, pyright

## Environment Variables

Required env vars (API keys, tokens, etc.) are listed in `env.example`. After cloning:

```bash
make env            # scaffolds missing vars into ~/.zshrc.local
vim ~/.zshrc.local  # fill in values
source ~/.zshrc.local
```

## Machine-Specific Config

Files not tracked in git — created as templates on first install:

- **`~/.zshrc.local`** — env vars, API keys, local PATHs (Pulumi, LM Studio, etc.)
- **`~/.gitconfig-local`** — `includeIf` blocks for work repos

## Re-running

The install script is idempotent — safe to run again at any time:

```bash
cd ~/.dotfiles && ./install.sh
```
