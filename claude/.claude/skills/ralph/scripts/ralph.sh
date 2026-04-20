#!/usr/bin/env bash
set -eo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# RALPH — AFK Docker Sandbox Loop
# Usage: ralph <init|run|cleanup> [options]
# ──────────────────────────────────────────────────────────────────────────────

RALPH_SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RALPH_IMAGE="ralph-sandbox:v1"
COMPLETION_TAG='<promise>COMPLETE</promise>'

# ── Derived from current repo ────────────────────────────────────────────────

repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || { echo "Error: not inside a git repo." >&2; exit 1; }
}

sandbox_name() {
  echo "ralph-$(basename "$(repo_root)")"
}

# ── Resolve with cascade: per-project (.sandcastle/) → global (skill dir) ───

resolve_dockerfile() {
  local root
  root="$(repo_root)"
  if [ -f "$root/.sandcastle/Dockerfile" ]; then
    echo "$root/.sandcastle/Dockerfile"
  else
    echo "$RALPH_SKILL_DIR/docker/Dockerfile"
  fi
}

resolve_prompt() {
  local root
  root="$(repo_root)"
  if [ -f "$root/.sandcastle/prompt.md" ]; then
    echo "$root/.sandcastle/prompt.md"
  else
    echo "$RALPH_SKILL_DIR/prompt.md"
  fi
}

resolve_iterations() {
  local root
  root="$(repo_root)"
  if [ -f "$root/.sandcastle/config.json" ]; then
    local val
    val=$(jq -r '.defaultIterations // empty' "$root/.sandcastle/config.json" 2>/dev/null)
    if [ -n "$val" ]; then
      echo "$val"
      return
    fi
  fi
  echo "50"
}

# ── Write .env into workspace for the Docker wrapper ─────────────────────────

write_env() {
  local root
  root="$(repo_root)"
  local env_file="$root/.sandcastle/.ralph-env"

  mkdir -p "$root/.sandcastle"

  # Per-project .sandcastle/.env takes precedence
  if [ -f "$root/.sandcastle/.env" ]; then
    cp "$root/.sandcastle/.env" "$env_file"
    return
  fi

  {
    echo "CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN:-}"
    echo "GH_TOKEN=${GH_TOKEN:-}"
  } > "$env_file"
}

cleanup_env() {
  local root
  root="$(repo_root)"
  rm -f "$root/.sandcastle/.ralph-env"
}

# ── Write context files before each iteration ────────────────────────────────

fetch_issues() {
  if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
    gh issue list --state open --label ralph --json number,title,body,comments,labels 2>/dev/null || echo "[]"
  else
    echo "[]"
  fi
}

fetch_commits() {
  git log --grep="RALPH" -n 10 --format="%H%n%ad%n%B---" --date=short 2>/dev/null || echo "No RALPH commits found"
}

# Build context string (issues + commits + optional task file)
build_context() {
  local prompt_file="$1"  # optional, for prompt-driven mode
  local issues commits

  if [ -n "$prompt_file" ]; then
    issues="No issues — working from prompt file. Task: $(cat "$prompt_file")"
  else
    issues="$(fetch_issues)"
  fi

  commits="$(fetch_commits)"

  echo "$issues Previous RALPH commits: $commits"
}

# ══════════════════════════════════════════════════════════════════════════════
# INIT
# ══════════════════════════════════════════════════════════════════════════════

