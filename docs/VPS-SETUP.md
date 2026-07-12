# VPS Bootstrap

Standing up a fresh dev server from zero. Follow top to bottom; each risky step
has a **verify** before you trust it. Target: **Ubuntu 24.04 LTS, amd64, ≥8 GB RAM**
(Hetzner / DigitalOcean).

Legend: 🖥️ = run on the VPS · 💻 = run on your Mac.

---

## Before you start

- Provision **Ubuntu 24.04 LTS (amd64)** and add your SSH **public** key during creation.
- **Know your rescue path first:** Hetzner dashboard → your server → **Console** (web VNC) logs you in even if SSH is completely broken. This is your safety net for every SSH change below — never edit `sshd` without it in your back pocket.
- **Golden rule:** when changing SSH, keep your current session open and verify a **new** connection works in a **second** terminal before closing the first.

---

## 0. 💻 Push your dotfiles

The VPS clones from GitHub, so your latest commits must be pushed:
```bash
cd ~/Documents/dotfiles && git push origin main
```

## 1. 🖥️ First login + a non-root user

```bash
ssh root@<VPS_IP>                       # the key you added at provisioning
apt update && apt -y upgrade

adduser --gecos "" tarek                 # your dev user
usermod -aG sudo tarek
rsync -a --chown=tarek:tarek /root/.ssh /home/tarek/   # reuse your key
```
**Verify** (new terminal, keep root open):
```bash
ssh tarek@<VPS_IP>                       # must succeed before continuing
```

## 2. 🖥️ Base environment (as `tarek`)

Installs nvim, tmux, zsh, node (fnm), **Docker**, Eternal Terminal, fonts, and stows all configs:
```bash
sudo apt install -y git
git clone https://github.com/emeraldtarek/dotfiles.git ~/.dotfiles
cd ~/.dotfiles && ./install.sh
exec zsh
```
> Private repo? `gh auth login` first. `install.sh` is idempotent.

## 3. 🖥️ Verify Docker

```bash
newgrp docker                            # apply the docker group now (or log out/in)
docker run --rm hello-world
docker compose version
```

## 4. 🖥️ Harden SSH onto 443

```bash
cd ~/.dotfiles && sudo ./scripts/vps-harden.sh
```
The script validates the config (`sshd -t`), switches sshd to the classic daemon so `Port` actually applies, and prints **`✓ sshd listening on 22 + 443`**. If it doesn't, stop and read the error — don't close your session.

**Verify from your Mac** (new terminal, keep the VPS session open):
```bash
ssh -p 443 tarek@<VPS_IP>                # must succeed
```
If 443 is refused but `ssh -p 22` works, it's almost always **your Mac's network** (VPN / Cloudflare WARP / corporate proxy intercepting 443) — not the VPS. See Troubleshooting.

## 5. 🖥️ Claude Code

```bash
npm i -g @anthropic-ai/claude-code
claude                                    # /login → opens an auth URL
# optional: cd ~/.dotfiles && make mcp    # merge your MCP servers
```

## 6. 💻 Wire up the Mac client

```bash
cd ~/Documents/dotfiles && ./install.sh   # installs ET (brew), stows ssh pkg, makes ~/.ssh/config.local
nvim ~/.ssh/config.local
```
```sshconfig
Host dev
    HostName <VPS_IP>
    User tarek
```
(`Port 443` + ControlMaster come from `~/.ssh/config.d/dev.conf`.) Test all three:
```bash
ssh dev          # plain SSH over 443
dev              # Eternal Terminal (resilient)
dev-forward      # auto port-forwarder (leave running in a spare tab)
```

## 7. ✅ Test the loop

🖥️ On the VPS (inside `dev`):
```bash
mkdir -p ~/projects && ts demo -d ~/projects
npx create-next-app@latest app && cd app && npm run dev
```
💻 With `dev-forward` running, open **http://localhost:3000** — the VPS app on your local browser. Edit in nvim on the VPS; HMR updates locally. Done.

### Pasting screenshots into Claude Code

Claude Code runs on the VPS, so a terminal `⌘V` only sends **text** — it can't reach your Mac's clipboard image. But Claude Code *reads images by path*, so bridge the clipboard to a file on the VPS:

💻 Screenshot to the clipboard (`⌘⇧⌃4`), then:
```bash
clip             # ships the clipboard image to dev:~/.clip/ and copies the remote path
```
Now `⌘V` in Claude Code pastes `/home/tarek/.clip/clip-….png` — hit Enter and Claude reads it. Needs `pngpaste` on the Mac (in the Brewfile; `brew install pngpaste`). The image rides the existing `dev` SSH master, so it's instant.

## 8. 🖥️ (Optional) Public URLs — webhooks / mobile / demos

Needs a domain on Cloudflare:
```bash
cd ~/.dotfiles && ./scripts/vps-tunnel.sh your-zone.com
# then add the one Cloudflare Access app it prints
```
→ `https://p3000.dev.your-zone.com` (auth'd to your email) · `https://hooks.your-zone.com` (webhooks).

## 9. 🖥️ Lock down (only after 443 + key login are confirmed)

```bash
echo -e 'PermitRootLogin no\nPasswordAuthentication no' | sudo tee /etc/ssh/sshd_config.d/99-lockdown.conf
sudo sshd -t && sudo systemctl restart ssh
```
**Verify a fresh `ssh dev` works before closing your session.**

---

## Troubleshooting

| Symptom | Most likely cause | Fix |
|---------|-------------------|-----|
| `ssh -p 443` refused, but `:443` **is** listening on the VPS (`sudo ss -tlnp \| grep :443`) | **Your Mac's network** — VPN / Cloudflare WARP / proxy intercepting 443 | Disable VPN/WARP (`ifconfig \| grep utun`); test from phone hotspot — if it works there, it's your laptop's network |
| **All** ports refused, but your existing session stays alive | Mac VPN came up after you connected, **or** sshd not accepting new conns | Kill VPN/WARP; if VPS-side, get in via **Hetzner Console** and `sudo systemctl restart ssh` |
| `vps-harden.sh` prints `✗ 443 NOT listening` | sshd failed to bind/restart | `sudo journalctl -u ssh -n 30`; check `sudo sshd -t` |
| Locked out entirely | — | **Hetzner Console** → log in → fix `sshd` → `sudo systemctl restart ssh` |
| `ssh dev` (22/443) works but `dev` (ET) doesn't | port 2022 blocked or etserver down | `systemctl status et` on the VPS; ensure 2022 reachable (no provider firewall) |
| `fwd` / `dev-forward` show nothing | server not bound to a port in 3000–9999, or app on `127.0.0.1` only | confirm with `ss -tlnp` on the VPS; widen the range: `dev-forward dev 1000 9999` |

**The #1 lesson from setup:** `Connection refused` means your packet *reached* something that said no — it's rarely the firewall (those time out). When 443 *and* 22 both refuse from your Mac while your session lives, suspect your **laptop's VPN/WARP first**, the VPS second.
