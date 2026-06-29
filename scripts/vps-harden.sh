#!/bin/bash
# Run ON THE VPS (needs sudo). Makes the box reachable from restrictive/travel
# networks and confirms the Eternal Terminal server is up.
#
#   1. sshd listens on 443 *as well as* 22 (classic daemon — Ubuntu 24.04 ships
#      ssh socket-activated, where the Port directive is ignored; we disable the
#      socket so Port takes effect deterministically).
#   2. firewall (ufw) opens 22, 443, and 2022 (Eternal Terminal) when active.
#   3. etserver enabled + running on :2022.
#
# Idempotent — safe to re-run.
set -e

echo "→ sshd: listen on 22 + 443…"
# Add 443 alongside 22 via the *classic* sshd daemon. Ubuntu 24.04 ships ssh
# socket-activated, where `Port` in sshd_config is IGNORED (systemd owns the
# sockets) — exactly the subtlety that bites people. Disable the socket and run
# the normal daemon so `Port` is deterministic and identical on Ubuntu/Debian.
sudo tee /etc/ssh/sshd_config.d/99-remote-dev.conf >/dev/null <<'EOF'
# Remote-dev: SSH on 22 and 443 (443 slips through restrictive networks)
Port 22
Port 443
EOF

# Never restart into a broken config — that's how you lock yourself out.
sudo sshd -t

if systemctl cat ssh.socket &>/dev/null; then
    echo "  disabling socket activation so Port directives apply…"
    sudo systemctl disable --now ssh.socket 2>/dev/null || true
fi
sudo systemctl enable ssh &>/dev/null || true
sudo systemctl restart ssh 2>/dev/null || sudo systemctl restart sshd

# Verify before trusting it.
if sudo ss -tlnp 2>/dev/null | grep -qE ':443\b'; then
    echo "  ✓ sshd listening on 22 + 443"
else
    echo "  ✗ 443 NOT listening — inspect: sudo journalctl -u ssh -n 30"
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
