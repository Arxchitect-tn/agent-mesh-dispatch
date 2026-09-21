# AI-agent isolation base image.
# One image, N disposable agent containers. Each container mounts its own
# home dir (auth/config/skills) so agents never share profiles.
FROM node:22-bookworm-slim

# node + git + basics for agent CLIs
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl ca-certificates python3 python3-pip build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install the CLI coding agents (opencode-ai is the npm package for OpenCode)
RUN npm install -g \
      @openai/codex@latest \
      @anthropic-ai/claude-code@latest \
      opencode-ai@latest \
      @google/gemini-cli@latest

# The node image already ships a non-root 'node' user at UID 1000 — reuse it.
USER node
WORKDIR /work
ENV HOME=/home/node

# Build:   docker build -t agent-base:latest -f agent-base.Dockerfile .
# Runtime: docker run -v <instance-home>:/home/node -v <workspace>:/work agent-base:latest sleep infinity
#   /work      is the shared workspace mount point.
#   /home/node is where per-instance auth/config gets mounted.
# No ENTRYPOINT: `docker run agent-base:latest sleep infinity` runs sleep directly.