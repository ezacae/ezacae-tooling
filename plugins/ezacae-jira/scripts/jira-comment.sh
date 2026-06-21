#!/usr/bin/env bash
# Ajoute un commentaire à un ticket JIRA via l'API REST v3 (format ADF).
# (Le MCP demande parfois une validation ; ce helper est auto-autorisé.)
#
# Usage :
#   jira-comment.sh <ISSUE-KEY> "texte du commentaire"
#   jira-comment.sh <ISSUE-KEY> -f <fichier>        # corps depuis un fichier
#   echo "texte" | jira-comment.sh <ISSUE-KEY> -    # corps depuis stdin
# Requiert : JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN, jq
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-lib.sh"
jira_load_env
jira_require_creds
command -v jq >/dev/null 2>&1 || { echo "⛔ jq requis (brew install jq)" >&2; exit 1; }

[ "$#" -ge 2 ] || { echo "Usage: jira-comment.sh <ISSUE-KEY> <texte> | -f <fichier> | -" >&2; exit 2; }
ISSUE="$1"; shift

case "$1" in
  -f) [ -f "${2:-}" ] || { echo "⛔ Fichier introuvable : ${2:-}" >&2; exit 1; }; TEXT=$(cat "$2") ;;
  -)  TEXT=$(cat) ;;
  *)  TEXT="$*" ;;
esac

[ -n "$TEXT" ] || { echo "⛔ Commentaire vide." >&2; exit 2; }

printf '%s' "$TEXT" | jira_text_to_adf | jq '{body: .}' \
  | jira_curl -X POST -H "Content-Type: application/json" --data @- \
    "$(jira_base)/rest/api/3/issue/${ISSUE}/comment" >/dev/null

echo "💬 commentaire ajouté à $ISSUE"
