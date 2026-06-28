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
| `ssh/` | Yes | SSH drop-in → `~/.ssh/config.d/dev.conf` (remote dev VPS) |
| `caddy/` | No | Caddy reverse-proxy config (deployed to the VPS by `vps-tunnel.sh`) |
| `cloudflared/` | No | Cloudflare Tunnel ingress template (real config generated on the VPS) |
| `iterm2/` | No | iTerm2 color scheme (imported during install) |
| `scripts/` | No | OS-specific install + `vps-harden.sh` + `vps-tunnel.sh` |

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

## Remote Dev (VPS)

Develop on a cloud VPS over SSH — nvim, tmux and Claude Code run on the box; your
laptop is just a terminal + a window onto the VPS's `localhost`. Designed to work
from restrictive/travel networks (no Tailscale, no UDP) by riding SSH on 443.

**On the VPS** (fresh Debian/Ubuntu):

```bash
git clone <repo-url> ~/.dotfiles && cd ~/.dotfiles && ./install.sh   # installs et
sudo ./scripts/vps-harden.sh                                         # sshd on 443 + et server
```

**On your Mac:** fill in `~/.ssh/config.local` (`HostName` + `User` for `Host dev`),
then:

| Command | What it does |
|---------|--------------|
| `dev` | Connect to the VPS over Eternal Terminal (survives drops/roaming; falls back to `ssh`). Run `tmux` / `ts <proj>` inside it. |
| `dev-forward` | Auto-forwarder — watches the VPS and forwards every new listening dev port (3000–9999) to your Mac's localhost. The nvim equivalent of VS Code's port forwarding. Leave it running in a spare tab. |
| `fwd 3000` / `unfwd 3000` | Manually forward/drop a single port into the live connection (no reconnect). |

So `npm run dev` or `docker compose up` on the VPS shows up at `http://localhost:3000`
on your Mac, exactly like local. The shared `dev` SSH options (Port 443,
ControlMaster, keepalives) live in `ssh/.ssh/config.d/dev.conf`; only your VPS's
host/user go in the untracked `~/.ssh/config.local`.

### Public URLs (webhooks · mobile · demos)

Secondary to the SSH path — for the things localhost can't do: webhook callbacks
(Stripe/Twilio/Meta), testing on your phone, OAuth redirects, sharing. A
**Cloudflare named tunnel** (outbound-only — no inbound ports on the VPS) fronts
a **Caddy** reverse proxy that routes subdomains to local ports.

```
sender / phone / client ──https──► Cloudflare ──tunnel──► cloudflared ──► Caddy :8080 ──► localhost:3000
```

**Setup** (on the VPS, needs a domain on Cloudflare):

```bash
./scripts/vps-tunnel.sh your-zone.com     # installs caddy + cloudflared, creates tunnel, wires DNS
# then add one Cloudflare Access app for *.dev.your-zone.com (the script prints exact steps)
```

**Using it:**

| URL | Routes to | Notes |
|-----|-----------|-------|
| `https://p3000.dev.zone` | `localhost:3000` | **Any port, zero config** — just open `p<port>.dev.zone`. |
| `https://name.dev.zone` | a named port | Add pretty routes in `/etc/caddy/named.caddy` → `sudo systemctl reload caddy`. |
| `https://hooks.zone` | webhook target | **Not** behind Access so Stripe/Twilio/Meta reach it — verify signatures in-app. |
| `share 3000` (on VPS) | ephemeral `*.trycloudflare.com` | No domain/config; URL changes each run. One-off shares only. |

**Access** locks `*.dev.zone` to your email (Cloudflare Zero Trust, free), so dev
apps aren't open to the world. `hooks.zone` stays public by design. From inside
Syria these Cloudflare-fronted URLs may be flaky — but they're mostly hit by
*external* senders/devices, and your own previewing uses the SSH-localhost path.
