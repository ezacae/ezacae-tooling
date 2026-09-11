#!/usr/bin/env bash
# Transitionne un ticket JIRA vers un statut cible (par NOM), via l'API REST v3.
#
# Garde pipeline INTÉGRÉE : refuse une transition hors séquence Mike⇄Sarah pour
# un ticket déjà dans un statut du pipeline (même filet de sécurité que le hook
# jira-guard.sh, partagé via jira-lib.sh). Comme ce script est auto-autorisé en
# Bash, la garde DOIT vivre ici pour ne pas être contournée.
#
# Usage : jira-transition.sh <ISSUE-KEY> <STATUT-CIBLE> [--worklog DURÉE] [--comment TEXTE]
#         jira-transition.sh <ISSUE-KEY> --list
#   ex.  jira-transition.sh CRM-337 "CONCEPTION OK"
#        jira-transition.sh CRM-337 EXAMINER --worklog 30m --comment "MR créée — revue"
#   --worklog : temps consacré (certaines transitions à écran l'exigent, ex. 30m, 1h)
#   --comment : commentaire de passation posté après la transition
#   --list    : lecture seule — affiche les transitions que Jira offre depuis le
#               statut courant (« nom → statut cible »), sans rien changer. Sert à
#               vérifier qu'un type de ticket suit le circuit avant d'en créer un.
# Requiert : JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN, jq
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-lib.sh"
jira_load_env
jira_require_creds
command -v jq >/dev/null 2>&1 || { echo "⛔ jq requis (brew install jq)" >&2; exit 1; }

[ "$#" -ge 2 ] || { echo "Usage: jira-transition.sh <ISSUE-KEY> <STATUT-CIBLE> [--worklog DURÉE] [--comment TEXTE] | <ISSUE-KEY> --list" >&2; exit 2; }
ISSUE="$1"; TARGET="$2"; shift 2

if [ "$TARGET" = "--list" ]; then
  CUR=$(jira_status "$ISSUE")
  echo "Transitions offertes par Jira depuis '${CUR:-?}' sur $ISSUE :"
  jira_transitions "$ISSUE" | jq -r '.transitions[]? | "  • \(.name) → \(.to.name)"'
  exit 0
fi

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

# Un seul appel aux transitions (avec les champs d'écran) : en tirer l'id ET
# les champs requis, sur le même appel que jira_status ci-dessus + celui-ci.
TRANSITIONS_JSON=$(jira_transitions "$ISSUE")
TRID=$(jira_transition_id_for_target "$TRANSITIONS_JSON" "$TARGET")
if [ -z "$TRID" ]; then
  echo "⛔ Aucune transition de '$CUR' vers '$TARGET' sur $ISSUE. Transitions disponibles :" >&2
  printf '%s' "$TRANSITIONS_JSON" | jq -r '.transitions[]? | "  • \(.name) → \(.to.name)"' >&2
  exit 4
fi

# Pré-vol : seul le champ mesuré fatal (worklog) refuse avant envoi. Tout autre
# champ requis (resolution, custom…) est laissé au serveur : les écrans Jira
# portent souvent une valeur par défaut, et un refus côté client fermerait des
# transitions que le serveur accepte (cf. conception RD-29, cas de l'annulation).
REQUIRED_FIELDS=$(jira_required_fields_for_transition "$TRANSITIONS_JSON" "$TRID")
if printf '%s\n' "$REQUIRED_FIELDS" | grep -qxF worklog && [ -z "$WORKLOG" ]; then
  echo "⛔ La transition '$CUR' → '$TARGET' exige un temps consacré. Ajoute --worklog <durée> (ex. 30m)." >&2
  exit 5
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
