#!/usr/bin/env bash
# roster.sh — regenerate ROSTER.md from live state. Never hand-edit ROSTER.md; run this instead.
#   ./roster.sh        -> rewrite $AGENTS_DIR/ROSTER.md
#   ./roster.sh -      -> print to stdout, change nothing
set -uo pipefail

# --- config: override any of these via the environment ----------------------------------------
AGENTS_DIR="${AGENTS_DIR:-$HOME/agents}"          # mesh root: instances/, workspace/, and the configs below
DISPATCH="${DISPATCH:-$AGENTS_DIR/dispatch.sh}"   # role -> container map + model defaults
REVIEW_CONF="${REVIEW_CONF:-$AGENTS_DIR/review.conf}"  # per-stage review models
WRAP="${WRAP:-$AGENTS_DIR/n8n-forced.sh}"         # optional forced-command wrapper to introspect
PROVIDER="${PROVIDER:-opencode-go}"               # provider label shown in the roster table
OUT="${OUT:-$AGENTS_DIR/ROSTER.md}"
[ "${1:-}" = "-" ] && OUT=/dev/stdout

# --- models: read them from the configs that actually drive the runs, never guess -------------
RESEARCH_MODEL=$(sed -n 's/.*RESEARCH_MODEL="\${RESEARCH_MODEL:-\([^}]*\)}".*/\1/p' "$DISPATCH" | head -1)
FINAL_MODEL=$(sed -n 's/.*FINAL_MODEL="\${REVIEW_FINAL_MODEL:-\([^}]*\)}".*/\1/p' "$DISPATCH" | head -1)
[ -f "$REVIEW_CONF" ] && { . "$REVIEW_CONF"; FINAL_MODEL="${REVIEW_FINAL_MODEL:-$FINAL_MODEL}"; }
: "${RESEARCH_MODEL:=unknown}" "${FINAL_MODEL:=unknown}"

# --- roles come from dispatch.sh's container map, so the roster cannot invent one -------------
roles=$(sed -n '/declare -A CONTAINER=(/,/^[[:space:]]*$/p' "$DISPATCH" | tr -d '\\\n' \
        | grep -oE '\[[a-z]+\]=[a-z0-9-]+' | sed 's/\[//; s/\]=/\t/')
[ -n "$roles" ] || { echo "no CONTAINER map found in $DISPATCH" >&2; exit 1; }
role_of() { printf '%s\n' "$roles" | awk -F'\t' -v r="$1" '$1==r{print $2}'; }
cli_of()  {
  grep -oE "^[[:space:]]*$1\)[[:space:]]+.*" "$DISPATCH" | head -1 |
    sed -e "s/^[[:space:]]*$1)[[:space:]]*//" \
        -e 's/timeout "$TIMEOUT" docker exec "$c" //' \
        -e 's/[[:space:]]*< \/dev\/null//' \
        -e 's/[[:space:]]*;;[[:space:]]*$//' \
        -e 's/[[:space:]]*\\$//' \
        -e 's/[[:space:]]*"\$prompt"//' \
        -e 's/ -m "\$RESEARCH_MODEL"/ -m <research model>/' \
        -e 's/ -m "\$FINAL_MODEL"/ -m <reviewer model>/' |
    cut -c1-48
}

# Per-container model reads. Instances follow the spin-agent.sh layout:
#   $AGENTS_DIR/instances/<agent>-<instance>/home   <- container agent-<agent>-<instance>
inst_home() {  # inst_home <container> -> $AGENTS_DIR/instances/<name>/home
  local c="$1" d
  [ -n "$c" ] || return 1
  d="$AGENTS_DIR/instances/${c#agent-}/home"
  [ -d "$d" ] && { printf '%s\n' "$d"; return 0; }
  return 1
}
codex_model() {  # model from the container's codex config, if any
  local h; h=$(inst_home "$1") || { echo unknown; return; }
  grep -m1 -E '^[[:space:]]*model[[:space:]]*=' "$h/.codex/config.toml" 2>/dev/null | sed 's/.*=[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}.*/\1/'
}
oc_model() {  # model from the container's opencode config, if any
  local h; h=$(inst_home "$1") || { echo unknown; return; }
  grep -m1 -oE '"model"[[:space:]]*:[[:space:]]*"[^"]*"' "$h/.config/opencode/opencode.json" 2>/dev/null | sed 's/.*:[[:space:]]*"\([^"]*\)"/\1/'
}
model_for() {  # model_for <role> — the model that role actually runs on, per engine
  local r="$1" cli; cli=$(cli_of "$r")
  case "$cli" in
    *"opencode run -m"*) echo "${FINAL_MODEL:-unknown}" ;;
    *codex*)             codex_model "$(role_of "$r")" ;;
    *opencode*)          oc_model "$(role_of "$r")" ;;
    *gemini*)            echo "${RESEARCH_MODEL:-unknown}" ;;
    *)                   echo unknown ;;
  esac
}

# --- live state ------------------------------------------------------------------------------
running=$(docker ps --format '{{.Names}}|{{.Status}}' 2>/dev/null)
is_up()  { printf '%s\n' "$running" | awk -F'|' -v c="$1" '$1==c{print $2}'; }

{
  echo "# Agent mesh roster"
  echo
  echo "Generated $(date '+%F %T %Z') — **regenerate from live state, do not hand-edit**: \`roster.sh\`."
  echo
  echo "## Dispatch roles (what \`$DISPATCH agent <role>\` accepts)"
  echo
  echo "| role | container | engine | model | provider | container state |"
  echo "|---|---|---|---|---|---|"
  while IFS=$'\t' read -r role container; do
    printf '| %s | %s | %s | %s | %s | %s |\n' \
      "$role" "$container" "$(cli_of "$role")" "$(model_for "$role")" "$PROVIDER" "$(is_up "$container")"
  done <<< "$roles"
  echo
  echo "The role -> container map is read live from \`$DISPATCH\`, so the roster cannot show a role"
  echo "dispatch.sh does not have. \`review\` and \`reviewer\` may share a container on different models."
  echo
  echo "## Automation surface (what a restricted SSH key may run)"
  echo
  if [ -r "$WRAP" ]; then
    sed -n '/^case /,/^esac/p' "$WRAP" | grep -E '^[[:space:]]*"' | tr '|' '\n' \
      | sed 's/).*$//; s/^[[:space:]]*//; s/["*]//g; s/[[:space:]]*$//' \
      | grep -vE '^$|^-' | sort -u | awk '{print "- `"$0"`"}'
    grep -oE 'echo "allowed:.*"' "$WRAP" | head -1 | sed 's/echo "allowed: /- as advertised by the wrapper: /; s/"$//'
  else
    echo "- (no forced-command wrapper found at $WRAP — point \$WRAP at one or ignore this section)"
  fi
  echo
  echo "Anything off that list is refused by the forced-command wrapper — a \`denied\` is by design, not a bug."
  echo
  echo "## Live state"
  echo
  echo "- agent containers: $(docker ps --format '{{.Names}} ({{.Status}})' 2>/dev/null | grep '^agent-' | paste -sd';' - | sed 's/;/; /g')"
  echo
  echo "Verify any of this without changing it: \`roster.sh -\`"
} > "$OUT"

[ "$OUT" = /dev/stdout ] || echo "wrote $OUT ($(wc -l < "$OUT") lines)"