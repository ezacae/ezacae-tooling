#!/usr/bin/env bash
# Lie deux tickets JIRA via l'API REST v3 (POST /issueLink).
# (Remplace createIssueLink côté MCP — auto-autorisé, headless-safe.)
#
# Usage : jira-link.sh <CLE-INWARD> <CLE-OUTWARD> [--type "<NOM>"]
#   --type : nom du type de lien (défaut "Relates"). Ex. "Blocks", "Cloners".
#            La sémantique inward/outward dépend du type (cf. type de lien JIRA).
# Requiert : JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN, jq
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-lib.sh"
jira_load_env
jira_require_creds
command -v jq >/dev/null 2>&1 || { echo "⛔ jq requis (brew install jq)" >&2; exit 1; }

[ "$#" -ge 2 ] || { echo "Usage: jira-link.sh <CLE-INWARD> <CLE-OUTWARD> [--type \"Relates\"]" >&2; exit 2; }
INWARD="$1"; OUTWARD="$2"; shift 2
TYPE="Relates"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --type) TYPE="${2:?--type requiert un nom}"; shift 2 ;;
    *) echo "⛔ Option inconnue : $1" >&2; exit 2 ;;
  esac
done

jq -n --arg t "$TYPE" --arg i "$INWARD" --arg o "$OUTWARD" \
  '{type:{name:$t}, inwardIssue:{key:$i}, outwardIssue:{key:$o}}' \
  | jira_curl -X POST -H "Content-Type: application/json" --data @- "$(jira_base)/rest/api/3/issueLink" >/dev/null
echo "🔗 $INWARD —[$TYPE]→ $OUTWARD"
