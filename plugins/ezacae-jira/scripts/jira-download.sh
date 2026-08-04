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

# Le nom de PJ vient des métadonnées API : un nom contenant '/' (poussé par un
# autre client, Jira ne normalise pas tout) écrirait hors de DEST via '../..'.
# basename le réduit avant tout usage — voir conception RD-29.
#
# Homonymes (même basename, id distincts) : compatible bash 3.2 (pas de tableau
# associatif) — les noms déjà vus sont tenus dans une variable multi-lignes,
# comparée ligne à ligne (grep -Fxq) puisqu'un nom peut contenir des espaces.
COUNT=0
SEEN_NAMES=""
while IFS=$'\t' read -r id name url; do
  [ -z "$name" ] && continue
  BASE=$(basename "$name")
  if [ -n "$FILTER" ] && [[ "$BASE" != *"$FILTER"* ]]; then continue; fi

  if printf '%s\n' "$SEEN_NAMES" | grep -Fxq "$BASE"; then
    STEM="${BASE%.*}"; EXT="${BASE##*.}"
    if [ "$STEM" = "$EXT" ]; then
      WRITE_NAME="${BASE}~${id}"
    else
      WRITE_NAME="${STEM}~${id}.${EXT}"
    fi
    echo "⚠ deuxième pièce jointe nommée « ${BASE} » → ${WRITE_NAME}" >&2
  else
    WRITE_NAME="$BASE"
  fi
  SEEN_NAMES=$(printf '%s\n%s' "$SEEN_NAMES" "$BASE")

  jira_curl_to_file "${DEST}/${WRITE_NAME}" -L "$url"
  echo "↓ ${DEST}/${WRITE_NAME}"
  COUNT=$((COUNT + 1))
done < <(echo "$META" | jq -r '.fields.attachment[]? | "\(.id)\t\(.filename)\t\(.content)"')

echo "✅ $COUNT pièce(s) jointe(s) récupérée(s) dans $DEST"
