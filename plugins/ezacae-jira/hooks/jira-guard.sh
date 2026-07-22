#!/usr/bin/env bash
# Hook PreToolUse — porte JIRA du pipeline Mike ⇄ Sarah (côté outils MCP).
#
# Le pipeline est « zéro MCP » : toute opération JIRA a un helper REST `jira-*.sh`
# équivalent. Ce hook rend cette règle DÉTERMINISTE côté MCP :
#   1. REDIRIGER — toute action MCP ayant un helper (lecture, commentaire, édition,
#      création, recherche, projets, liens) est refusée (deny) et pointe le helper
#      exact à utiliser. Un deny de hook ne peut pas être contourné par l'agent :
#      c'est le seul aiguillage fiable (une simple consigne est ignorée). Si les
#      credentials manquent, le deny guide pas à pas la création de .claude/jira.env.
#   2. GARDER les transitions : `transitionJiraIssue` reste la seule exception MCP
#      (champ d'écran custom obligatoire non géré par jira-transition.sh). Sa garde
#      bloque toute transition hors graphe de statuts. N'agit QUE si le ticket est
#      dans un statut DU pipeline et que les credentials REST sont présents.
#   3. AUTORISER — les rares outils MCP JIRA sans helper (getTransitionsForJiraIssue,
#      addWorklog, getAccessibleAtlassianResources…) restent auto-autorisés.
#
# La logique de garde (graphe légal, normalisation, annulation) vit dans
# scripts/jira-lib.sh — partagée avec jira-transition.sh pour qu'une transition
# lancée en Bash applique EXACTEMENT le même filet de sécurité que via le MCP.
#
# Décision : exit 0 + JSON hookSpecificOutput.permissionDecision (allow|deny).
# Un "deny" d'un hook l'emporte toujours sur un "allow".
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

# --- Redirection MCP → helpers REST (ezacae-jira) ---
# Les opérations Jira ayant un helper `jira-*.sh` équivalent ne doivent PAS passer
# par le MCP : on renvoie deny + le nom exact du helper. Un deny de hook est le seul
# aiguillage qu'un agent ne peut pas ignorer (une consigne écrite est contournée).
# Les rares outils MCP SANS helper (getTransitionsForJiraIssue, addWorklog,
# getAccessibleAtlassianResources…) tombent dans le `*) allow` plus bas.
HELPER_DIR="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/scripts"
EXAMPLE="${HELPER_DIR%/scripts}/jira.env.example"

redirect() {
  # $1 = usage du helper (ex. "jira-get.sh <KEY> [--comments]").
  if [ -n "${JIRA_BASE_URL:-}" ] && [ -n "${JIRA_EMAIL:-}" ] && [ -n "${JIRA_API_TOKEN:-}" ]; then
    deny "MCP Jira redirigé → utilise le helper REST du plugin ezacae-jira : ${HELPER_DIR}/$1 (auto-autorisé, fonctionne en headless/cron). Ne pas contourner par le MCP."
  else
    deny "Credentials Jira absents : le helper ${HELPER_DIR}/$1 ne peut pas tourner. Pour l'activer, GUIDE l'utilisateur pas à pas (ne fabrique jamais le token toi-même — demande-lui les valeurs ou laisse-le remplir le fichier) :
1) Générer un token API Atlassian : https://id.atlassian.com/manage-profile/security/api-tokens
2) Copier le modèle :  cp ${EXAMPLE} <projet>/.claude/jira.env
3) Renseigner dans ce fichier : JIRA_BASE_URL=https://ezacae.atlassian.net , JIRA_EMAIL=<email ezacae> , JIRA_API_TOKEN=<token généré à l'étape 1>
4) Relancer l'opération : le helper prend alors le relais.
Ne PAS contourner par le MCP en attendant."
  fi
}

case "$TOOL" in
  *getJiraIssue)                     redirect 'jira-get.sh <KEY> [--comments]' ;;
  *addCommentToJiraIssue)            redirect 'jira-comment.sh <KEY> "texte" | -f <fichier>' ;;
  *editJiraIssue)                    redirect 'jira-edit.sh <KEY> [--summary|--description-file|--label|--assignee …]' ;;
  *createJiraIssue)                  redirect 'jira-create.sh --project <KEY> --type <NOM> --summary "…" [--description-file <f>]' ;;
  *searchJiraIssuesUsingJql)         redirect 'jira-search.sh "<JQL>" [--max N]' ;;
  *createIssueLink)                  redirect 'jira-link.sh <CLE-INWARD> <CLE-OUTWARD> [--type "Relates"]' ;;
  *getVisibleJiraProjects)           redirect 'jira-projects.sh   (sans argument = liste des projets visibles)' ;;
  *getJiraProjectIssueTypesMetadata) redirect 'jira-projects.sh <PROJECT-KEY>   (types de ticket du projet)' ;;
  *getJiraIssueTypeMetaWithFields)   redirect 'jira-projects.sh <PROJECT-KEY>   (types de ticket du projet)' ;;
esac

# Tout autre outil JIRA NON-transition : auto-autorisé sans validation manuelle.
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
