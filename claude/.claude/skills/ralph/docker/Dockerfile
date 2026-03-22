FROM docker/sandbox-templates:claude-code

USER root

# Wrapper that injects CLAUDE_CODE_OAUTH_TOKEN and GH_TOKEN before claude starts.
# Placed in /usr/local/bin which won't be touched by claude auto-updates.
# The real binary lives at ~/.local/bin/claude.
RUN cat > /usr/local/bin/claude <<'WRAPPER'
#!/bin/bash
# Read tokens from .sandcastle/.ralph-env (written by ralph script)
# Falls back to .sandcastle/.env (user-managed per-project override)
RALPH_ENV=""
if [ -f .sandcastle/.ralph-env ]; then
  RALPH_ENV=".sandcastle/.ralph-env"
elif [ -f .sandcastle/.env ]; then
  RALPH_ENV=".sandcastle/.env"
fi
if [ -n "$RALPH_ENV" ]; then
  while IFS='=' read -r key value; do
    case "$key" in
      CLAUDE_CODE_OAUTH_TOKEN|GH_TOKEN)
        if [ -n "$value" ] && [ -z "$(eval echo \$$key)" ]; then
          export "$key=$value"
        fi
        ;;
    esac
  done < "$RALPH_ENV"
fi
exec /home/agent/.local/bin/claude "$@"
WRAPPER
RUN chmod +x /usr/local/bin/claude

# Prepend /usr/local/bin so wrapper is found before ~/.local/bin
ENV PATH=/usr/local/bin:$PATH

USER agent
