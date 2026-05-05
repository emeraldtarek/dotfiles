#!/usr/bin/env bash
# Refresh vendored skills under claude/.claude/skills/ from upstream sources
# declared in scripts/skills-sources.tsv.
#
# Usage:
#   ./scripts/update-skills.sh             # refresh all
#   ./scripts/update-skills.sh mcp-builder # refresh one (matches dest column)

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
manifest="$repo_root/scripts/skills-sources.tsv"
skills_dir="$repo_root/.claude/skills"
filter="${1:-}"

command -v rsync >/dev/null || { echo "rsync required" >&2; exit 1; }
command -v git   >/dev/null || { echo "git required"   >&2; exit 1; }

[[ -f "$manifest" ]] || { echo "manifest not found: $manifest" >&2; exit 1; }

if [[ -n "$filter" ]]; then
  echo "This will update skill '$filter' from upstream (overwrites local edits)."
else
  echo "This will update ALL vendored skills from upstream (overwrites local edits)."
fi
read -rp "Type 'yes' to continue: " reply
if [[ "$reply" != "yes" ]]; then
  echo "aborted."
  exit 0
fi

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

updated=0; skipped=0; failed=0; matched=0

while IFS=$'\t' read -r repo ref subpath dest || [[ -n "${repo:-}" ]]; do
  [[ -z "${repo:-}" || "$repo" =~ ^[[:space:]]*# ]] && continue

  if [[ -z "${dest:-}" || -z "${ref:-}" || -z "${subpath:-}" ]]; then
    echo "✗ malformed row (need 4 tab-separated columns): $repo" >&2
    failed=$((failed+1))
    continue
  fi

  if [[ ! "$dest" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "✗ invalid dest '$dest' (alphanumerics, dot, dash, underscore only)" >&2
    failed=$((failed+1))
    continue
  fi

  if [[ -n "$filter" && "$dest" != "$filter" ]]; then
    skipped=$((skipped+1))
    continue
  fi
  matched=$((matched+1))

  echo "→ $dest  ($repo @ $ref ⇐ $subpath)"

  workdir="$tmp_root/$dest"
  if ! git clone --depth 1 --branch "$ref" --quiet "$repo" "$workdir" 2>/dev/null; then
    rm -rf "$workdir"
    if ! git clone --quiet "$repo" "$workdir"; then
      echo "  ✗ clone failed" >&2
      failed=$((failed+1))
      continue
    fi
    if ! git -C "$workdir" checkout --quiet "$ref"; then
      echo "  ✗ checkout '$ref' failed" >&2
      failed=$((failed+1))
      continue
    fi
  fi

  src="$workdir/$subpath"
  if [[ ! -d "$src" ]]; then
    echo "  ✗ subpath '$subpath' not found in repo" >&2
    failed=$((failed+1))
    continue
  fi

  sha="$(git -C "$workdir" rev-parse --short HEAD)"
  mkdir -p "$skills_dir/$dest"
  rsync -a --delete --exclude='.git' "$src/" "$skills_dir/$dest/"
  echo "  ✓ synced @ $sha"
  updated=$((updated+1))
done < "$manifest"

if [[ -n "$filter" && $matched -eq 0 ]]; then
  echo "no manifest row matched '$filter'" >&2
  exit 1
fi

echo
echo "updated: $updated   skipped: $skipped   failed: $failed"
[[ $failed -eq 0 ]]
