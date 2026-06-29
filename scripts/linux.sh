#!/bin/bash
# Linux-specific setup (Debian/Ubuntu)

set -e

echo "Updating package lists..."
sudo apt-get update

echo "Installing core packages..."
sudo apt-get install -y --no-install-recommends \
    tmux \
    git \
    curl \
    wget \
    stow \
    ripgrep \
    fzf \
    python3 \
    python3-venv \
    zsh \
    build-essential \
    software-properties-common \
    unzip \
    fontconfig

# ── Neovim (tarball from GitHub releases) ─────────────────────────
# PPA is stuck on 0.9.x; tarball gives latest stable with no deps
NVIM_MIN_VERSION="0.11"
case "$(uname -m)" in
    x86_64|amd64)  NVIM_ARCH="x86_64" ;;
    aarch64|arm64) NVIM_ARCH="arm64"  ;;
    *) echo "  ! unknown arch $(uname -m), defaulting to x86_64"; NVIM_ARCH="x86_64" ;;
esac
NVIM_INSTALL_DIR="/opt/nvim-linux-${NVIM_ARCH}"

needs_nvim_install() {
    if ! command -v nvim &>/dev/null; then
        return 0
    fi
    local current
    current=$(nvim --version | head -1 | grep -oP '\d+\.\d+')
    [ "$(printf '%s\n' "$NVIM_MIN_VERSION" "$current" | sort -V | head -1)" != "$NVIM_MIN_VERSION" ]
}

if needs_nvim_install; then
    echo "Installing Neovim (${NVIM_ARCH})..."
    sudo apt-get remove -y neovim 2>/dev/null || true
    curl -fsSL -o "/tmp/nvim-linux-${NVIM_ARCH}.tar.gz" \
        "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${NVIM_ARCH}.tar.gz"
    sudo rm -rf "$NVIM_INSTALL_DIR"
    sudo tar -C /opt -xzf "/tmp/nvim-linux-${NVIM_ARCH}.tar.gz"
    sudo ln -sf "$NVIM_INSTALL_DIR/bin/nvim" /usr/local/bin/nvim
    rm "/tmp/nvim-linux-${NVIM_ARCH}.tar.gz"
    echo "  installed $(nvim --version | head -1)"
else
    echo "Neovim already installed: $(nvim --version | head -1)"
fi

# ── fnm (Fast Node Manager) ──────────────────────────────────────
# Replaces NodeSource PPA — no apt conflicts, userspace install
if ! command -v fnm &>/dev/null; then
    echo "Installing fnm..."
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
    export PATH="$HOME/.local/share/fnm:$PATH"
fi

if ! fnm list 2>/dev/null | grep -q "v[0-9]"; then
    echo "Installing Node.js LTS via fnm..."
    eval "$(fnm env --shell bash)"
    fnm install --lts
fi

# ── Docker (your `docker compose up` dev flow) ────────────────────
# Official repo; works on both Ubuntu and Debian via $ID/$VERSION_CODENAME.
if ! command -v docker &>/dev/null; then
    echo "Installing Docker..."
    DISTRO_ID=$(. /etc/os-release && echo "$ID")              # ubuntu | debian
    DISTRO_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/${DISTRO_ID}/gpg" \
        | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${DISTRO_ID} ${DISTRO_CODENAME} stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo usermod -aG docker "$USER"
    echo "  Docker installed — run 'newgrp docker' or re-login for the group to apply"
fi

# ── GitHub CLI ────────────────────────────────────────────────────
if ! command -v gh &>/dev/null; then
    echo "Installing GitHub CLI..."
    sudo mkdir -p -m 755 /etc/apt/keyrings
    wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y gh
fi

# ── Eternal Terminal (resilient SSH: survives drops, carries port tunnels) ──
# TCP-based (unlike mosh's UDP, which travel/Syria networks often throttle).
# The `et` package ships both the client and an etserver systemd unit on :2022.
if ! command -v et &>/dev/null; then
    echo "Installing Eternal Terminal..."
    if grep -qi ubuntu /etc/os-release 2>/dev/null; then
        sudo add-apt-repository -y ppa:jgmath2000/et
        sudo apt-get update
        sudo apt-get install -y et
    else
        echo "  non-Ubuntu detected — install et from the Debian repo:"
        echo "  https://github.com/MisterTea/EternalTerminal#debian"
    fi
fi

# ── JetBrains Mono Nerd Font ─────────────────────────────────────
FONT_DIR="$HOME/.local/share/fonts"
if [ ! -f "$FONT_DIR/JetBrainsMonoNerdFont-Regular.ttf" ]; then
    echo "Installing JetBrains Mono Nerd Font..."
    mkdir -p "$FONT_DIR"
    curl -fsSL -o /tmp/JetBrainsMono.tar.xz \
        https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz
    tar -xf /tmp/JetBrainsMono.tar.xz -C "$FONT_DIR"
    rm /tmp/JetBrainsMono.tar.xz
    fc-cache -fv
fi
