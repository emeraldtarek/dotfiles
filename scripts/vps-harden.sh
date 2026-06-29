#!/bin/bash
# Run ON THE VPS (needs sudo). Makes the box reachable from restrictive/travel
# networks and confirms the Eternal Terminal server is up.
#
#   1. sshd listens on 443 *as well as* 22 (handles both classic sshd and the
#      socket-activated ssh.socket used on Ubuntu 22.10+, where Port in
#      sshd_config is ignored).
#   2. firewall (ufw) opens 22, 443, and 2022 (Eternal Terminal).
#   3. etserver enabled + running on :2022.
#
# Idempotent — safe to re-run.
set -e

echo "→ sshd: add :443 listener (keep :22)…"
# Detect socket-activated ssh (Ubuntu 22.10+): is-active is reliable here,
# is-enabled can report "alias"/non-zero even when the socket owns the ports.
if systemctl is-active --quiet ssh.socket; then
    # Socket-activated ssh (Ubuntu 22.10+): Port in sshd_config is ignored.
    sudo mkdir -p /etc/systemd/system/ssh.socket.d
    sudo tee /etc/systemd/system/ssh.socket.d/99-remote-dev.conf >/dev/null <<'EOF'
[Socket]
ListenStream=
ListenStream=22
ListenStream=443
EOF
    sudo systemctl daemon-reload
    sudo systemctl restart ssh.socket
    echo "  via ssh.socket"
else
    sudo tee /etc/ssh/sshd_config.d/99-remote-dev.conf >/dev/null <<'EOF'
# Remote-dev: listen on 443 too, for restrictive/captive networks
Port 22
Port 443
EOF
    sudo systemctl restart ssh 2>/dev/null || sudo systemctl restart sshd
    echo "  via sshd_config.d"
fi

echo "→ firewall…"
if command -v ufw &>/dev/null; then
    sudo ufw allow 22/tcp   >/dev/null
    sudo ufw allow 443/tcp  >/dev/null
    sudo ufw allow 2022/tcp >/dev/null   # Eternal Terminal
    echo "  ufw: opened 22, 443, 2022"
else
    echo "  ufw not present — open 22/443/2022 in your provider's firewall"
fi

echo "→ Eternal Terminal server…"
if command -v etserver &>/dev/null; then
    sudo systemctl enable --now et >/dev/null 2>&1 || true
    systemctl is-active et >/dev/null 2>&1 && echo "  et server active on :2022" \
        || echo "  et installed but service inactive — check: systemctl status et"
else
    echo "  etserver missing — run scripts/linux.sh first (installs et)"
fi

echo
echo "Done. From your Mac:"
echo "  ssh -p 443 <user>@<vps>      # verify 443 works"
echo "  fill ~/.ssh/config.local, then:  dev   (et) ·  dev-forward   (auto port-forward)"
