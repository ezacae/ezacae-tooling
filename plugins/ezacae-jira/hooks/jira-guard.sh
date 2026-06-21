#!/usr/bin/env bash
# Hook PreToolUse — porte JIRA du pipeline Mike ⇄ Sarah (côté outils MCP).
#
# Double rôle :
#   1. AUTO-AUTORISER toute action JIRA MCP (création, lecture, édition, commentaire,
#      lien, recherche, transition…) sans validation manuelle — comportement par
#      défaut pour tout outil JIRA capté par le matcher du hooks.json.
#   2. GARDER les transitions : bloque une transitionJiraIssue qui ne respecte pas
#      le graphe de statuts du pipeline. La garde n'agit QUE si le ticket est dans
#      un statut DU pipeline et que les credentials REST sont présents.
#
# La logique de garde (graphe légal, normalisation, annulation) vit dans
# scripts/jira-lib.sh — partagée avec jira-transition.sh pour qu'une transition
# lancée en Bash applique EXACTEMENT le même filet de sécurité que via le MCP.
#
# Décision : exit 0 + JSON hookSpecificOutput.permissionDecision (allow|deny).
# Un "deny" d'un hook l'emporte toujours sur un "allow", donc la garde reste
# effective malgré l'auto-autorisation globale.
set -uo pipefail

# Source la lib partagée (creds, curl, statut, garde). Sans jq la lib reste
# inerte ; le repli ci-dessous gère ce cas.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)/jira-lib.sh"
jira_load_env

# Le hook dispose d'un budget court : timeout curl réduit.
export JIRA_CURL_MAX_TIME=6

INPUT=$(cat)

allow() {
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg c "${1:-}" '{hookSpecificOutput:({hookEventName:"PreToolUse",permissionDecision:"allow"} + (if $c=="" then {} else {additionalContext:$c} end))}'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
  fi
  exit 0
}
deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Sans jq on ne peut rien décider → ne pas bloquer.
command -v jq >/dev/null 2>&1 || { printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'; exit 0; }

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
KEY=$(printf '%s' "$INPUT" | jq -r '.tool_input.issueIdOrKey // empty')
TRID=$(printf '%s' "$INPUT" | jq -r '.tool_input.transitionId // empty')

# Tout outil JIRA NON-transition : auto-autorisé sans validation manuelle.
# Seules les transitions passent par la garde de statut ci-dessous.
case "$TOOL" in
  *transitionJiraIssue) ;;
  *) allow ;;
esac

[ -z "$KEY" ] && allow

# Garde inactive si credentials REST absents (cohérent avec les helpers).
if [ -z "${JIRA_BASE_URL:-}" ] || [ -z "${JIRA_EMAIL:-}" ] || [ -z "${JIRA_API_TOKEN:-}" ]; then
  allow "⚠ Garde de statut inactive : credentials JIRA absents."
fi

CUR=$(jira_status "$KEY" 2>/dev/null || true)
[ -z "$CUR" ] && allow "⚠ Garde : statut courant de $KEY introuvable — transition autorisée par défaut."

# Statut cible de la transition demandée (résolu depuis son id).
TARGET=""
if [ -n "$TRID" ]; then
  TARGET=$(jira_curl "$(jira_base)/rest/api/3/issue/$KEY/transitions" 2>/dev/null \
    | jq -r --arg id "$TRID" '.transitions[]? | select(.id==$id) | .to.name' | head -n1)
fi
[ -z "$TARGET" ] && allow "⚠ Garde : cible de la transition introuvable — autorisée par défaut."

# Décision déléguée à la garde partagée (même graphe que jira-transition.sh).
if REASON=$(jira_pipeline_guard "$CUR" "$TARGET"); then
  allow "✅ $REASON ($KEY)"
else
  deny "$REASON"
fi
