#!/usr/bin/env bash
# Merge claude/mcp-servers.json into a Claude profile and settle overlaps with
# the internal-tooling plugin (skills and MCP servers that both ship), per
# CLAUDE_TOOLING_PREFER in ~/.zshrc.local:
#
#   dotfiles          (default) keep the dotfiles copies. Claude Code already
#                     skips plugin MCP servers that share an endpoint with one of
#                     yours; the plugin's skills still list as internal-tooling:<name>.
#   internal-tooling  drop the dotfiles copies from the profile so the plugin's
#                     are used. The plugin's secret options are seeded from the
#                     matching env vars (trello_token ← TRELLO_TOKEN). An MCP server
#                     whose plugin copy still lacks options keeps its dotfiles copy.
#
# Run after stowing (the installers and `make restow` do). Usage:
#   sync-profile.sh [claude-dir]   # default ~/.claude

set -euo pipefail

claude_root="$(cd "$(dirname "$0")/.." && pwd)"
skills_src="$claude_root/.claude/skills"
mcp_src="$claude_root/mcp-servers.json"
plugin_id="internal-tooling@adadvisor-internal"
zshrc_local="$HOME/.zshrc.local"

command -v jq >/dev/null || { echo "jq required" >&2; exit 1; }

config_dir="${1:-$HOME/.claude}"
config_dir="${config_dir%/}"
# The default profile keeps its global config next to the dir, not inside it.
if [[ "$config_dir" == "$HOME/.claude" ]]; then
  claude_json="$HOME/.claude.json"
  claude_cmd=(env -u CLAUDE_CONFIG_DIR claude)
else
  claude_json="$config_dir/.claude.json"
  claude_cmd=(env CLAUDE_CONFIG_DIR="$config_dir" claude)
fi

# ── Preference ─────────────────────────────────────────────────────
touch "$zshrc_local"
if ! grep -q '^export CLAUDE_TOOLING_PREFER=' "$zshrc_local"; then
  cat >> "$zshrc_local" <<'EOF'

# Which copy wins when dotfiles and the internal-tooling Claude plugin ship the
# same skill or MCP server: dotfiles | internal-tooling. Re-run the installer
# (make restow / ./install-claude.sh <dir>) after changing it.
export CLAUDE_TOOLING_PREFER=dotfiles
EOF
  echo "Added CLAUDE_TOOLING_PREFER=dotfiles to $zshrc_local"
fi
file_pref="$(sed -n 's/^export CLAUDE_TOOLING_PREFER=//p' "$zshrc_local" | tail -1 | tr -d "\"'")"
pref="${CLAUDE_TOOLING_PREFER:-${file_pref:-dotfiles}}"
if [[ -n "${CLAUDE_TOOLING_PREFER:-}" && -n "$file_pref" && "$CLAUDE_TOOLING_PREFER" != "$file_pref" ]]; then
  echo "note: this shell has CLAUDE_TOOLING_PREFER=$CLAUDE_TOOLING_PREFER but $zshrc_local says $file_pref (source it to switch)"
fi
case "$pref" in
  dotfiles|internal-tooling) ;;
  *) echo "CLAUDE_TOOLING_PREFER must be 'dotfiles' or 'internal-tooling', got '$pref'" >&2; exit 1 ;;
esac

plugin_dir="$(jq -r --arg id "$plugin_id" \
  '.plugins[$id] // [] | map(select(.scope == "user")) | .[0].installPath // empty' \
  "$config_dir/plugins/installed_plugins.json" 2>/dev/null || true)"
plugin_enabled="$(jq -r --arg id "$plugin_id" '.enabledPlugins[$id] // false' \
  "$config_dir/settings.json" 2>/dev/null || echo false)"
if [[ -z "$plugin_dir" || ! -d "$plugin_dir" || "$plugin_enabled" != true ]]; then
  if [[ "$pref" == internal-tooling ]]; then
    echo "warning: $plugin_id isn't installed and enabled in $config_dir; keeping dotfiles copies."
    echo "  CLAUDE_CONFIG_DIR=$config_dir claude plugin install $plugin_id"
    pref=dotfiles
  fi
  plugin_dir=""
fi
echo "Claude profile $config_dir: preferring $pref"