cmd_init() {
  local root
  root="$(repo_root)"
  echo "RALPH init — $(basename "$root")"
  echo "──────────────────────────────────"

  # 1. Check env vars
  local missing=0
  if [ -z "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
    echo "ERROR: CLAUDE_CODE_OAUTH_TOKEN is not set."
    echo "  Add it to ~/.zshrc.local and source it."
    missing=1
  else
    echo "  CLAUDE_CODE_OAUTH_TOKEN ... ok"
  fi

  if [ -z "$GH_TOKEN" ]; then
    echo "WARNING: GH_TOKEN is not set. GitHub issue mode won't work."
    echo "  Add it to ~/.zshrc.local and source it."
  else
    echo "  GH_TOKEN ................. ok"
  fi

  if [ "$missing" -eq 1 ]; then
    exit 1
  fi

  # 2. Check Docker
  if ! command -v docker &>/dev/null; then
    echo "ERROR: docker not found. Install Docker Desktop."
    exit 1
  fi

  if ! docker sandbox ls &>/dev/null; then
    echo "ERROR: 'docker sandbox' not available. Update Docker Desktop to 4.58+."
    exit 1
  fi
  echo "  Docker sandbox ........... ok"

  # 3. Build image if needed
  local dockerfile
  dockerfile="$(resolve_dockerfile)"
  if docker image inspect "$RALPH_IMAGE" &>/dev/null 2>&1; then
    echo "  Image $RALPH_IMAGE ...... exists (skipping build)"
  else
    echo "  Building $RALPH_IMAGE from $(basename "$dockerfile")..."
    docker build -t "$RALPH_IMAGE" -f "$dockerfile" "$(dirname "$dockerfile")"
    echo "  Image built."
  fi

  # 4. Create sandbox if needed
  local name
  name="$(sandbox_name)"
  local _sb_list
  _sb_list="$(docker sandbox ls 2>/dev/null || true)"
  if echo "$_sb_list" | grep -q "$name"; then
    echo "  Sandbox $name ... exists"
  else
    echo "  Creating sandbox $name..."
    write_env
    docker sandbox create -t "$RALPH_IMAGE" --name "$name" claude "$root"
    echo "  Sandbox created."
  fi

  # 5. Scaffold .sandcastle/
  mkdir -p "$root/.sandcastle/logs"
  if [ ! -f "$root/.sandcastle/.gitignore" ]; then
    cat > "$root/.sandcastle/.gitignore" <<'EOF'
.env
.ralph-env
.ralph-prompt.md
logs/
EOF
    echo "  Created .sandcastle/.gitignore"
  fi

  echo ""
  echo "Ready. Run: ralph run"
}

# ══════════════════════════════════════════════════════════════════════════════
# RUN
# ══════════════════════════════════════════════════════════════════════════════

cmd_run() {
  local root name
  root="$(repo_root)"
  name="$(sandbox_name)"

  # Parse flags
  local max_iterations branch quiet=0 prompt_file
  max_iterations="$(resolve_iterations)"

  while [ $# -gt 0 ]; do
    case "$1" in
      --iterations) max_iterations="$2"; shift 2 ;;
      --branch)     branch="$2"; shift 2 ;;
      --quiet)      quiet=1; shift ;;
      --prompt)     prompt_file="$2"; shift 2 ;;
      *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
  done

  # Verify sandbox exists
  local _sb_list
  _sb_list="$(docker sandbox ls 2>/dev/null || true)"
  if ! echo "$_sb_list" | grep -q "$name"; then
    echo "ERROR: Sandbox '$name' not found. Run 'ralph init' first." >&2
    exit 1
  fi

  # Write .env from shell environment
  write_env
  trap 'cleanup_env' EXIT

  # Handle branch
  if [ -n "$branch" ]; then
    if git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
      git checkout "$branch"
      echo "Checked out existing branch: $branch"
    else
      git checkout -b "$branch"
      echo "Created and checked out branch: $branch"
    fi
  fi

  # Copy resolved prompt into workspace so @-reference works inside sandbox
  local prompt_template
  prompt_template="$(resolve_prompt)"
  cp "$prompt_template" "$root/.sandcastle/.ralph-prompt.md"

  # jq filters for stream-json output
  local stream_text='select(.type == "assistant").message.content[]? | select(.type == "text").text // empty | gsub("\n"; "\r\n") | . + "\r\n\n"'
  local final_result='select(.type == "result").result // empty'

  echo "RALPH run — $(basename "$root")"
  echo "  Sandbox:    $name"
  echo "  Iterations: $max_iterations"
  echo "  Mode:       $([ -n "$prompt_file" ] && echo "prompt ($prompt_file)" || echo "github issues")"
  echo "  Branch:     $([ -n "$branch" ] && echo "$branch" || echo "$(git branch --show-current)")"
  echo "  Output:     $([ "$quiet" -eq 1 ] && echo "quiet (logging to .sandcastle/logs/)" || echo "streaming")"
  echo "──────────────────────────────────"

  for ((i=1; i<=max_iterations; i++)); do
    echo ""
    echo "── Iteration $i / $max_iterations ──"

    # Build fresh context (issues + commits)
    local context
    context="$(build_context "$prompt_file")"

    local log_file="$root/.sandcastle/logs/iteration-$(printf '%03d' "$i").log"
    mkdir -p "$root/.sandcastle/logs"

    if [ "$quiet" -eq 1 ]; then
      # Quiet mode: capture output to log, show nothing
      docker sandbox run "$name" -- \
        --verbose \
        --print \
        --output-format stream-json \
        "$context @.sandcastle/.ralph-prompt.md" \
        > "$log_file" 2>&1 || true

      echo "  Logged to $log_file"
    else
      # Streaming mode: show output via jq, save raw json to log
      local tmpfile
      tmpfile=$(mktemp)
      trap "rm -f $tmpfile" EXIT

      docker sandbox run "$name" -- \
        --verbose \
        --print \
        --output-format stream-json \
        "$context @.sandcastle/.ralph-prompt.md" \
      | grep --line-buffered '^{' \
      | tee "$tmpfile" \
      | jq --unbuffered -rj "$stream_text" || true

      cp "$tmpfile" "$log_file"
      rm -f "$tmpfile"

      echo ""
    fi

    # Check for completion promise in the log
    local result
    result=$(jq -r "$final_result" "$log_file" 2>/dev/null || echo "")
    if [[ "$result" == *"$COMPLETION_TAG"* ]]; then
      echo ""
      echo "RALPH complete after $i iteration(s)."
      exit 0
    fi
  done

  echo ""
  echo "RALPH finished $max_iterations iterations (no completion signal)."
}

