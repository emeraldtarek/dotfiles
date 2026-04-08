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

cmd_cleanup() {
  local root name
  root="$(repo_root)"
  name="$(sandbox_name)"

  local remove_image=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --image) remove_image=1; shift ;;
      *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
  done

  echo "RALPH cleanup — $(basename "$root")"
  echo "──────────────────────────────────"

  local _sb_list
  _sb_list="$(docker sandbox ls 2>/dev/null || true)"
  if echo "$_sb_list" | grep -q "$name"; then
    echo "  Removing sandbox '$name'..."
    docker sandbox rm "$name"
    echo "  Sandbox removed."
  else
    echo "  Sandbox '$name' not found, skipping."
  fi

  if [ "$remove_image" -eq 1 ]; then
    if docker image inspect "$RALPH_IMAGE" &>/dev/null 2>&1; then
      echo "  Removing image '$RALPH_IMAGE'..."
      docker rmi "$RALPH_IMAGE"
      echo "  Image removed."
    else
      echo "  Image '$RALPH_IMAGE' not found, skipping."
    fi
  fi

  # Clean up generated files
  cleanup_env
  rm -rf "$root/.sandcastle/context" "$root/.sandcastle/logs"
  echo ""
  echo "Cleanup complete."
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
  cleanup [options]   Remove sandbox and clean up

Run options:
  --iterations N      Max iterations (default: 50 or .sandcastle/config.json)
  --branch <name>     Create-or-checkout a branch for RALPH commits
  --quiet             Suppress streaming, log to .sandcastle/logs/
  --prompt <file>     Prompt-driven mode (instead of GitHub issues)

Cleanup options:
  --image             Also remove the Docker image
USAGE
}

case "${1:-}" in
  init)    shift; cmd_init "$@" ;;
  run)     shift; cmd_run "$@" ;;
  cleanup) shift; cmd_cleanup "$@" ;;
  -h|--help|help) usage ;;
  "") usage; exit 1 ;;
  *) echo "Unknown command: $1" >&2; usage; exit 1 ;;
esac