# ── MCP servers ────────────────────────────────────────────────────
# Dotfiles servers the plugin also ships (same name or same endpoint), one per
# line: name, same|differs (endpoint), user_config keys the plugin's copy uses.
overlap=""
if [[ -n "$plugin_dir" && -f "$plugin_dir/.mcp.json" ]]; then
  overlap="$(jq -r -s '
    def endpoint: if .url then "url:" + (.url | ascii_downcase | rtrimstr("/"))
                  else "cmd:" + ([.command] + (.args // []) | join(" ")) end;
    (.[1].mcpServers // {}) as $plugin
    | .[0] | to_entries[]
    | .key as $name | (.value | endpoint) as $ep
    | [$plugin | to_entries[] | select(.key == $name or (.value | endpoint) == $ep)][0]
    | select(.)
    | [$name,
       (if (.value | endpoint) == $ep then "same" else "differs" end),
       ([.value | .. | strings | scan("\\$\\{user_config\\.([A-Za-z0-9_]+)\\}")[0]] | unique | join(","))]
    | @tsv' "$mcp_src" "$plugin_dir/.mcp.json")"
fi

drop=()
kept=()
if [[ "$pref" == internal-tooling && -n "$overlap" ]]; then
  # Seed only secret options: they go to the OS keychain. Non-secret ones are
  # saved in settings.json, which is this (public) repo, so set those yourself
  # with /plugin configure if you want them.
  secret_keys="$(jq -r '.userConfig // {} | to_entries[] | select(.value.sensitive) | .key' \
    "$plugin_dir/.claude-plugin/plugin.json")"
  seed=()
  for key in $(cut -f3 <<<"$overlap" | tr ',' '\n' | sort -u); do
    env_name="$(tr '[:lower:]' '[:upper:]' <<<"$key")"
    if [[ -n "${!env_name:-}" ]] && grep -qx "$key" <<<"$secret_keys"; then
      seed+=("$key")
    fi
  done
  if ((${#seed[@]})); then
    # Values come from jq's env, never from argv.
    if jq -n '[$ARGS.positional[] | {(.): env[ascii_upcase]}] | add' --args "${seed[@]}" \
        | "${claude_cmd[@]}" plugin configure "$plugin_id" --values-stdin >/dev/null; then
      echo "  seeded plugin options from env: ${seed[*]}"
    else
      echo "warning: couldn't seed plugin options (${seed[*]})"
    fi
  fi

  configured="$("${claude_cmd[@]}" plugin configure "$plugin_id" --json | jq -r '.configured[]' || true)"
  while IFS=$'\t' read -r name _ keys; do
    missing=()
    for key in ${keys//,/ }; do
      grep -qx "$key" <<<"$configured" || missing+=("$key")
    done
    if ((${#missing[@]})); then
      kept+=("$name (plugin needs ${missing[*]})")
    else
      drop+=("$name")
    fi
  done <<<"$overlap"
fi

[[ -f "$claude_json" ]] || echo '{}' > "$claude_json"
jq -n --slurpfile cur "$claude_json" --slurpfile dot "$mcp_src" '
  def keep: with_entries(select(.key | IN($ARGS.positional[]) | not));
  $cur[0] | .mcpServers = (((.mcpServers // {}) * ($dot[0] | keep)) | keep)
' --args ${drop[@]+"${drop[@]}"} > "$claude_json.tmp"
chmod 600 "$claude_json.tmp"
mv "$claude_json.tmp" "$claude_json"
echo "  merged MCP servers into $claude_json"

if [[ "$pref" == internal-tooling ]]; then
  ((${#drop[@]})) && echo "  MCP from plugin: ${drop[*]}"
  for k in ${kept[@]+"${kept[@]}"}; do echo "  MCP kept from dotfiles: $k"; done
elif [[ -n "$overlap" ]]; then
  echo "  MCP from dotfiles: $(cut -f1 <<<"$overlap" | xargs)"
  differs="$(awk -F'\t' '$2 == "differs" { print $1 }' <<<"$overlap" | xargs)"
  [[ -n "$differs" ]] && echo "    plugin's copy also loads (different endpoint): $differs"
fi

# ── Skills ─────────────────────────────────────────────────────────
skill_overlap=()
if [[ -n "$plugin_dir" && -d "$plugin_dir/skills" ]]; then
  for d in "$skills_src"/*/; do
    name="$(basename "$d")"
    [[ -d "$plugin_dir/skills/$name" ]] && skill_overlap+=("$name")
  done
fi
((${#skill_overlap[@]})) || exit 0

if [[ "$pref" == internal-tooling ]]; then
  if [[ -L "$config_dir/skills" ]]; then
    echo "warning: $config_dir/skills is a single symlink into dotfiles, so single skills can't be dropped."
    echo "  rm $config_dir/skills and re-run the installer to link skills one by one."
    exit 0
  fi
  removed=()
  for name in "${skill_overlap[@]}"; do
    link="$config_dir/skills/$name"
    # Only remove links stow made into this repo, never real directories.
    if [[ -L "$link" && "$(cd "$link" && pwd -P)" == "$(cd "$skills_src/$name" && pwd -P)" ]]; then
      rm "$link"
    fi
    [[ -e "$link" ]] || removed+=("$name")
  done
  echo "  skills from plugin: ${removed[*]-}"
else
  missing=()
  for name in "${skill_overlap[@]}"; do
    [[ -e "$config_dir/skills/$name" ]] || missing+=("$name")
  done
  echo "  skills from dotfiles: ${skill_overlap[*]}"
  ((${#missing[@]})) && echo "    not linked yet, re-run the installer to stow them: ${missing[*]}"
fi
exit 0
