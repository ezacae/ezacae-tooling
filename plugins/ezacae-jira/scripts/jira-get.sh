#!/usr/bin/env bash
# Lit un ticket JIRA via l'API REST v3 et l'affiche de façon lisible.
# (Évite un appel MCP — fonctionne aussi en headless/cron, sans validation.)
#
# Usage : jira-get.sh <ISSUE-KEY> [--comments] [--raw] [--fields f1,f2,...]
#   --comments : inclut les commentaires
#   --raw      : sortie JSON brute de l'API (pour traitement programmatique)
#   --fields   : liste de champs JIRA (défaut : statut/résumé/type/assigné/description)
# Requiert : JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN, jq
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-lib.sh"
jira_load_env
jira_require_creds
command -v jq >/dev/null 2>&1 || { echo "⛔ jq requis (brew install jq)" >&2; exit 1; }

[ "$#" -ge 1 ] || { echo "Usage: jira-get.sh <ISSUE-KEY> [--comments] [--raw] [--fields f1,f2]" >&2; exit 2; }
ISSUE="$1"; shift

WITH_COMMENTS=0; RAW=0
FIELDS="summary,status,issuetype,assignee,reporter,priority,description,labels"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --comments) WITH_COMMENTS=1; FIELDS="$FIELDS,comment"; shift ;;
    --raw)      RAW=1; shift ;;
    --fields)   FIELDS="${2:?--fields requiert une liste}"; shift 2 ;;
    *) echo "⛔ Option inconnue : $1" >&2; exit 2 ;;
  esac
done

DATA=$(jira_curl "$(jira_base)/rest/api/3/issue/${ISSUE}?fields=${FIELDS}")

if [ "$RAW" = "1" ]; then
  printf '%s\n' "$DATA"
  exit 0
fi

# adf_text : aplatit récursivement les nœuds texte d'un document ADF en chaîne.
JQ_SUMMARY='
  def adf_text: [.. | objects | select(.type=="text") | .text] | join("");
  "🎫 \(.key)  [\(.fields.status.name // "?")]  \(.fields.issuetype.name // "")",
  "Résumé    : \(.fields.summary // "")",
  "Assigné   : \(.fields.assignee.displayName // "non assigné")",
  "Priorité  : \(.fields.priority.name // "")",
  "Labels    : \((.fields.labels // []) | join(", "))",
  "",
  "--- Description ---",
  (.fields.description | if . == null then "(vide)" else adf_text end)
'
printf '%s' "$DATA" | jq -r "$JQ_SUMMARY"

if [ "$WITH_COMMENTS" = "1" ]; then
  JQ_COMMENTS='
    def adf_text: [.. | objects | select(.type=="text") | .text] | join("");
    "", "--- Commentaires (\(.fields.comment.total // 0)) ---",
    (.fields.comment.comments[]? | "• [\(.author.displayName // "?")] \(.created[0:16])\n\(.body | adf_text)\n")
  '
  printf '%s' "$DATA" | jq -r "$JQ_COMMENTS"
fi
