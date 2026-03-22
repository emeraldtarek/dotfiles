---
name: ralph
description: Run an AFK RALPH loop in a Docker sandbox — iterates over GitHub issues or a prompt file, implements tasks, commits with RALPH: prefix. Use when user says "ralph", "AFK loop", "run ralph", or wants autonomous Docker-sandboxed development.
---

# RALPH — AFK Docker Sandbox Loop

RALPH runs Claude Code headlessly in a Docker sandbox, iterating over GitHub issues (or a prompt file) until all work is done.

## Quick start

```bash
# First time in a repo
ralph init

# Start the loop (GitHub issues mode)
ralph run

# Start with options
ralph run --iterations 20 --branch feat/new-feature --quiet

# Prompt-driven mode
ralph run --prompt task.md

# Tear down
ralph cleanup
```

## Subcommands

### `ralph init`
Builds the Docker image (with OAuth wrapper), creates the sandbox, verifies `CLAUDE_CODE_OAUTH_TOKEN` and `GH_TOKEN` are set, scaffolds `.sandcastle/` directory with `.gitignore`.

### `ralph run [flags]`
Runs the RALPH loop. Flags:
- `--iterations N` — max iterations (default: `.sandcastle/config.json` → global default 50)
- `--branch <name>` — create-or-checkout branch for RALPH commits
- `--quiet` — suppress streaming, log to `.sandcastle/logs/`
- `--prompt <file>` — use a prompt file instead of GitHub issues

### `ralph cleanup`
Removes the sandbox. Pass `--image` to also remove the Docker image.

## Override cascade

Per-project files in `.sandcastle/` override global defaults:

| File | Purpose | Global default |
|---|---|---|
| `Dockerfile` | Custom sandbox image | `~/.claude/skills/ralph/docker/Dockerfile` |
| `prompt.md` | Custom RALPH instructions | `~/.claude/skills/ralph/prompt.md` |
| `config.json` | `{"defaultIterations": N}` | 50 |
| `.env` | Per-project tokens | Shell environment vars |

## When invoked as a skill

If the user asks you to run ralph, start the loop, or do AFK work:
1. Check prerequisites: `docker sandbox ls` works, env vars set
2. Run `ralph init` if sandbox doesn't exist
3. Run `ralph run` with appropriate flags based on user's request
