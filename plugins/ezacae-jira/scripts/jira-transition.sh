#!/usr/bin/env bash
# Transitionne un ticket JIRA vers un statut cible (par NOM), via l'API REST v3.
#
# Garde pipeline INTÉGRÉE : refuse une transition hors séquence Mike⇄Sarah pour
# un ticket déjà dans un statut du pipeline (même filet de sécurité que le hook
# jira-guard.sh, partagé via jira-lib.sh). Comme ce script est auto-autorisé en
# Bash, la garde DOIT vivre ici pour ne pas être contournée.
#
# Usage : jira-transition.sh <ISSUE-KEY> <STATUT-CIBLE> [--worklog DURÉE] [--comment TEXTE]
#   ex.  jira-transition.sh CRM-337 "CONCEPTION OK"
#        jira-transition.sh CRM-337 EXAMINER --worklog 30m --comment "MR créée — revue"
#   --worklog : temps consacré (certaines transitions à écran l'exigent, ex. 30m, 1h)
#   --comment : commentaire de passation posté après la transition
# Requiert : JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN, jq
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-lib.sh"
jira_load_env
jira_require_creds
command -v jq >/dev/null 2>&1 || { echo "⛔ jq requis (brew install jq)" >&2; exit 1; }

[ "$#" -ge 2 ] || { echo "Usage: jira-transition.sh <ISSUE-KEY> <STATUT-CIBLE> [--worklog DURÉE] [--comment TEXTE]" >&2; exit 2; }
ISSUE="$1"; TARGET="$2"; shift 2

WORKLOG=""; COMMENT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --worklog) WORKLOG="${2:?--worklog requiert une durée (ex. 30m)}"; shift 2 ;;
    --comment) COMMENT="${2:?--comment requiert un texte}"; shift 2 ;;
    *) echo "⛔ Option inconnue : $1" >&2; exit 2 ;;
  esac
done

CUR=$(jira_status "$ISSUE")
[ -n "$CUR" ] || { echo "⛔ Statut courant de $ISSUE introuvable." >&2; exit 1; }

# Garde de statut (partagée avec le hook jira-guard.sh).
if ! REASON=$(jira_pipeline_guard "$CUR" "$TARGET"); then
  echo "⛔ $REASON" >&2
  exit 3
fi

TRID=$(jira_transition_id_for_status "$ISSUE" "$TARGET")
if [ -z "$TRID" ]; then
  echo "⛔ Aucune transition de '$CUR' vers '$TARGET' sur $ISSUE. Transitions disponibles :" >&2
  jira_curl "$(jira_base)/rest/api/3/issue/${ISSUE}/transitions" \
    | jq -r '.transitions[]? | "  • \(.name) → \(.to.name)"' >&2
  exit 4
fi

# Corps de la transition (+ worklog éventuel pour les transitions à écran).
BODY=$(jq -n --arg id "$TRID" '{transition: {id: $id}}')
if [ -n "$WORKLOG" ]; then
  BODY=$(printf '%s' "$BODY" | jq --arg w "$WORKLOG" '. + {update: {worklog: [{add: {timeSpent: $w}}]}}')
fi

printf '%s' "$BODY" | jira_curl -X POST -H "Content-Type: application/json" --data @- \
  "$(jira_base)/rest/api/3/issue/${ISSUE}/transitions" >/dev/null
echo "✅ $ISSUE : $CUR → $TARGET"

if [ -n "$COMMENT" ]; then
  printf '%s' "$COMMENT" | jira_text_to_adf | jq '{body: .}' \
    | jira_curl -X POST -H "Content-Type: application/json" --data @- \
      "$(jira_base)/rest/api/3/issue/${ISSUE}/comment" >/dev/null
  echo "💬 commentaire ajouté à $ISSUE"
fi
