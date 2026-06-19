#!/usr/bin/env bash
# Attache un ou plusieurs fichiers à un ticket JIRA via l'API REST v3.
# (Le MCP Atlassian ne propose pas d'upload de pièce jointe.)
#
# Usage : jira-attach.sh <ISSUE-KEY> <fichier> [fichier...]
# Requiert : JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN
set -euo pipefail

# Charge <projet>/.claude/jira.env si les credentials ne sont pas déjà dans l'environnement.
# Le script vit dans le plugin (cache), mais le secret reste dans le projet courant.
_JIRA_ENV="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/jira.env"
if [ -z "${JIRA_BASE_URL:-}" ] && [ -f "$_JIRA_ENV" ]; then set -a; . "$_JIRA_ENV"; set +a; fi

: "${JIRA_BASE_URL:?JIRA_BASE_URL non défini — voir le skill jira-pipeline}"
: "${JIRA_EMAIL:?JIRA_EMAIL non défini — voir le skill jira-pipeline}"
: "${JIRA_API_TOKEN:?JIRA_API_TOKEN non défini — voir le skill jira-pipeline}"

if [ "$#" -lt 2 ]; then
  echo "Usage: jira-attach.sh <ISSUE-KEY> <fichier> [fichier...]" >&2
  exit 2
fi

ISSUE="$1"; shift
BASE="${JIRA_BASE_URL%/}"

for f in "$@"; do
  if [ ! -f "$f" ]; then
    echo "⛔ Fichier introuvable : $f" >&2
    exit 1
  fi
  echo "↑ $f → $ISSUE"
  curl --fail --silent --show-error \
    -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
    -X POST \
    -H "X-Atlassian-Token: no-check" \
    -F "file=@${f}" \
    "${BASE}/rest/api/3/issue/${ISSUE}/attachments" >/dev/null
done

echo "✅ $(($#)) fichier(s) attaché(s) à $ISSUE"
