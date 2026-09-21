#!/usr/bin/env bash
# spin-agent.sh <agent> <instance-name>
# Start an isolated container for a single AI-agent instance.
#   agent:       codex | opencode | claude | gemini
#   instance:    unique name, e.g. dev, research, media
# Mounts:
#   $AGENTS_DIR/workspace  -> /work       (shared project workspace, rw)
#   $AGENTS_DIR/instances/<agent>-<instance>/home -> /home/node (isolated auth/config)
set -euo pipefail

# --- config: override any of these via the environment ----------------------------------------
AGENTS_DIR="${AGENTS_DIR:-$HOME/agents}"      # mesh root: workspace/ and instances/ live here
IMG="${IMG:-agent-base:latest}"               # build with: docker build -t agent-base:latest -f agent-base.Dockerfile .
RUN_UID="${RUN_UID:-1000}"                    # image's non-root user (node image: UID 1000)
AGENT_ENV="${AGENT_ENV:-$AGENTS_DIR/agent.env}"  # shared env file (keys, defaults); skipped if absent

AGENT="${1:-}"
INSTANCE="${2:-}"
[ -n "$AGENT" ] && [ -n "$INSTANCE" ] || {
  echo "usage: $0 <agent> <instance-name>" >&2
  exit 2
}
NAME="agent-$AGENT-$INSTANCE"

HOST_HOME="$AGENTS_DIR/instances/$AGENT-$INSTANCE/home"
HOST_WORK="$AGENTS_DIR/workspace"
mkdir -p "$HOST_HOME" "$HOST_WORK"
chown -R "$RUN_UID:$RUN_UID" "$HOST_HOME" "$HOST_WORK" 2>/dev/null || true

DOCKER_ARGS=(-d --name "$NAME" --restart unless-stopped)
[ -f "$AGENT_ENV" ] && DOCKER_ARGS+=(--env-file "$AGENT_ENV")

echo "Starting $NAME ..."
docker run "${DOCKER_ARGS[@]}" \
  -v "$HOST_HOME:/home/node" \
  -v "$HOST_WORK:/work" \
  -w /work \
  -e HOME=/home/node \
  "$IMG" sleep infinity

echo "Started container $NAME"
echo "  workspace:  $HOST_WORK  -> /work"
echo "  agent home: $HOST_HOME -> /home/node"
echo "  exec:  docker exec -it $NAME $AGENT"
echo "  stop:  docker rm -f $NAME"