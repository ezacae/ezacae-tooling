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

# --- Remontée d'erreur (RD-29) --------------------------------------------------

# Écrit le message d'erreur HTTP de Jira sur STDERR — jamais sur stdout.
# $1 = code HTTP, $2 = corps de la réponse (peut être vide ou non-JSON).
# - Corps JSON avec errorMessages et/ou errors → les deux sont affichés (l'échec
#   d'assignation ne remplit QUE `errors` ; errorMessages seul ne suffit pas).
# - Corps vide ou non-JSON (proxy, HTML) → repli sur le code HTTP + 200 premiers
#   caractères du corps, sur une ligne.
# - Silencieux si JIRA_QUIET_ERRORS=1 (appelants qui s'attendent à un échec).
# - Itère les messages ligne par ligne (jamais `printf ... $msgs` non quoté :
#   les messages sont en français, ils contiennent des espaces).
jira_report_http_error() {
  [ "${JIRA_QUIET_ERRORS:-0}" = "1" ] && return 0
  local code="$1" body="$2" msgs errs
  {
    if [ -n "$body" ] && msgs=$(printf '%s' "$body" | jq -e -r '.errorMessages[]?, (.errors // {} | to_entries[] | "\(.key) : \(.value)")' 2>/dev/null); then
      echo "⛔ Jira a refusé la requête (HTTP $code)"
      printf '%s\n' "$msgs" | while IFS= read -r line; do
        [ -n "$line" ] && printf '   • %s\n' "$line"
      done
    else
      echo "⛔ Jira a refusé la requête (HTTP $code)"
      if [ -n "$body" ]; then
        printf '   • %s\n' "$(printf '%s' "$body" | head -c 200)"
      fi
    fi
  } >&2
}

# curl authentifié vers l'API JIRA. Le timeout est réglable via JIRA_CURL_MAX_TIME
# (le hook le baisse pour rester dans son budget). Args : passés tels quels à curl.
#
# Contrat :
#   2xx → le corps sur stdout, octet pour octet, code de retour 0.
#   non-2xx → rien sur stdout, message sur stderr (jira_report_http_error), rc≠0.
#   échec transport → curl a déjà parlé sur stderr via --show-error, rc≠0.
#
# Refuse -o/--output dans ses arguments : le contrat "rien sur stdout en cas
# d'échec" ne protège pas un fichier de sortie. Utiliser jira_curl_to_file.
jira_curl() {
  local a
  for a in "$@"; do
    case "$a" in
      -o|--output) echo "⛔ jira_curl refuse -o/--output — utiliser jira_curl_to_file" >&2; return 2 ;;
    esac
  done
  local out code body
  out=$(curl --silent --show-error --write-out '\n%{http_code}' \
          --max-time "${JIRA_CURL_MAX_TIME:-20}" \
          -u "$JIRA_EMAIL:$JIRA_API_TOKEN" "$@") || return 1
  code=${out##*$'\n'}
  body=${out%$'\n'*}
  case "$code" in
    2*) printf '%s' "$body"; return 0 ;;
  esac
  jira_report_http_error "$code" "$body"
  return 1
}

# Comme jira_curl, mais écrit le corps 2xx dans <destination> au lieu de stdout —
# pour un contenu binaire ou volumineux (le corps ne passe jamais par une
# variable shell : un octet nul la tronquerait).
#
# $1 = destination, reste = args curl…
#
# - Écrit dans <destination>.part.XXXXXX (même dossier → même système de fichiers).
# - 2xx → mv vers la destination (seule façon d'y créer un fichier).
# - non-2xx ou échec transport → temporaire supprimé, aucun fichier à destination,
#   message sur stderr (corps tronqué à 2000 octets), code non nul.
# - Un trap local nettoie le temporaire sur SIGINT/SIGTERM (un SIGKILL peut
#   laisser un .part.* orphelin — assumé, hors périmètre des tests).
jira_curl_to_file() {
  local dest="$1"; shift
  local tmp code rc
  tmp=$(mktemp "${dest}.part.XXXXXX") || return 1
  trap 'rm -f "$tmp"' INT TERM

  code=$(curl --silent --show-error --write-out '%{http_code}' \
           --max-time "${JIRA_CURL_MAX_TIME:-20}" \
           -u "$JIRA_EMAIL:$JIRA_API_TOKEN" -o "$tmp" "$@")
  rc=$?
  trap - INT TERM

  if [ "$rc" -ne 0 ]; then
    rm -f "$tmp"
    echo "⛔ Échec réseau lors du téléchargement (curl rc=$rc)" >&2
    return 1
  fi

  case "$code" in
    2*)
      mv "$tmp" "$dest"
      return 0
      ;;
    *)
      local body
      body=$(head -c 2000 "$tmp" 2>/dev/null)
      rm -f "$tmp"
      jira_report_http_error "$code" "$body"
      return 1
      ;;
  esac
}

# --- Lecture -------------------------------------------------------------------

# $1 = ISSUE-KEY → nom du statut courant (vide si introuvable).
jira_status() {
  jira_curl "$(jira_base)/rest/api/3/issue/$1?fields=status" \
    | jq -r '.fields.status.name // empty'
}

# $1 = ISSUE-KEY → JSON complet de GET .../transitions?expand=transitions.fields
# (id, nom, statut cible ET champs requis de l'écran de transition). Un seul
# appel : jira-transition.sh en tire l'id de la transition cible ET ses champs
# requis (indice --worklog), sur le même appel qu'avant (pas une requête de plus).
jira_transitions() {
  jira_curl "$(jira_base)/rest/api/3/issue/$1/transitions?expand=transitions.fields"
}

# $1 = JSON de jira_transitions, $2 = STATUT-CIBLE → id de la transition y menant
# (insensible à la casse, jamais sur le nom de transition). Vide si aucune ne
# mène à la cible. La comparaison se fait ENTIÈREMENT dans jq (ascii_upcase des
# deux côtés) : un `tr` côté shell mettrait les caractères accentués en
# majuscule selon la locale (é→É) alors que `ascii_upcase` les laisse tels
# quels, d'où un faux négatif sur les statuts accentués (ex. « Annulé »).
jira_transition_id_for_target() {
  printf '%s' "$1" | jq -r --arg t "$2" \
    '.transitions[]? | select((.to.name|ascii_upcase)==($t|ascii_upcase)) | .id' | head -n1
}

# $1 = JSON de jira_transitions, $2 = id de transition → liste des noms de
# champs requis par l'écran de cette transition (un par ligne, vide si aucun).
jira_required_fields_for_transition() {
  printf '%s' "$1" | jq -r --arg id "$2" \
    '.transitions[]? | select(.id==$id) | .fields // {} | to_entries[] | select(.value.required==true) | .key'
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
