#!/usr/bin/env bash
# For each Docker named volume, prints:
#   <size>\t<volume_name>\t<in_use_by_container_or_"->\t<compose_project_label>
# Sorted by size descending (largest first).
# Read-only.

set -u

if ! docker info >/dev/null 2>&1; then
  echo "docker daemon not reachable" >&2
  exit 1
fi

# Get volume name → size map from `docker system df -v`
volumes_raw=$(docker system df -v 2>/dev/null | awk '
  /^Local Volumes space usage:/ { in_section=1; next }
  in_section && /^$/ { in_section=0 }
  in_section && NF>=3 && $1 != "VOLUME" { print $NF "\t" $1 }
')

if [ -z "$volumes_raw" ]; then
  echo "(no local volumes)"
  exit 0
fi

printf "%-12s  %-70s  %-40s  %s\n" "SIZE" "VOLUME" "USED BY" "COMPOSE PROJECT"

# For each volume, look up referencing container + compose label
echo "$volumes_raw" | while IFS=$'\t' read -r size name; do
  [ -z "$name" ] && continue

  used_by=$(docker ps -a --filter "volume=$name" --format "{{.Names}}" 2>/dev/null | paste -sd "," -)
  [ -z "$used_by" ] && used_by="-"

  project=$(docker volume inspect "$name" --format '{{ index .Labels "com.docker.compose.project" }}' 2>/dev/null)
  [ -z "$project" ] && project="-"

  printf "%-12s  %-70s  %-40s  %s\n" "$size" "$name" "$used_by" "$project"
done | sort -h -r -k1,1
