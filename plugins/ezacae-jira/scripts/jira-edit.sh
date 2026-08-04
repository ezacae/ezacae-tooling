#!/usr/bin/env bash
# Édite les champs d'un ticket JIRA via l'API REST v3 (PUT /issue/{key}).
# (Équivalent de editJiraIssue côté MCP, mais auto-autorisé et headless-safe.)
#
# Usage : jira-edit.sh <ISSUE-KEY> [options]
#   --summary "..."            résumé (titre)
#   --description "..."        description (texte → ADF)
#   --description-file <f>     description depuis un fichier (texte → ADF)
#   --label <l>                ajoute un label (option répétable)
#   --assignee <accountId|nom|-> (ré)assigne (accountId ou nom d'affichage,
#                              résolu si une seule correspondance) ; '-' pour désassigner
# Requiert : JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN, jq
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-lib.sh"
jira_load_env
jira_require_creds
command -v jq >/dev/null 2>&1 || { echo "⛔ jq requis (brew install jq)" >&2; exit 1; }

[ "$#" -ge 1 ] || { echo "Usage: jira-edit.sh <ISSUE-KEY> [--summary ..] [--description ..|--description-file f] [--label l].. [--assignee id|nom|-]" >&2; exit 2; }
ISSUE="$1"; shift

FIELDS='{}'; LABEL_OPS='[]'

set_field() {  # $1 = nom du champ, $2 = valeur JSON
  FIELDS=$(printf '%s' "$FIELDS" | jq --arg k "$1" --argjson v "$2" '.[$k] = $v')
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --summary)
      set_field summary "$(jq -n --arg s "${2:?--summary requiert une valeur}" '$s')"; shift 2 ;;
    --description)
      set_field description "$(printf '%s' "${2:?--description requiert une valeur}" | jira_text_to_adf)"; shift 2 ;;
    --description-file)
      [ -f "${2:?--description-file requiert un fichier}" ] || { echo "⛔ Fichier introuvable : $2" >&2; exit 1; }
      set_field description "$(jira_text_to_adf < "$2")"; shift 2 ;;
    --label)
      LABEL_OPS=$(printf '%s' "$LABEL_OPS" | jq --arg l "${2:?--label requiert une valeur}" '. + [{add: $l}]'); shift 2 ;;
    --assignee)
      ARG="${2:?--assignee requiert un accountId, un nom d affichage, ou le caractere -}"
      if [ "$ARG" = "-" ]; then
        set_field assignee 'null'
      elif jira_looks_like_account_id "$ARG"; then
        set_field assignee "$(jq -n --arg a "$ARG" '{accountId: $a}')"
      else
        ACCOUNT_ID=$(jira_resolve_assignee "$ISSUE" "$ARG") || exit 1
        DISPLAY_NAME=$(jira_curl --get --data-urlencode "query=$ARG" \
          "$(jira_base)/rest/api/3/user/assignable/search?issueKey=$ISSUE" \
          | jq -r --arg id "$ACCOUNT_ID" '.[] | select(.accountId==$id) | .displayName')
        echo "→ assigné à ${DISPLAY_NAME} (${ACCOUNT_ID})"
        set_field assignee "$(jq -n --arg a "$ACCOUNT_ID" '{accountId: $a}')"
      fi
      shift 2 ;;
    *) echo "⛔ Option inconnue : $1" >&2; exit 2 ;;
  esac
done

if [ "$FIELDS" = '{}' ] && [ "$LABEL_OPS" = '[]' ]; then
  echo "⛔ Aucun champ à modifier." >&2; exit 2
fi

BODY=$(jq -n --argjson f "$FIELDS" --argjson l "$LABEL_OPS" '
  ( if $f == {} then {} else {fields: $f} end )
  + ( if $l == [] then {} else {update: {labels: $l}} end )
')

printf '%s' "$BODY" | jira_curl -X PUT -H "Content-Type: application/json" --data @- \
  "$(jira_base)/rest/api/3/issue/${ISSUE}" >/dev/null
echo "✅ $ISSUE mis à jour"
