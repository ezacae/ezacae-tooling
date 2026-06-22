#!/usr/bin/env bash
# Crée un ticket JIRA via l'API REST v3 (POST /issue). Affiche la clé créée.
# (Remplace le MCP createJiraIssue — auto-autorisé, headless-safe, sans cloudId.)
#
# Usage : jira-create.sh --project <KEY> --type <NOM|id> --summary "<titre>" \
#                        [--description "…" | --description-file <f>] \
#                        [--label <l>]... [--assignee <accountId>]
#   --type : nom (ex. "Story", "Bug") ou id numérique. Choisir un type dont le
#            workflow porte le pipeline (cf. skill jira-pipeline §3).
# Requiert : JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN, jq
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-lib.sh"
jira_load_env
jira_require_creds
command -v jq >/dev/null 2>&1 || { echo "⛔ jq requis (brew install jq)" >&2; exit 1; }

PROJECT=""; TYPE=""; SUMMARY=""; DESC_ADF=""; LABELS='[]'; ASSIGNEE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project)  PROJECT="${2:?--project requiert une clé}"; shift 2 ;;
    --type)     TYPE="${2:?--type requiert un nom ou id}"; shift 2 ;;
    --summary)  SUMMARY="${2:?--summary requiert un titre}"; shift 2 ;;
    --description)
      DESC_ADF="$(printf '%s' "${2:?--description requiert une valeur}" | jira_text_to_adf)"; shift 2 ;;
    --description-file)
      [ -f "${2:?--description-file requiert un fichier}" ] || { echo "⛔ Fichier introuvable : $2" >&2; exit 1; }
      DESC_ADF="$(jira_text_to_adf < "$2")"; shift 2 ;;
    --label)    LABELS=$(printf '%s' "$LABELS" | jq --arg l "${2:?--label requiert une valeur}" '. + [$l]'); shift 2 ;;
    --assignee) ASSIGNEE="${2:?--assignee requiert un accountId}"; shift 2 ;;
    *) echo "⛔ Option inconnue : $1" >&2; exit 2 ;;
  esac
done

[ -n "$PROJECT" ] || { echo "⛔ --project requis" >&2; exit 2; }
[ -n "$TYPE" ]    || { echo "⛔ --type requis" >&2; exit 2; }
[ -n "$SUMMARY" ] || { echo "⛔ --summary requis" >&2; exit 2; }

# issuetype par id si purement numérique, sinon par nom.
if printf '%s' "$TYPE" | grep -qE '^[0-9]+$'; then
  ITYPE=$(jq -n --arg v "$TYPE" '{id:$v}')
else
  ITYPE=$(jq -n --arg v "$TYPE" '{name:$v}')
fi

FIELDS=$(jq -n --arg p "$PROJECT" --argjson it "$ITYPE" --arg s "$SUMMARY" --argjson l "$LABELS" '
  {project:{key:$p}, issuetype:$it, summary:$s}
  + (if $l == [] then {} else {labels:$l} end)')
[ -n "$DESC_ADF" ] && FIELDS=$(printf '%s' "$FIELDS" | jq --argjson d "$DESC_ADF" '.description = $d')
[ -n "$ASSIGNEE" ] && FIELDS=$(printf '%s' "$FIELDS" | jq --arg a "$ASSIGNEE" '.assignee = {accountId:$a}')

RESP=$(jq -n --argjson f "$FIELDS" '{fields:$f}' \
  | jira_curl -X POST -H "Content-Type: application/json" --data @- "$(jira_base)/rest/api/3/issue")
KEY=$(printf '%s' "$RESP" | jq -r '.key // empty')
[ -n "$KEY" ] || { echo "⛔ Création échouée : $RESP" >&2; exit 1; }
echo "✅ ticket créé : $KEY"
