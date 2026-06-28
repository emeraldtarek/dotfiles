#!/bin/bash
# Run ON THE VPS. Stands up the public-URL layer: Caddy (subdomain → localhost
# port router) behind a Cloudflare named tunnel (outbound-only, no inbound
# ports). Secondary to the SSH-localhost path — for webhooks, mobile, demos.
#
#   ./scripts/vps-tunnel.sh <your-zone.com>
#
# Result:
#   https://p3000.dev.<zone>      → localhost:3000   (any port, zero config)
#   https://<name>.dev.<zone>     → named routes you add in /etc/caddy/named.caddy
#   https://hooks.<zone>          → webhook target (no Access; verify signatures)
#
# Idempotent — safe to re-run. Interactive once: cloudflared opens a browser
# login URL you authorize from any device.
set -euo pipefail

ZONE="${1:-${DEV_ZONE:-}}"
if [ -z "$ZONE" ]; then echo "usage: $0 <your-zone.com>   (or set DEV_ZONE)"; exit 1; fi
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USER_NAME="$(id -un)"
CFDIR="$HOME/.cloudflared"
echo "Zone: $ZONE   ·   user: $USER_NAME"

# ── 1. Install Caddy ──────────────────────────────────────────────
if ! command -v caddy &>/dev/null; then
    echo "Installing Caddy..."
    sudo apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
        | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
        | sudo tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
    sudo apt-get update && sudo apt-get install -y caddy
fi

# ── 2. Install cloudflared ────────────────────────────────────────
if ! command -v cloudflared &>/dev/null; then
    echo "Installing cloudflared..."
    sudo mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
        | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" \
        | sudo tee /etc/apt/sources.list.d/cloudflared.list >/dev/null
    sudo apt-get update && sudo apt-get install -y cloudflared
fi

# ── 3. Deploy Caddy config ────────────────────────────────────────
echo "Deploying Caddyfile..."
sudo cp "$DOTFILES_DIR/caddy/Caddyfile" /etc/caddy/Caddyfile
if [ ! -f /etc/caddy/named.caddy ]; then
    sudo tee /etc/caddy/named.caddy >/dev/null <<EOF
# Named routes — pretty URLs for specific projects.
# After editing:  sudo systemctl reload caddy
#
# @adadvisor host adadvisor.dev.$ZONE
# handle @adadvisor {
#     reverse_proxy 127.0.0.1:3000
# }
#
# Webhooks (keep this host OUT of Cloudflare Access — verify signatures in-app):
# @hooks host hooks.$ZONE
# handle @hooks {
#     reverse_proxy 127.0.0.1:3000
# }
EOF
fi
sudo systemctl reload caddy 2>/dev/null || sudo systemctl restart caddy
echo "  caddy: $(systemctl is-active caddy)"

# ── 4. Cloudflare login (once) ────────────────────────────────────
if [ ! -f "$CFDIR/cert.pem" ]; then
    echo "→ Authorize cloudflared in your browser (URL below), pick zone $ZONE:"
    cloudflared tunnel login
fi

# ── 5. Create the tunnel (idempotent) ─────────────────────────────
if ! cloudflared tunnel list 2>/dev/null | awk '{print $2}' | grep -qx dev; then
    echo "Creating tunnel 'dev'..."
    cloudflared tunnel create dev
fi
TUNNEL_ID="$(cloudflared tunnel list | awk '$2=="dev"{print $1}')"
echo "  tunnel id: $TUNNEL_ID"

# ── 6. Write ingress config ───────────────────────────────────────
echo "Writing $CFDIR/config.yml..."
cat > "$CFDIR/config.yml" <<EOF
tunnel: dev
credentials-file: $CFDIR/$TUNNEL_ID.json
ingress:
  - hostname: hooks.$ZONE
    service: http://localhost:8080
  - hostname: "*.dev.$ZONE"
    service: http://localhost:8080
  - service: http_status:404
EOF

# ── 7. DNS routes (wildcard + hooks) ──────────────────────────────
echo "Routing DNS..."
cloudflared tunnel route dns dev "*.dev.$ZONE" \
    || echo "  ! wildcard route failed — add a proxied CNAME '*.dev' → $TUNNEL_ID.cfargotunnel.com in the dashboard"
cloudflared tunnel route dns dev "hooks.$ZONE" \
    || echo "  ! hooks route failed — add a proxied CNAME 'hooks' → $TUNNEL_ID.cfargotunnel.com"

# ── 8. Run the tunnel as a systemd service ────────────────────────
echo "Installing cloudflared-dev.service..."
sudo tee /etc/systemd/system/cloudflared-dev.service >/dev/null <<EOF
[Unit]
Description=cloudflared tunnel (dev)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER_NAME
ExecStart=/usr/bin/cloudflared tunnel --no-autoupdate --config $CFDIR/config.yml run dev
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now cloudflared-dev
echo "  cloudflared-dev: $(systemctl is-active cloudflared-dev)"

# ── 9. Next: Cloudflare Access (manual, one-time) ─────────────────
cat <<EOF

✓ Tunnel + Caddy up. Test:  npm run dev  on the VPS, then open https://p3000.dev.$ZONE

Lock it down — Cloudflare Zero Trust dashboard (one Access app):
  Access → Applications → Add → Self-hosted
    • Application domain:  *.dev.$ZONE
    • Policy: Allow → Include → Emails → tarek.kekhia@emeraldlake.io
  Save.  Do NOT add an app for hooks.$ZONE (webhooks must stay public).

Now https://p3000.dev.$ZONE asks for your email; hooks.$ZONE is open for callbacks.
EOF