# ══════════════════════════════════════════════════════════════════════════════
# CLEANUP
# ══════════════════════════════════════════════════════════════════════════════

# Thorough removal of a single sandbox: docker sandbox rm → buildx builder rm → vm dir rm.
# The vm-dir rm acts as a fallback for cases where `docker sandbox rm` silently failed
# (stuck daemon, dead socket) and left behind a ~926GB sparse Docker.raw file.
_ralph_remove_one() {
  local name="$1"
  local vm_dir="$HOME/.docker/sandboxes/vm/$name"

  local _sb_list
  _sb_list="$(docker sandbox ls 2>/dev/null || true)"
  if echo "$_sb_list" | grep -q "^$name\b\|[[:space:]]$name\b"; then
    echo "  [$name] docker sandbox rm"
    docker sandbox rm "$name" 2>/dev/null || echo "    (sandbox rm failed, will force-remove vm dir)"
  fi

  if docker buildx ls 2>/dev/null | grep -q "^$name[[:space:]]"; then
    echo "  [$name] docker buildx rm"
    docker buildx rm "$name" 2>/dev/null || true
  fi

  if [ -d "$vm_dir" ]; then
    echo "  [$name] rm -rf $vm_dir"
    rm -rf "$vm_dir"
  fi
}

# Enumerate every ralph-* sandbox found on disk (VM dir is authoritative — picks up
# orphans that `docker sandbox ls` can no longer see).
_ralph_list_all() {
  local vm_root="$HOME/.docker/sandboxes/vm"
  [ -d "$vm_root" ] || return 0
  find "$vm_root" -maxdepth 1 -mindepth 1 -type d -name 'ralph-*' -exec basename {} \;
}

