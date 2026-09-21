#!/usr/bin/env bash
# dispatch.sh — whitelisted entry point for n8n (and humans) to drive the agent mesh.
#
#   dispatch.sh sentinel                              -> print the latest sentinel report
#   dispatch.sh agent <codex|research|review|reviewer|claude> <task...> -> one agent, one task, non-interactive
#   dispatch.sh review <task...>                      -> codex writes, opencode first-reviews, opencode final-reviews
#
# Non-interactive flags (verified, not assumed):
#   codex exec "prompt"   |   claude -p "prompt"   |   gemini -p "prompt"
set -uo pipefail

# Mesh address book — override AGENTS_DIR to relocate the whole tree.
AGENTS_DIR="${AGENTS_DIR:-$HOME/agents}"
LOG="${DISPATCH_LOG:-$AGENTS_DIR/dispatch.log}"
WORK="${DISPATCH_WORK:-$AGENTS_DIR/workspace}"
TIMEOUT=${DISPATCH_TIMEOUT:-900}
FINAL_MODEL="${REVIEW_FINAL_MODEL:-opencode-go/CHANGE-ME}"
[ -f "$AGENTS_DIR/review.conf" ] && . "$AGENTS_DIR/review.conf"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }

declare -A CONTAINER=( [codex]=agent-codex-dev [claude]=agent-claude-review \
                        [research]=agent-gemini-research \
                        [review]=agent-opencode-research [reviewer]=agent-opencode-research )

run_agent() {   # run_agent <codex|research|review|reviewer|claude> <prompt>
  local who="$1"; shift
  local prompt="$*"
  local c="${CONTAINER[$who]:-}"
  [ -n "$c" ] || { echo "unknown agent: $who" >&2; return 2; }
  docker ps --format '{{.Names}}' | grep -qx "$c" || { echo "container $c is not running (spin it first)" >&2; return 3; }
  case "$who" in
    codex)  timeout "$TIMEOUT" docker exec "$c" codex exec \
              --skip-git-repo-check -C /work \
              --dangerously-bypass-approvals-and-sandbox "$prompt" < /dev/null ;;
    claude) timeout "$TIMEOUT" docker exec "$c" claude -p "$prompt" \
              --dangerously-skip-permissions < /dev/null ;;
    research) timeout "$TIMEOUT" docker exec "$c" gemini -p "$prompt" --skip-trust --approval-mode yolo < /dev/null ;;
    review)   timeout "$TIMEOUT" docker exec "$c" opencode run "$prompt" < /dev/null ;;
    reviewer) timeout "$TIMEOUT" docker exec "$c" opencode run -m "$FINAL_MODEL" "$prompt" < /dev/null ;;
  esac
}

cmd="${1:-}"; shift || true
case "$cmd" in
  sentinel)
    log "sentinel read"
    cat "${SENTINEL_REPORT:-/var/log/sentinel/latest.txt}" 2>/dev/null || { echo "no sentinel report yet" >&2; exit 1; }
    ;;
  agent)
    who="${1:-}"; shift || true
    [ -n "${1:-}" ] || { echo "usage: dispatch.sh agent <codex|research|review|reviewer|claude> <task>" >&2; exit 2; }
    log "agent $who :: $*"
    run_agent "$who" "$*"
    ;;
  review)
    [ -n "${1:-}" ] || { echo "usage: dispatch.sh review <task>" >&2; exit 2; }
    task="$*"
    dir="$WORK/review/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$dir"; log "review pipeline :: $task :: $dir"
    echo "== stage 1: codex writes =="
    run_agent codex "$task" | tee "$dir/1-write.md"
    echo; echo "== stage 2: first review (opencode / OpenCode Go) =="
    run_agent review "Review the work product below adversarially. Find factual errors, missing cases, and risky assumptions. Be specific, quote the text you are criticising, and rank the problems by severity.
=== WORK PRODUCT ===
$(cat "$dir/1-write.md")" | tee "$dir/2-review.md"
    echo; echo "== stage 3: final review (OpenCode Go, model: $FINAL_MODEL) =="
    run_agent reviewer "You are the final reviewer. Below are a work product and a prior review of it. Judge both: is the prior review correct, what did it miss, and what must change before this is accepted? Be decisive about accept / reject-with-changes.
=== WORK PRODUCT ===
$(cat "$dir/1-write.md")
=== PRIOR REVIEW ===
$(cat "$dir/2-review.md")" | tee "$dir/3-final-review.md"
    echo; echo "artifacts: $dir"
    ;;
  income)
    log "income brief"
    [ -x "$AGENTS_DIR/income.sh" ] || { echo "income.sh not found under $AGENTS_DIR (unpublished side script)" >&2; exit 3; }
    timeout "$TIMEOUT" "$AGENTS_DIR/income.sh"
    ;;
  ""|-h|--help)
    sed -n '2,6p' "$0"; exit 0
    ;;
  *)
    echo "denied: unknown action '$cmd'" >&2; exit 2
    ;;
esac
