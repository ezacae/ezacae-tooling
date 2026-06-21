#!/usr/bin/env bash
# Récupère les pièces jointes d'un ticket JIRA via l'API REST v3.
#
# Usage : jira-download.sh <ISSUE-KEY> [dossier-destination] [filtre-nom]
#   - dossier-destination : défaut = ./jira-<ISSUE-KEY>
#   - filtre-nom          : ne télécharge que les PJ dont le nom contient cette chaîne
# Requiert : JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN, jq
set -euo pipefail

# Credentials + helpers REST partagés (chargement de .claude/jira.env inclus).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-lib.sh"
jira_load_env
jira_require_creds
command -v jq >/dev/null 2>&1 || { echo "⛔ jq requis (brew install jq)" >&2; exit 1; }

if [ "$#" -lt 1 ]; then
  echo "Usage: jira-download.sh <ISSUE-KEY> [dossier] [filtre-nom]" >&2
  exit 2
fi

ISSUE="$1"
DEST="${2:-./jira-${ISSUE}}"
FILTER="${3:-}"
mkdir -p "$DEST"

META=$(jira_curl "$(jira_base)/rest/api/3/issue/${ISSUE}?fields=attachment")

COUNT=0
while IFS=$'\t' read -r name url; do
  [ -z "$name" ] && continue
  if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then continue; fi
  jira_curl -L "$url" -o "${DEST}/${name}"
  echo "↓ ${DEST}/${name}"
  COUNT=$((COUNT + 1))
done < <(echo "$META" | jq -r '.fields.attachment[]? | "\(.filename)\t\(.content)"')

echo "✅ $COUNT pièce(s) jointe(s) récupérée(s) dans $DEST"
