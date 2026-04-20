---
name: prune-docker
description: Reclaim disk space from Docker on macOS by auditing usage (images, containers, volumes, build cache, ralph sandboxes, Docker.raw) and guiding the user through cleanup steps least-to-most invasive. Use when user says "docker is taking space", "prune docker", "clean up docker", "disk full", or mentions system data / Docker.raw bloat. Each destructive step requires explicit user approval — never run automatically.
---

# Prune Docker — Disk Space Reclamation (macOS)

Guided, step-by-step Docker cleanup. Audit first, then propose cleanup steps ordered least-to-most invasive. **User must explicitly approve each step** before you run it.

## Core rules (NEVER violate)

1. **No destructive command runs without explicit "yes" for THAT specific step.** "Yes do it" to step 2 does not authorize step 3. Ask again every time.
2. **Never batch multiple destructive commands into one tool call.** One step at a time.
3. **Never use `rm -rf`, `docker volume rm`, `docker system prune`, `docker buildx prune`, or delete `Docker.raw` without prior explicit approval.**
4. **If the user says "do all of them" or "just clean everything"** — still go one at a time but skip re-asking; confirm once upfront that you'll proceed through the whole list unattended, then narrate each step as you do it.
5. **Audit commands (read-only) can run without asking.** These are: `df`, `du`, `stat`, `docker system df`, `docker volume ls`, `docker buildx ls`, `ls`, `ps`. Running these never mutates state. **Run the audit as ONE combined bash call, never as multiple parallel tool calls** — parallel batches fail atomically if any single call hits a permission prompt, which will leave you with partial data.
6. **Before each step, show exactly what command will run and what it will affect** (size, count of items, names of items where short enough).

## Phase 1 — Audit (run without asking)

Run the bundled audit script:

```bash
bash ~/.claude/skills/prune-docker/scripts/audit.sh
```

The script prints labelled sections (`=== HOST DISK ===`, `=== Docker.raw ===`, `=== docker system df ===`, etc.) with `|| true` on every probe so partial failures don't abort the audit.

**Do NOT replace this with multiple parallel tool calls** — parallel Bash batches fail atomically if any single call hits a permission prompt. The script runs everything in one shell invocation so a single prompt/failure doesn't lose the rest.

If the audit reports "docker daemon not reachable", stop and tell the user Docker Desktop isn't running. Ask if they want you to start it before continuing.

Present the audit as a table with **actual disk usage** (not logical), e.g.:

| Location | Size | Notes |
|---|---|---|
| `~/Library/Containers/com.docker.docker` | 346 GB | Docker.raw 685 GB logical / 310 GB actual |
| `~/.docker/sandboxes/vm` | 53 GB | 3 ralph sandboxes |
| Images (reclaimable) | 22.85 GB | 14 unused of 15 |
| Volumes | 58.24 GB | 45 total, 1 active; buildx builder cache = 39 GB |
| Build cache (reclaimable) | 21.45 GB | — |

## Phase 2 — Plan (ordered least-to-most invasive)

Present a numbered list. Only include steps that will actually reclaim something given the audit. Use this canonical order:

| # | Step | Invasiveness | Reclaims |
|---|---|---|---|
| 1 | `docker container prune -f` | safe — stopped containers only | small |
| 2 | `docker image prune -a -f` | safe if you don't mind re-pulling | images |
| 3 | `docker builder prune -af` | safe — build cache only | build cache |
| 4 | `docker buildx prune -af --builder <name>` per buildx builder | safe — per-builder buildx cache | buildx cache (often large) |
| 5 | `docker run --rm --privileged --pid=host docker/desktop-reclaim-space` | safe — just `fstrim` inside VM | shrinks Docker.raw host file |
| 6 | `rm -rf ~/.docker/sandboxes/vm/<orphan-sandbox>` (ralph or otherwise) | safe if sandbox isn't in active use | 10s of GB per orphan |
| 7 | `docker buildx rm <stale-builder>` for ralph-* builders with dead sockets | safe — removes dangling entries | cosmetic, helps step 4 |
| 8 | `docker volume rm <named-volume>` for each disposable volume | **data loss** — DB volumes etc. | per-volume |
| 9 | Restart Docker Desktop + re-run reclaim-space | safe but disruptive | further Docker.raw shrink |
| 10 | Delete `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw` | **nuclear — wipes ALL volumes, images, containers, build cache** | up to Docker.raw actual size |

Skip any step that has nothing to reclaim. For step 8, enumerate volumes with sizes and ask the user to classify each (keep / delete). Volumes from projects they still work on must be kept.

## Phase 3 — Execute (one step at a time)

For each step the plan includes, in order:

1. **State what you're about to do** and what will be affected (size, names).
2. **Ask for explicit approval**: *"Run step N — `<exact command>`? This will reclaim ~X GB and will <specific effect>. Yes to proceed, or say skip."*
3. **Wait for the user's answer.** Only "yes" / "y" / "do it" / "proceed" / "go" count as approval. Anything else → skip.
4. **Run the command.** One tool call per step.
5. **Report delta** — how much disk was actually reclaimed (re-check `df` and relevant `du`).
6. **Move to the next step.**

Do NOT auto-skip ahead if the user approves one step. Re-ask for the next.

## Invasive steps — extra guardrails

Before running step 8 (volume removal), **always** run:

```bash
bash ~/.claude/skills/prune-docker/scripts/list-volumes.sh
```

This prints size / volume name / using-container / compose project for every volume, sorted largest-first. Show the user the list and ask them to classify each volume they'd like to remove. Only pass volumes they explicitly named to `docker volume rm`. Never pipe the whole list into `xargs docker volume rm` — always name volumes one at a time.

Before running step 10 (Docker.raw deletion), **always**:
- Remind user this wipes every image, container, volume, and build cache — not reversible.
- Confirm Docker Desktop is quit first (`osascript -e 'quit app "Docker"'`).
- Check for leftover user-space docker processes (`pkill -9 -f "Docker.app"` etc.) ONLY if asked; else just verify with `ps aux | grep Docker`.
- Require an explicit second confirmation: *"This will delete Docker.raw and wipe everything. Type 'nuke' to confirm."*

## If Docker daemon is unresponsive

If `docker info` hangs or fails during audit:
1. Check processes: `ps aux | grep -iE "docker" | grep -v grep | head`
2. If there are stale user-space Docker processes that won't die, suggest `pkill -9 -f "Docker.app"` but require approval.
3. Relaunch with `open -a Docker`, then poll readiness (`until docker info >/dev/null 2>&1; do sleep 3; done`).

## Post-cleanup summary

After the session, print a totals table:
- Starting free disk vs ending free disk
- Per-step delta
- What was NOT cleaned (and why — user skipped / kept intentionally)

## Related

If ralph sandboxes keep accumulating, recommend the `ralph` skill's new commands:
- `ralph status` — list all ralph-* sandboxes with live/orphan state
- `ralph cleanup --all` — remove every ralph-* sandbox and its builder
