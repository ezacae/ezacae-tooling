#!/usr/bin/env bash
# Hook PreToolUse(Bash) — auto-autorise les helpers JIRA du plugin ezacae-jira.
#
# Les pièces jointes JIRA passent par les scripts REST `jira-attach.sh` /
# `jira-download.sh` (cf. skill jira-pipeline). Ce hook évite de valider
# manuellement chaque appel à ces helpers.
#
# Il N'émet une décision QUE pour ces commandes : toute autre commande Bash
# ressort sans JSON (exit 0), donc le flux de permission normal s'applique —
# on n'auto-autorise jamais du Bash arbitraire.
set -uo pipefail

# Sans jq on ne peut pas lire la commande de façon fiable → ne rien décider.
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')

case "$CMD" in
  *jira-attach.sh*|*jira-download.sh*)
    jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow"}}'
    ;;
esac
exit 0
