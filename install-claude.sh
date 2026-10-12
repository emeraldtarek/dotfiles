#!/bin/bash
# Stow only the Claude config (claude/.claude/*) into an arbitrary Claude
# config dir, e.g. one used via CLAUDE_CONFIG_DIR.
#
# Usage: ./install-claude.sh <claude-dir>
#   ./install-claude.sh .claude-el        → ~/.claude-el
#   ./install-claude.sh /abs/path/.claude → /abs/path/.claude

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <claude-dir>   (e.g. .claude-el → \$HOME/.claude-el)" >&2
    exit 1
fi

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

case "$1" in
    /*) TARGET="$1" ;;
    *)  TARGET="$HOME/$1" ;;
esac
TARGET="${TARGET%/}"

# Stow dir is claude/, package is .claude → its contents land directly in $TARGET
STOW_ARGS=(--dir="$DOTFILES_DIR/claude" --target="$TARGET" --ignore='\.DS_Store' --ignore='\.gitkeep')

# Pre-create so stow links contents rather than folding the dir itself
# (skills/ too, so sync-profile.sh can unlink single skills)
mkdir -p "$TARGET/skills"

echo "Stowing claude → $TARGET"

# Back up existing files that would conflict with stow
# Handles both stow formats:
#   "existing target is neither a link nor a directory: FILE"
#   "cannot stow SRC over existing target FILE since ..."
for f in $(stow --no --verbose "${STOW_ARGS[@]}" .claude 2>&1 \
        | sed -nE 's/.*over existing target (.+) since .*/\1/p; s/.*existing target is [^:]*: (.+)$/\1/p'); do
    if [ -e "$TARGET/$f" ] && [ ! -L "$TARGET/$f" ]; then
        echo "  backing up $TARGET/$f → $TARGET/${f}.backup"
        mv "$TARGET/$f" "$TARGET/${f}.backup"
    fi
done

stow --restow "${STOW_ARGS[@]}" .claude
echo "  stowed claude"

if [ ! -f "$TARGET/settings.local.json" ]; then
    cat > "$TARGET/settings.local.json" <<'EOF'
{
  "permissions": {
    "allow": []
  }
}
EOF
    echo "Created $TARGET/settings.local.json template"
fi

# ── MCP servers + internal-tooling overlaps ────────────────────────
# User-scope MCP servers live in $CLAUDE_CONFIG_DIR/.claude.json. Merge ours
# in (repo definitions win on name clashes; other servers are kept), then
# apply CLAUDE_TOOLING_PREFER to what the internal-tooling plugin also ships.
if ! command -v jq &> /dev/null; then
    echo "Skipping MCP servers (jq not installed)"
else
    bash "$DOTFILES_DIR/claude/scripts/sync-profile.sh" "$TARGET"
fi

echo ""
echo "Done! Use with: CLAUDE_CONFIG_DIR=\"$TARGET\" claude"
