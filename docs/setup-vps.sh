#!/usr/bin/env bash
#
# setup-vps.sh — make the Claude Code *interactive TUI* start authenticated on a
# headless VPS, using a long-lived subscription OAuth token (sk-ant-oat01-...).
#
# WHY THIS IS NEEDED
#   `claude -p` reads CLAUDE_CODE_OAUTH_TOKEN, but the TUI decides "am I logged
#   in?" by looking for a claudeAiOauth credential on disk (Keychain on macOS,
#   ~/.claude/.credentials.json on Linux). On a fresh VPS that file doesn't
#   exist, so the TUI drops to the "Select login method" screen. This script
#   seeds that credential from your token + marks onboarding complete.
#
# GET A TOKEN (on a machine with a browser — your Mac):
#   claude setup-token          # prints sk-ant-oat01-...  (valid ~1 year)
#
# USAGE (run ON the VPS):
#   export CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...
#   ./setup-vps.sh                 # set up, then launch claude
#   ./setup-vps.sh --no-launch     # set up only
#   ./setup-vps.sh sk-ant-oat01-...# pass the token as an argument instead
#
# OPTIONAL ENV:
#   CLAUDE_SUB_TYPE=max|pro        # your plan (default: max)
#   CLAUDE_ONBOARD_VERSION=2.1.207 # match/exceed the installed claude version
#   # Identity block is optional (auth works without it). To include it, export:
#   CLAUDE_ACCOUNT_UUID  CLAUDE_ORG_UUID  CLAUDE_EMAIL  [CLAUDE_ORG_TYPE]
#   # Keep those in an *untracked* file (e.g. ~/.claude-identity.env) — never commit them.
#
# NOTE: the token expires ~1 year after `claude setup-token`. When it dies you
# get 401s (no warning, by design). Regenerate on your Mac and re-run this.
#
set -euo pipefail

# ---------- options ----------
SUB_TYPE="${CLAUDE_SUB_TYPE:-max}"
ONBOARD_VERSION="${CLAUDE_ONBOARD_VERSION:-2.1.207}"
LAUNCH=1
if [ "${1:-}" = "--no-launch" ]; then LAUNCH=0; shift || true; fi

# ---------- token ----------
TOKEN="${CLAUDE_CODE_OAUTH_TOKEN:-${1:-}}"
if [ -z "$TOKEN" ]; then
  echo "ERROR: no token found." >&2
  echo "  export CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...   then re-run" >&2
  echo "  (or)  ./setup-vps.sh sk-ant-oat01-..." >&2
  exit 1
fi
case "$TOKEN" in
  sk-ant-oat01-*) : ;;
  *) echo "WARN: token doesn't look like an sk-ant-oat01- token (make one with 'claude setup-token')." >&2 ;;
esac

CLAUDE_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_DIR"

# ---------- 1. credential file (what the TUI checks) ----------
CRED="$CLAUDE_DIR/.credentials.json"
if [ -f "$CRED" ]; then cp "$CRED" "$CRED.bak.$$"; echo "backed up existing credentials -> $CRED.bak.$$"; fi
printf '{"claudeAiOauth":{"accessToken":"%s","refreshToken":"","expiresAt":9999999999999,"scopes":["user:inference","user:profile"],"subscriptionType":"%s"}}\n' \
  "$TOKEN" "$SUB_TYPE" > "$CRED"
chmod 600 "$CRED"
echo "wrote $CRED  (subscriptionType=$SUB_TYPE)"

# ---------- 2. onboarding seed (skip first-run wizard / login selector) ----------
CONF="$HOME/.claude.json"
SEED_TMP="$(mktemp)"
cat > "$SEED_TMP" <<SEEDEOF
{
  "hasCompletedOnboarding": true,
  "lastOnboardingVersion": "$ONBOARD_VERSION",
  "numStartups": 5,
  "hasCompletedClaudeInChromeOnboarding": true
}
SEEDEOF

# optional identity block — only if you exported the vars (kept OUT of the repo)
if [ -n "${CLAUDE_ACCOUNT_UUID:-}" ] && command -v python3 >/dev/null 2>&1; then
  python3 - "$SEED_TMP" <<'PY'
import json, os, sys
p = sys.argv[1]; d = json.load(open(p))
d["oauthAccount"] = {
    "accountUuid":      os.environ.get("CLAUDE_ACCOUNT_UUID", ""),
    "emailAddress":     os.environ.get("CLAUDE_EMAIL", ""),
    "organizationUuid": os.environ.get("CLAUDE_ORG_UUID", ""),
    "organizationType": os.environ.get("CLAUDE_ORG_TYPE", "claude_max"),
}
json.dump(d, open(p, "w"), indent=2)
print("included oauthAccount identity block")
PY
fi

if command -v python3 >/dev/null 2>&1 && [ -f "$CONF" ]; then
  # merge: keep any existing VPS config, seed keys win
  python3 - "$CONF" "$SEED_TMP" <<'PY'
import json, sys
conf, seedp = sys.argv[1], sys.argv[2]
try:    cur = json.load(open(conf))
except Exception: cur = {}
cur.update(json.load(open(seedp)))
json.dump(cur, open(conf, "w"), indent=2)
print("merged onboarding seed into", conf)
PY
else
  [ -f "$CONF" ] && { cp "$CONF" "$CONF.bak.$$"; echo "backed up $CONF -> $CONF.bak.$$"; }
  cp "$SEED_TMP" "$CONF"
  echo "wrote $CONF"
fi
rm -f "$SEED_TMP"
chmod 600 "$CONF"

# ---------- 3. avoid conflicts, then launch ----------
unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN
export CLAUDE_CODE_OAUTH_TOKEN="$TOKEN"
echo "setup complete."

if [ "$LAUNCH" = "1" ]; then
  echo "launching claude..."
  exec claude
else
  echo "now run:  claude"
fi
