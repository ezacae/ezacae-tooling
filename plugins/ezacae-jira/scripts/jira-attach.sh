#!/usr/bin/env bash
# Attache un ou plusieurs fichiers à un ticket JIRA via l'API REST v3.
# (Le MCP Atlassian ne propose pas d'upload de pièce jointe.)
#
# Usage : jira-attach.sh <ISSUE-KEY> <fichier> [fichier...]
# Requiert : JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN
set -euo pipefail

# Credentials + helpers REST partagés (chargement de .claude/jira.env inclus).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-lib.sh"
jira_load_env
jira_require_creds

if [ "$#" -lt 2 ]; then
  echo "Usage: jira-attach.sh <ISSUE-KEY> <fichier> [fichier...]" >&2
  exit 2
fi

ISSUE="$1"; shift

for f in "$@"; do
  if [ ! -f "$f" ]; then
    echo "⛔ Fichier introuvable : $f" >&2
    exit 1
  fi
  echo "↑ $f → $ISSUE"
  jira_curl -X POST \
    -H "X-Atlassian-Token: no-check" \
    -F "file=@${f}" \
    "$(jira_base)/rest/api/3/issue/${ISSUE}/attachments" >/dev/null
done

echo "✅ $(($#)) fichier(s) attaché(s) à $ISSUE"
