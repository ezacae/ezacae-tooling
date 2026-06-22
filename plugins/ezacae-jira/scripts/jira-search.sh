#!/usr/bin/env bash
# Recherche JQL via l'API REST v3 (GET /search/jql). Affiche "CLE [STATUT] Résumé".
# (Remplace searchJiraIssuesUsingJql côté MCP — auto-autorisé, headless-safe.)
#
# Usage : jira-search.sh "<JQL>" [--max N] [--fields f1,f2,...] [--raw]
#   ex.   jira-search.sh "project = CRM AND status = CONCEPTION ORDER BY updated DESC"
# Requiert : JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN, jq
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-lib.sh"
jira_load_env
jira_require_creds
command -v jq >/dev/null 2>&1 || { echo "⛔ jq requis (brew install jq)" >&2; exit 1; }

[ "$#" -ge 1 ] || { echo "Usage: jira-search.sh \"<JQL>\" [--max N] [--fields f1,f2] [--raw]" >&2; exit 2; }
JQL="$1"; shift
MAX=50; FIELDS="summary,status"; RAW=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --max)    MAX="${2:?--max requiert un nombre}"; shift 2 ;;
    --fields) FIELDS="${2:?--fields requiert une liste}"; shift 2 ;;
    --raw)    RAW=1; shift ;;
    *) echo "⛔ Option inconnue : $1" >&2; exit 2 ;;
  esac
done

DATA=$(jira_curl -G "$(jira_base)/rest/api/3/search/jql" \
  --data-urlencode "jql=$JQL" \
  --data-urlencode "fields=$FIELDS" \
  --data-urlencode "maxResults=$MAX")

if [ "$RAW" = 1 ]; then printf '%s\n' "$DATA"; exit 0; fi
printf '%s' "$DATA" | jq -r '.issues[]? | "\(.key)\t[\(.fields.status.name // "?")]\t\(.fields.summary // "")"'
printf '%s' "$DATA" | jq -r '"— \(.issues | length) résultat(s)"' >&2