cmd_cleanup() {
  local remove_image=0 all=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --image) remove_image=1; shift ;;
      --all)   all=1; shift ;;
      *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
  done

  if [ "$all" -eq 1 ]; then
    echo "RALPH cleanup — ALL ralph sandboxes"
    echo "──────────────────────────────────"
    local found=0
    while IFS= read -r name; do
      [ -z "$name" ] && continue
      found=1
      _ralph_remove_one "$name"
    done < <(_ralph_list_all)
    [ "$found" -eq 0 ] && echo "  No ralph-* sandboxes found."
  else
    local root name
    root="$(repo_root)"
    name="$(sandbox_name)"

    echo "RALPH cleanup — $(basename "$root")"
    echo "──────────────────────────────────"
    _ralph_remove_one "$name"

    cleanup_env
    rm -rf "$root/.sandcastle/context" "$root/.sandcastle/logs"
  fi

  if [ "$remove_image" -eq 1 ]; then
    if docker image inspect "$RALPH_IMAGE" &>/dev/null 2>&1; then
      echo "  Removing image '$RALPH_IMAGE'..."
      docker rmi "$RALPH_IMAGE"
    else
      echo "  Image '$RALPH_IMAGE' not found, skipping."
    fi
  fi

  echo ""
  echo "Cleanup complete."
}

# ══════════════════════════════════════════════════════════════════════════════
# STATUS
# ══════════════════════════════════════════════════════════════════════════════

cmd_status() {
  local vm_root="$HOME/.docker/sandboxes/vm"

  echo "RALPH status"
  echo "──────────────────────────────────"

  if [ ! -d "$vm_root" ]; then
    echo "  No sandbox VM directory found at $vm_root"
    return 0
  fi

  local _sb_list
  _sb_list="$(docker sandbox ls 2>/dev/null || true)"

  local found=0 total_bytes=0
  printf "  %-35s %8s  %-10s  %s\n" "NAME" "SIZE" "DOCKER" "LAST MODIFIED"
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    found=1
    local dir="$vm_root/$name"
    local size mtime docker_state
    size=$(du -sh "$dir" 2>/dev/null | awk '{print $1}')
    mtime=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$dir" 2>/dev/null)
    if echo "$_sb_list" | grep -q "^$name\b\|[[:space:]]$name\b"; then
      docker_state="live"
    else
      docker_state="orphan"
    fi
    printf "  %-35s %8s  %-10s  %s\n" "$name" "$size" "$docker_state" "$mtime"
    local bytes
    bytes=$(du -sk "$dir" 2>/dev/null | awk '{print $1}')
    total_bytes=$(( total_bytes + ${bytes:-0} ))
  done < <(_ralph_list_all)

  if [ "$found" -eq 0 ]; then
    echo "  No ralph-* sandboxes found."
    return 0
  fi

  local total_mb=$(( total_bytes / 1024 ))
  echo ""
  echo "  Total: ${total_mb} MB across ralph-* sandboxes"
  echo ""
  echo "  'orphan' = on disk but docker doesn't see it (safe to 'ralph cleanup --all')"
}

# ══════════════════════════════════════════════════════════════════════════════
# DISPATCH
# ══════════════════════════════════════════════════════════════════════════════

usage() {
  cat <<'USAGE'
Usage: ralph <command> [options]

Commands:
  init                Build image, create sandbox, verify env, scaffold .sandcastle/
  run [options]       Start the RALPH loop
  status              List all ralph-* sandboxes on disk with size and state
  cleanup [options]   Remove sandbox(es) and clean up

Run options:
  --iterations N      Max iterations (default: 50 or .sandcastle/config.json)
  --branch <name>     Create-or-checkout a branch for RALPH commits
  --quiet             Suppress streaming, log to .sandcastle/logs/
  --prompt <file>     Prompt-driven mode (instead of GitHub issues)

Cleanup options:
  --all               Remove every ralph-* sandbox on disk (not just current repo's)
  --image             Also remove the Docker image
USAGE
}

case "${1:-}" in
  init)    shift; cmd_init "$@" ;;
  run)     shift; cmd_run "$@" ;;
  status)  shift; cmd_status "$@" ;;
  cleanup) shift; cmd_cleanup "$@" ;;
  -h|--help|help) usage ;;
  "") usage; exit 1 ;;
  *) echo "Unknown command: $1" >&2; usage; exit 1 ;;
esac
