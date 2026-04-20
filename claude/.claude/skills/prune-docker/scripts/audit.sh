#!/usr/bin/env bash
# Read-only Docker disk audit for macOS.
# Prints sections so the caller can parse them; uses `|| true` on every probe
# so a single failure (permission prompt, missing file, daemon down) doesn't
# abort the rest of the audit.

set -u

hr() { printf '\n=== %s ===\n' "$1"; }

hr "HOST DISK"
df -h /System/Volumes/Data 2>/dev/null || true

hr "DOCKER DIRS"
du -sh ~/Library/Containers/com.docker.docker 2>/dev/null || true
du -sh ~/.docker 2>/dev/null || true
du -sh ~/.docker/sandboxes/vm 2>/dev/null || true

hr "Docker.raw"
raw=~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw
if [ -f "$raw" ]; then
  stat -f "%N: %z bytes logical, modified %Sm" "$raw" 2>/dev/null || true
else
  echo "(Docker.raw not found — Docker may not be running or VM hasn't been created yet)"
fi

hr "docker system df"
if docker info >/dev/null 2>&1; then
  docker system df 2>&1 || true
else
  echo "(docker daemon not reachable)"
fi

hr "docker system df -v (top 80 lines)"
docker system df -v 2>&1 | head -80 || true

hr "docker buildx ls"
docker buildx ls 2>&1 || true

hr "ralph sandbox VM dirs"
if [ -d ~/.docker/sandboxes/vm ]; then
  du -sh ~/.docker/sandboxes/vm/*/ 2>/dev/null || echo "(none)"
else
  echo "(no sandbox VM directory)"
fi

hr "exited containers"
docker ps -a --filter "status=exited" --format "{{.Names}}\t{{.Size}}" 2>&1 || true

hr "stale user-space Docker processes"
ps aux | grep -iE "docker|vmnetd" | grep -v grep | awk '{print $2, $9, $11}' | head -10 || true
