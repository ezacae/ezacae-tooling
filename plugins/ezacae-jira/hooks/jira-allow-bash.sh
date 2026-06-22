#!/usr/bin/env bash
# Hook PreToolUse(Bash) — auto-autorise les helpers JIRA du plugin ezacae-jira.
#
# Toutes les opérations JIRA des agents passent par les helpers REST `jira-*.sh`
# (cf. skill jira-pipeline) : lecture (jira-get), commentaire (jira-comment),
# transition (jira-transition, garde intégrée), édition (jira-edit), pièces
# jointes (jira-attach / jira-download), création (jira-create), projets/types
# (jira-projects), recherche JQL (jira-search), liaison (jira-link). Ce hook évite
# de valider manuellement chaque appel à ces helpers — c'est ce qui rend le
# pipeline non-interactif et supprime tout besoin du MCP Atlassian.
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
  *jira-attach.sh*|*jira-download.sh*|*jira-get.sh*|*jira-comment.sh*|*jira-transition.sh*|*jira-edit.sh*|*jira-create.sh*|*jira-projects.sh*|*jira-search.sh*|*jira-link.sh*)
    jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow"}}'
    ;;
esac
exit 0
