#!/usr/bin/env bash
# Bibliothèque partagée des helpers JIRA REST (plugin ezacae-jira).
#
# Sourcée par les scripts jira-*.sh ET par le hook jira-guard.sh, afin que la
# garde de statut du pipeline soit définie UNE SEULE FOIS (pas de divergence
# entre la garde du hook MCP et celle des scripts Bash).
#
# ⚠️ Ne RIEN écrire sur stdout au chargement : le hook jira-guard.sh parse son
# propre stdout en JSON. Les fonctions ci-dessous n'émettent que sur demande.

# --- Credentials ---------------------------------------------------------------

# Charge <projet>/.claude/jira.env si les credentials ne sont pas déjà exportés.
# Le script vit dans le plugin (cache), mais le secret reste dans le projet courant.
jira_load_env() {
  local env_file="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/jira.env"
  if [ -z "${JIRA_BASE_URL:-}" ] && [ -f "$env_file" ]; then
    set -a; . "$env_file"; set +a
  fi
}

# Avorte (via ${var:?}) si un credential manque. À n'appeler que dans un script
# (jamais dans le hook, qui doit rester tolérant).
jira_require_creds() {
  : "${JIRA_BASE_URL:?JIRA_BASE_URL non défini — voir le skill jira-pipeline}"
  : "${JIRA_EMAIL:?JIRA_EMAIL non défini — voir le skill jira-pipeline}"
  : "${JIRA_API_TOKEN:?JIRA_API_TOKEN non défini — voir le skill jira-pipeline}"
}

jira_base() { printf '%s' "${JIRA_BASE_URL%/}"; }

# curl authentifié vers l'API JIRA. Le timeout est réglable via JIRA_CURL_MAX_TIME
# (le hook le baisse pour rester dans son budget). Args : passés tels quels à curl.
jira_curl() {
  curl --fail --silent --show-error --max-time "${JIRA_CURL_MAX_TIME:-20}" \
    -u "$JIRA_EMAIL:$JIRA_API_TOKEN" "$@"
}

# --- Lecture -------------------------------------------------------------------

# $1 = ISSUE-KEY → nom du statut courant (vide si introuvable).
jira_status() {
  jira_curl "$(jira_base)/rest/api/3/issue/$1?fields=status" \
    | jq -r '.fields.status.name // empty'
}

# $1 = ISSUE-KEY, $2 = STATUT-CIBLE → id de la transition y menant (insensible à
# la casse, jamais sur le nom de transition). Vide si aucune ne mène à la cible.
# La comparaison se fait ENTIÈREMENT dans jq (ascii_upcase des deux côtés) : un
# `tr` côté shell mettrait les caractères accentués en majuscule selon la locale
# (é→É) alors que `ascii_upcase` les laisse tels quels, d'où un faux négatif sur
# les statuts accentués (ex. « Annulé »).
jira_transition_id_for_status() {
  jira_curl "$(jira_base)/rest/api/3/issue/$1/transitions" \
    | jq -r --arg t "$2" \
      '.transitions[]? | select((.to.name|ascii_upcase)==($t|ascii_upcase)) | .id' | head -n1
}

# --- Garde de statut du pipeline Mike ⇄ Sarah ---------------------------------

# Statuts faisant partie du pipeline (déjà en majuscules ASCII).
jira_is_pipeline_status() {
  case "$1" in
    NOUVEAU|CADRAGE|CONCEPTION|"CONCEPTION VALIDATION"|"CONCEPTION OK"|"EN COURS"|EXAMINER|"RECETTE INTERNE") return 0 ;;
    *) return 1 ;;
  esac
}

# Graphe des transitions légales du pipeline : "SOURCE>CIBLE".
JIRA_LEGAL_TRANSITIONS="NOUVEAU>CADRAGE
CADRAGE>CONCEPTION
CONCEPTION>CONCEPTION VALIDATION
CONCEPTION VALIDATION>CONCEPTION
CONCEPTION VALIDATION>CONCEPTION OK
CONCEPTION OK>EN COURS
EN COURS>EXAMINER
EXAMINER>EN COURS
EXAMINER>RECETTE INTERNE"

# Décision de garde. $1 = statut courant, $2 = statut cible (noms bruts).
# Émet un message explicatif sur stdout ; retourne 0 (autorisé) / 1 (refusé).
# - statut courant hors pipeline      → autorisé (les autres workflows ignorés)
# - cible = annulation (globale)      → autorisé
# - transition dans le graphe légal   → autorisé
# - sinon                             → refusé, avec la liste des étapes légales
jira_pipeline_guard() {
  local cur_u tgt_u legal_from
  cur_u=$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')
  tgt_u=$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')

  if ! jira_is_pipeline_status "$cur_u"; then
    echo "Hors pipeline (statut '$1') — transition autorisée par défaut."; return 0
  fi
  case "$tgt_u" in
    ANNUL*) echo "Annulation autorisée ('$1' → '$2')."; return 0 ;;
  esac
  if printf '%s\n' "$JIRA_LEGAL_TRANSITIONS" | grep -qxF "$cur_u>$tgt_u"; then
    echo "Transition pipeline conforme : '$1' → '$2'."; return 0
  fi
  legal_from=$(printf '%s\n' "$JIRA_LEGAL_TRANSITIONS" | grep -F "$cur_u>" \
    | sed 's/^[^>]*>/→ /' | tr '\n' ' ')
  [ -z "$legal_from" ] && legal_from="(aucune — statut terminal du pipeline)"
  echo "Transition hors pipeline Mike⇄Sarah : '$1' → '$2' n'est pas autorisée. Étapes légales depuis '$1' : ${legal_from}"
  return 1
}

# --- ADF (Atlassian Document Format) ------------------------------------------

# Convertit du texte multi-lignes (stdin) en document ADF (une ligne = un
# paragraphe ; ligne vide = paragraphe vide). Émet l'objet `doc` sur stdout.
jira_text_to_adf() {
  jq -Rs '{type:"doc",version:1,content:(
    rtrimstr("\n") | split("\n") |
    map(if . == "" then {type:"paragraph"}
        else {type:"paragraph",content:[{type:"text",text:.}]} end)
  )}'
}
