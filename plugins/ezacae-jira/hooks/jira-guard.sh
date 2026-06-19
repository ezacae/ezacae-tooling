#!/usr/bin/env bash
# Hook PreToolUse — garde de statut du pipeline Mike ⇄ Sarah.
#
# Bloque une transition JIRA qui ne respecte pas le graphe de statuts du pipeline.
# N'agit QUE si :
#   - l'outil est une transition (transitionJiraIssue),
#   - les credentials JIRA REST sont présents,
#   - le ticket est actuellement dans un statut DU pipeline.
# Sinon : autorise (les ~38 autres projets / workflows ne sont pas concernés).
#
# Décision : exit 0 + JSON hookSpecificOutput.permissionDecision (allow|deny).
set -uo pipefail

# Charge <projet>/.claude/jira.env si les credentials ne sont pas déjà exportés.
# Hook de plugin : CLAUDE_PROJECT_DIR pointe le projet courant, pas le cache du plugin.
_JIRA_ENV="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/jira.env"
if [ -z "${JIRA_BASE_URL:-}" ] && [ -f "$_JIRA_ENV" ]; then set -a; . "$_JIRA_ENV"; set +a; fi

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

# Ne garder que les transitions.
case "$TOOL" in
  *transitionJiraIssue) ;;
  *) allow ;;
esac

[ -z "$KEY" ] && allow

# Garde inactive si credentials REST absents (cohérent avec les helpers de PJ).
if [ -z "${JIRA_BASE_URL:-}" ] || [ -z "${JIRA_EMAIL:-}" ] || [ -z "${JIRA_API_TOKEN:-}" ]; then
  allow "⚠ Garde de statut inactive : credentials JIRA absents."
fi

BASE="${JIRA_BASE_URL%/}"
AUTH="$JIRA_EMAIL:$JIRA_API_TOKEN"

CUR=$(curl --fail --silent --max-time 6 -u "$AUTH" \
  "$BASE/rest/api/3/issue/$KEY?fields=status" 2>/dev/null \
  | jq -r '.fields.status.name // empty')
[ -z "$CUR" ] && allow "⚠ Garde : statut courant de $KEY introuvable — transition autorisée par défaut."

# La casse des statuts JIRA est incohérente (Nouveau, CONCEPTION, Recette Interne…).
# On normalise en majuscules ASCII pour toutes les comparaisons.
CUR_U=$(printf '%s' "$CUR" | tr '[:lower:]' '[:upper:]')

# Hors périmètre du pipeline → ne pas interférer.
case "$CUR_U" in
  NOUVEAU|CADRAGE|CONCEPTION|"CONCEPTION VALIDATION"|"CONCEPTION OK"|"EN COURS"|EXAMINER|"RECETTE INTERNE") ;;
  *) allow ;;
esac

# Statut cible de la transition demandée.
TARGET=""
if [ -n "$TRID" ]; then
  TARGET=$(curl --fail --silent --max-time 6 -u "$AUTH" \
    "$BASE/rest/api/3/issue/$KEY/transitions" 2>/dev/null \
    | jq -r --arg id "$TRID" '.transitions[]? | select(.id==$id) | .to.name' | head -n1)
fi
[ -z "$TARGET" ] && allow "⚠ Garde : cible de la transition introuvable — autorisée par défaut."
TARGET_U=$(printf '%s' "$TARGET" | tr '[:lower:]' '[:upper:]')

# L'annulation est une transition globale du workflow — toujours permise.
case "$TARGET_U" in ANNUL*) allow "✅ Annulation autorisée ($KEY)." ;; esac

# Graphe des transitions légales du pipeline : "SOURCE>CIBLE".
LEGAL="NOUVEAU>CADRAGE
CADRAGE>CONCEPTION
CONCEPTION>CONCEPTION VALIDATION
CONCEPTION VALIDATION>CONCEPTION
CONCEPTION VALIDATION>CONCEPTION OK
CONCEPTION OK>EN COURS
EN COURS>EXAMINER
EXAMINER>EN COURS
EXAMINER>RECETTE INTERNE"

if printf '%s\n' "$LEGAL" | grep -qxF "$CUR_U>$TARGET_U"; then
  allow "✅ Transition pipeline conforme : $CUR → $TARGET ($KEY)."
else
  LEGAL_FROM=$(printf '%s\n' "$LEGAL" | grep -F "$CUR_U>" | sed 's/^[^>]*>/→ /' | tr '\n' ' ')
  [ -z "$LEGAL_FROM" ] && LEGAL_FROM="(aucune — statut terminal du pipeline)"
  deny "Transition hors pipeline Mike⇄Sarah pour $KEY : '$CUR' → '$TARGET' n'est pas autorisée. Étapes légales depuis '$CUR' : ${LEGAL_FROM}"
fi
