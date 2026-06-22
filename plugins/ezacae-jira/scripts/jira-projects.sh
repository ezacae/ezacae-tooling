#!/usr/bin/env bash
# Liste les projets JIRA visibles, ou les types de ticket d'un projet, via REST v3.
# (Remplace getVisibleJiraProjects / getJiraProjectIssueTypesMetadata côté MCP.)
#
# Usage :
#   jira-projects.sh                 # projets visibles : "CLE<TAB>Nom"
#   jira-projects.sh <PROJECT-KEY>   # types de ticket du projet : "Nom<TAB>(id)[ sous-tâche]"
#   jira-projects.sh [...] --raw     # JSON brut de l'API
# Requiert : JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN, jq
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-lib.sh"
jira_load_env
jira_require_creds
command -v jq >/dev/null 2>&1 || { echo "⛔ jq requis (brew install jq)" >&2; exit 1; }

PROJECT=""; RAW=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --raw) RAW=1; shift ;;
    -*) echo "⛔ Option inconnue : $1" >&2; exit 2 ;;
    *) PROJECT="$1"; shift ;;
  esac
done

if [ -z "$PROJECT" ]; then
  DATA=$(jira_curl "$(jira_base)/rest/api/3/project/search?maxResults=100")
  [ "$RAW" = 1 ] && { printf '%s\n' "$DATA"; exit 0; }
  printf '%s' "$DATA" | jq -r '.values[]? | "\(.key)\t\(.name)"'
else
  DATA=$(jira_curl "$(jira_base)/rest/api/3/project/${PROJECT}")
  [ "$RAW" = 1 ] && { printf '%s\n' "$DATA"; exit 0; }
  printf '%s' "$DATA" | jq -r '.issueTypes[]? | "\(.name)\t(\(.id))\(if .subtask then "  [sous-tâche]" else "" end)"'
fi
