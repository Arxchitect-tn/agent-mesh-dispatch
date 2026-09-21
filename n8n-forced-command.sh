#!/usr/bin/env bash
# forced-command wrapper — the ONLY thing the n8n SSH key is allowed to run.
# Installed via command="..." in ~/.ssh/authorized_keys.
#
# n8n's SSH node always sends the command prefixed with "cd <dir> ; " (its default
# working directory is "/"), so an exact match denies every n8n call while still
# accepting the same command typed from a shell. Strip ONLY that shape, then validate
# the remainder strictly: the path may not contain shell metacharacters, and the whole
# remaining string must match a whitelisted action, so "cd / ; rm -rf /" is still denied.
set -uo pipefail

orig="${SSH_ORIGINAL_COMMAND:-}"
action="$orig"

# Pattern in a variable: an inline [[ =~ ]] with & ; | < > breaks bash's parser.
prefix_re='^cd[[:space:]]+[^;&|<>]*[[:space:]]*(;|&&)[[:space:]]*(.*)$'
if [[ "$action" =~ $prefix_re ]]; then
  action="${BASH_REMATCH[2]}"
fi

AUDIT=/home/admin/agents/n8n-forced.log

case "$action" in
  "sentinel"|"sentinel "*) ;;
  "income"|"income "*) ;;
  "agent codex "*|"agent research "*|"agent review "*|"agent reviewer "*) ;;
  "review "*) ;;
  ""|"-h"|"--help")
    echo "allowed: sentinel | income | agent <codex|research|review|reviewer> <task> | review <task>"
    exit 0
    ;;
  *)
    printf '%s DENIED <%s>\n' "$(date '+%F %T')" "$action" >> "$AUDIT" 2>/dev/null
    echo "denied: allowed actions are: sentinel | income | agent <codex|research|review|reviewer> <task> | review <task>" >&2
    exit 126
    ;;
esac

printf '%s RUN <%s>\n' "$(date '+%F %T')" "$action" >> "$AUDIT" 2>/dev/null
exec /home/admin/agents/dispatch.sh $action
