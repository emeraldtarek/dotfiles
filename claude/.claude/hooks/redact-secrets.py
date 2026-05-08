#!/usr/bin/env python3
"""
PostToolUse hook: redact known secret values from tool output before
Claude sees them. Reads keychain entry names from
~/.config/claude-redact/secrets (one per line, '#' for comments).
For each name, looks up the value via macOS Keychain and replaces every
occurrence in the tool's stdout/stderr/content with [REDACTED:<name>].

Caches looked-up values in a per-user tmp file (mode 0600) to avoid
the cost of N sequential `security` calls on every Bash invocation.
Cache invalidates when the config file changes or after CACHE_TTL_SECONDS.

Designed to be defensive about input shape — Claude Code's hook docs are
inconsistent about whether the field is tool_response, tool_output, or
tool_result. We try all of them and use the first dict found.
"""

import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

CONFIG_PATH = Path(
    os.environ.get(
        "CLAUDE_REDACT_CONFIG",
        Path.home() / ".config" / "claude-redact" / "secrets",
    )
)
CACHE_PATH = Path(tempfile.gettempdir()) / f"claude-redact-{os.getuid()}.cache"
CACHE_TTL_SECONDS = 1800  # 30 minutes

RELEVANT_TOOLS = ("Bash", "Read", "WebFetch")
OUTPUT_PARENTS = ("tool_response", "tool_output", "tool_result")
OUTPUT_FIELDS = ("stdout", "stderr", "content")

# Skip values shorter than this — they cause false-positive matches against
# unrelated output and against redaction markers themselves (e.g. value
# "adadvisor" matching inside the marker text "[REDACTED:adadvisor-...]").
# 12 is permissive enough for most real API keys/passwords while filtering
# out config values like DB names, ports, and short identifiers.
MIN_SECRET_LENGTH = 12


def read_config_names():
    if not CONFIG_PATH.exists():
        return []
    names = []
    for line in CONFIG_PATH.read_text().splitlines():
        n = line.strip()
        if n and not n.startswith("#"):
            names.append(n)
    return names


def lookup_keychain(names):
    user = os.environ.get("USER", "")
    if not user:
        return {}
    out = {}
    for name in names:
        try:
            r = subprocess.run(
                ["security", "find-generic-password", "-a", user, "-s", name, "-w"],
                capture_output=True,
                text=True,
                timeout=2,
            )
        except (subprocess.SubprocessError, OSError):
            continue
        if r.returncode != 0:
            continue
        value = r.stdout.rstrip("\n")
        if value:
            out[name] = value
    return out


def load_cache(config_mtime):
    if not CACHE_PATH.exists():
        return None
    try:
        st = CACHE_PATH.stat()
    except OSError:
        return None
    if (time.time() - st.st_mtime) > CACHE_TTL_SECONDS:
        return None
    try:
        data = json.loads(CACHE_PATH.read_text())
    except (json.JSONDecodeError, OSError):
        return None
    if data.get("config_mtime") != config_mtime:
        return None
    values = data.get("values")
    if not isinstance(values, dict):
        return None
    return values


def save_cache(values, config_mtime):
    payload = json.dumps({"config_mtime": config_mtime, "values": values})
    fd = os.open(str(CACHE_PATH), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        os.write(fd, payload.encode("utf-8"))
    finally:
        os.close(fd)


def get_secrets():
    """Return list of (name, value) pairs, using disk cache when fresh."""
    if not CONFIG_PATH.exists():
        return []
    config_mtime = CONFIG_PATH.stat().st_mtime
    cached = load_cache(config_mtime)
    if cached is not None:
        return list(cached.items())
    names = read_config_names()
    if not names:
        return []
    values = lookup_keychain(names)
    try:
        save_cache(values, config_mtime)
    except OSError:
        pass
    return list(values.items())


def find_output_container(payload):
    for key in OUTPUT_PARENTS:
        node = payload.get(key)
        if isinstance(node, dict):
            return node
    return None


def main():
    raw = sys.stdin.read()
    if not raw.strip():
        return
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return

    if payload.get("tool_name") not in RELEVANT_TOOLS:
        return

    container = find_output_container(payload)
    if container is None:
        return

    pieces = []
    for k in OUTPUT_FIELDS:
        v = container.get(k)
        if isinstance(v, str) and v:
            if k == "stderr":
                pieces.append(f"[stderr]\n{v}")
            else:
                pieces.append(v)
    if not pieces:
        return

    secrets = get_secrets()
    # Drop too-short values, then sort by descending length so the longer
    # (more specific) match runs first and short substrings can't damage
    # the markers left behind by earlier replacements.
    secrets = sorted(
        ((n, v) for n, v in secrets if len(v) >= MIN_SECRET_LENGTH),
        key=lambda nv: -len(nv[1]),
    )
    if not secrets:
        return

    combined = "\n".join(pieces)
    redacted = combined
    # Two-pass replacement so secret values that happen to be substrings of
    # other secrets' names can't corrupt earlier markers. Pass 1: every value
    # is swapped for a NUL-bracketed sentinel. Pass 2: sentinels are swapped
    # for the friendly [REDACTED:name] markers.
    sentinels = []
    for i, (name, value) in enumerate(secrets):
        if value in redacted:
            sentinel = f"\x00REDACT{i}\x00"
            redacted = redacted.replace(value, sentinel)
            sentinels.append((sentinel, name))
    for sentinel, name in sentinels:
        redacted = redacted.replace(sentinel, f"[REDACTED:{name}]")

    if redacted == combined:
        return

    sys.stdout.write(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PostToolUse",
                    "updatedToolOutput": redacted,
                }
            }
        )
    )


if __name__ == "__main__":
    main()
