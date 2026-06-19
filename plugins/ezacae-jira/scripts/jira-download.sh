#!/usr/bin/env bash
# Récupère les pièces jointes d'un ticket JIRA via l'API REST v3.
#
# Usage : jira-download.sh <ISSUE-KEY> [dossier-destination] [filtre-nom]
#   - dossier-destination : défaut = ./jira-<ISSUE-KEY>
#   - filtre-nom          : ne télécharge que les PJ dont le nom contient cette chaîne
# Requiert : JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN, jq
set -euo pipefail

# Charge <projet>/.claude/jira.env si les credentials ne sont pas déjà dans l'environnement.
# Le script vit dans le plugin (cache), mais le secret reste dans le projet courant.
_JIRA_ENV="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/jira.env"
if [ -z "${JIRA_BASE_URL:-}" ] && [ -f "$_JIRA_ENV" ]; then set -a; . "$_JIRA_ENV"; set +a; fi

: "${JIRA_BASE_URL:?JIRA_BASE_URL non défini — voir le skill jira-pipeline}"
: "${JIRA_EMAIL:?JIRA_EMAIL non défini — voir le skill jira-pipeline}"
: "${JIRA_API_TOKEN:?JIRA_API_TOKEN non défini — voir le skill jira-pipeline}"
command -v jq >/dev/null 2>&1 || { echo "⛔ jq requis (brew install jq)" >&2; exit 1; }

if [ "$#" -lt 1 ]; then
  echo "Usage: jira-download.sh <ISSUE-KEY> [dossier] [filtre-nom]" >&2
  exit 2
fi

ISSUE="$1"
DEST="${2:-./jira-${ISSUE}}"
FILTER="${3:-}"
BASE="${JIRA_BASE_URL%/}"
mkdir -p "$DEST"

META=$(curl --fail --silent --show-error \
  -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "${BASE}/rest/api/3/issue/${ISSUE}?fields=attachment")

COUNT=0
while IFS=$'\t' read -r name url; do
  [ -z "$name" ] && continue
  if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then continue; fi
  curl --fail --silent --show-error -L \
    -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
    "$url" -o "${DEST}/${name}"
  echo "↓ ${DEST}/${name}"
  COUNT=$((COUNT + 1))
done < <(echo "$META" | jq -r '.fields.attachment[]? | "\(.filename)\t\(.content)"')

echo "✅ $COUNT pièce(s) jointe(s) récupérée(s) dans $DEST"
