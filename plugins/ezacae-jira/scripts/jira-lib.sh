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
  # ⚠️ Ce trap est PROCESS-WIDE, pas local à la fonction : bash n'a pas de trap
  # scopé à une fonction. Il écrase le handler INT/TERM du processus appelant
  # pendant l'appel curl, puis le remet à "-" (défaut) juste après — donc si
  # l'appelant avait posé son propre trap INT/TERM, il est perdu, pas restauré.
  # Aucun appelant ne pose de trap aujourd'hui (vérifié) ; à surveiller si l'un
  # en pose un jour.
  trap 'rm -f "$tmp"' INT TERM

  # La substitution de commande est protégée du set -e des appelants (même
  # idiome que jira_curl ci-dessus) : sans le && rc=0 || rc=$?, un échec
  # transport (DNS, connexion refusée, timeout — curl rc≠0) ferait sortir le
  # script AVANT cette ligne sous set -e, laissant le .part.* orphelin et
  # perdant le message d'erreur (cf. conception RD-29, Corrections de revue #1).
  code=$(curl --silent --show-error --write-out '%{http_code}' \
           --max-time "${JIRA_CURL_MAX_TIME:-20}" \
           -u "$JIRA_EMAIL:$JIRA_API_TOKEN" -o "$tmp" "$@") && rc=0 || rc=$?
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

# Porte de validation humaine (RD-43, spec brique 1 §3) : les statuts cibles que
# SEUL un humain pose, en cliquant lui-même dans Jira. L'assistant, dont les
# scripts sont l'unique chemin vers les tickets, ne fait jamais cette transition,
# quel que soit le statut courant (y compris hors pipeline : la cible seule
# décide). Un statut par ligne, en majuscules ASCII.
JIRA_HUMAN_GATES="CONCEPTION OK"

# $1 = statut cible (majuscules) → 0 si c'est une porte humaine.
jira_is_human_gate() {
  printf '%s\n' "$JIRA_HUMAN_GATES" | grep -qxF "$1"
}

# Graphe des transitions légales du pipeline : "SOURCE>CIBLE".
# CONCEPTION VALIDATION → CONCEPTION OK n'y figure plus : c'est la porte humaine.
JIRA_LEGAL_TRANSITIONS="NOUVEAU>CADRAGE
CADRAGE>CONCEPTION
CONCEPTION>CONCEPTION VALIDATION
CONCEPTION VALIDATION>CONCEPTION
CONCEPTION OK>EN COURS
EN COURS>EXAMINER
EXAMINER>EN COURS
EXAMINER>RECETTE INTERNE"

# Décision de garde. $1 = statut courant, $2 = statut cible (noms bruts).
# Émet un message explicatif sur stdout ; retourne 0 (autorisé) / 1 (refusé).
# - cible = porte humaine (RD-43)     → refusé, toujours, avant toute autre règle
# - statut courant hors pipeline      → autorisé (les autres workflows ignorés)
# - cible = annulation (globale)      → autorisé
# - transition dans le graphe légal   → autorisé
# - sinon                             → refusé, avec la liste des étapes légales
jira_pipeline_guard() {
  local cur_u tgt_u legal_from
  cur_u=$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')
  tgt_u=$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')

  if jira_is_human_gate "$tgt_u"; then
    echo "Porte de validation : '$2' se pose par validation humaine dans Jira, jamais par l'assistant. Demande au responsable produit de lire les documents et de changer lui-même le statut du ticket ; ne contourne pas (ni MCP, ni curl)."
    return 1
  fi

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

# --- Résolution d'assigné (RD-29) -----------------------------------------------

# $1 = chaîne → 0 si elle ressemble à un accountId Jira (24 caractères
# hexadécimaux — mesuré : 6256cf820630bd0070761e65 — ou une forme contenant
# ':', ex. compte de service). 1 sinon (probablement un nom d'affichage).
jira_looks_like_account_id() {
  case "$1" in
    *:*) return 0 ;;
  esac
  [[ "$1" =~ ^[0-9a-fA-F]{24}$ ]]
}

# $1 = ISSUE-KEY, $2 = nom d'affichage → "accountId<TAB>displayName" sur stdout
# si une seule correspondance (découpé par l'appelant via IFS=$'\t' read -r) ;
# sinon refuse (message sur stderr, rc≠0). Renvoyer aussi displayName évite à
# l'appelant de refaire le même appel réseau pour l'afficher (Correction 2,
# RD-29 : jira-edit.sh relançait /user/assignable/search une seconde fois pour
# le seul displayName). L'encodage de la requête est délégué à curl
# (--get --data-urlencode), jamais fait à la main.
jira_resolve_assignee() {
  local issue="$1" name="$2" result n
  result=$(jira_curl --get --data-urlencode "query=$name" \
    "$(jira_base)/rest/api/3/user/assignable/search?issueKey=$issue") || return 1
  n=$(printf '%s' "$result" | jq 'length')
  case "$n" in
    0)
      echo "⛔ aucun utilisateur assignable ne correspond à « $name » sur $issue" >&2
      return 1
      ;;
    1)
      printf '%s' "$result" | jq -r '.[0] | "\(.accountId)\t\(.displayName)"'
      return 0
      ;;
    *)
      {
        echo "⛔ plusieurs utilisateurs assignables correspondent à « $name » sur $issue — précise avec un accountId :"
        printf '%s' "$result" | jq -r '.[] | "   • \(.displayName) — \(.accountId)"'
      } >&2
      return 1
      ;;
  esac
}

# --- ADF (Atlassian Document Format) ------------------------------------------

# Programme jq définissant `adf_render` : un document ADF → texte lisible (RD-23).
#
# Deux exigences distinctes :
#  1. rendre les frontières de blocs visibles (une ligne vide entre les blocs, un
#     tiret par puce, des délimiteurs autour des blocs de code) — l'ancien filtre
#     concaténait tout, d'où le « RD-17PÉRIMÈTRE RÉEL » illisible ;
#  2. ne JAMAIS jeter de contenu : tout type de nœud inconnu retombe sur une
#     extraction récursive. C'est aussi un correctif — les cartes de ticket liées
#     (inlineCard) disparaissaient, d'où le « The linked issue -  has been resolved ».
#
# Stocké en VARIABLE : ce fichier ne doit rien exécuter ni rien écrire au
# chargement, car le hook jira-guard.sh parse son propre stdout en JSON.
# Se termine par un ';' → le corps du programme se concatène SANS barre verticale :
#   jq -r "$JIRA_JQ_ADF_RENDER adf_render"
JIRA_JQ_ADF_RENDER='
  def adf_inline:
    if type == "array" then map(adf_inline) | join("")
    elif type != "object" then ""
    elif .type == "text" then (.text // "")
    elif .type == "hardBreak" then "\n"
    elif (.attrs.text? // null) != null then .attrs.text
    elif (.attrs.url? // null) != null then .attrs.url
    elif (.attrs.shortName? // null) != null then .attrs.shortName
    elif .content? then (.content | adf_inline)
    else "" end;

  def indent($n): split("\n") | map((" " * $n) + .) | join("\n");

  def adf_block:
    if type != "object" then ""
    elif .type == "paragraph" then (.content // [] | adf_inline)
    elif .type == "heading" then (("#" * (.attrs.level // 1)) + " " + (.content // [] | adf_inline))
    elif .type == "codeBlock" then
      ("```" + (.attrs.language // "") + "\n" + (.content // [] | adf_inline) + "\n```")
    elif .type == "rule" then "---"
    elif .type == "blockquote" then
      ((.content // [] | map(adf_block) | join("\n")) | split("\n") | map("> " + .) | join("\n"))
    elif .type == "bulletList" then
      (.content // [] | map("- " + ((.content // [] | map(adf_block) | join("\n")) | indent(2) | ltrimstr("  "))) | join("\n"))
    elif .type == "orderedList" then
      ((.attrs.order // 1) as $start
       | .content // [] | to_entries
       | map((($start + .key) | tostring) + ". "
             + ((.value.content // [] | map(adf_block) | join("\n")) | indent(3) | ltrimstr("   ")))
       | join("\n"))
    elif .type == "table" then
      (.content // [] | map("| " + ((.content // []) | map(adf_inline) | join(" | ")) + " |") | join("\n"))
    elif .content? then (.content | map(adf_block) | join("\n"))
    else adf_inline end;

  # Les blocs vides sont écartés AVANT le join : les lignes vides du texte source
  # produisent des paragraphes vides qui doubleraient les séparations.
  def adf_render: (.content // []) | map(adf_block) | map(select(. != "")) | join("\n\n");
'

# Programme jq d'origine (RD-15) : une ligne = un paragraphe. Conservé mot pour
# mot comme repli — c'est lui qui garantit qu'un envoi aboutit toujours (RD-23).
JIRA_JQ_TEXT_TO_ADF_FLAT='{type:"doc",version:1,content:(
    rtrimstr("\n") | split("\n") |
    map(if . == "" then {type:"paragraph"}
        else {type:"paragraph",content:[{type:"text",text:.}]} end)
  )}'

# Convertisseur ORIENTÉ LIGNE (RD-23). Ne promeut que les constructions ancrées
# en début de ligne : titres, listes, blocs de code. Aucune recherche de paires
# de signes au milieu des phrases — nos textes sont pleins de noms de fichiers et
# de chemins que cela corromprait en silence. Toute ligne non reconnue redevient
# un paragraphe, à l'identique de JIRA_JQ_TEXT_TO_ADF_FLAT.
JIRA_JQ_TEXT_TO_ADF='
  def para($s): if $s == "" then {type:"paragraph"}
                else {type:"paragraph",content:[{type:"text",text:$s}]} end;
  def heading($lvl; $s): {type:"heading",attrs:{level:$lvl},content:[{type:"text",text:$s}]};
  # ⚠️ La forme produite par item() et code() est vérifiée par JIRA_JQ_ADF_VALID
  # (plus bas). Toute évolution ici doit y être répercutée, sinon le filet de
  # sécurité dégrade à tort ou laisse passer une structure réellement invalide.
  def item($s): {type:"listItem",content:[para($s)]};
  def code($lang; $lines):
    {type:"codeBlock"}
    + (if $lang == "" then {} else {attrs:{language:$lang}} end)
    + (if ($lines|length) == 0 then {} else {content:[{type:"text",text:($lines|join("\n"))}]} end);

  # Referme le bloc en cours (liste, ou bloc de code jamais fermé) et le verse
  # dans .out. Un bloc de code non fermé DÉGRADE : sa ligne d ouverture et ses
  # lignes accumulées ressortent en paragraphes, dans l ordre d origine.
  def flush:
    if .mode == "bullet" then
      .out += [{type:"bulletList",content:.buf}] | .mode = "none" | .buf = []
    elif .mode == "ordered" then
      .out += [ {type:"orderedList"}
                + (if .order == 1 then {} else {attrs:{order:.order}} end)
                + {content:.buf} ]
      | .mode = "none" | .buf = []
    elif .mode == "fence" then
      .out += ([para(.raw)] + (.buf | map(para(.))))
      | .mode = "none" | .buf = [] | .lang = "" | .raw = ""
    else . end;

  rtrimstr("\n") | split("\n")
  | reduce .[] as $line ({out:[], mode:"none", buf:[], order:1, lang:"", raw:""};
      ($line | capture("^```(?<lang>.*)$") // null) as $fence
      | ($line | capture("^(?<h>#{2,3}) (?<t>\\S.*)$") // null) as $head
      | ($line | capture("^- (?<t>\\S.*)$") // null) as $bul
      | ($line | capture("^(?<n>[0-9]+)\\. (?<t>\\S.*)$") // null) as $ord
      # Priorité maximale au bloc de code : à l intérieur, AUCUNE promotion.
      # C est ce qui protège les extraits shell (« # commentaire » ne devient
      # pas un titre, « -f fichier » ne devient pas une puce).
      | if .mode == "fence" then
          (if ($line | test("^```\\s*$")) then
             .out += [code(.lang; .buf)]
             | .mode = "none" | .buf = [] | .lang = "" | .raw = ""
           else .buf += [$line] end)
        elif $fence != null then
          # gsub et non ltrimstr/rtrimstr : ces derniers ne retirent QU UNE
          # occurrence, donc "```   bash" laissait language = "  bash".
          flush | .mode = "fence" | .buf = []
          | .lang = ($fence.lang | gsub("^\\s+|\\s+$";"")) | .raw = $line
        elif $head != null then flush | .out += [heading(($head.h|length); $head.t)]
        elif $bul != null then
          (if .mode == "bullet" then . else flush | .mode = "bullet" end)
          | .buf += [item($bul.t)]
        elif $ord != null then
          (if .mode == "ordered" then . else flush | .mode = "ordered" | .order = ($ord.n|tonumber) end)
          | .buf += [item($ord.t)]
        else flush | .out += [para($line)]
        end)
  | flush
  | {type:"doc",version:1,content:.out}
'

# Invariants de validité ADF vérifiables hors-ligne (sous-ensemble couvrant nos
# erreurs possibles, pas le schéma officiel de Jira). Booléen sur stdout.
#
# ⚠️ Ces règles décrivent la forme produite par item() et code() dans
# JIRA_JQ_TEXT_TO_ADF (plus haut) : les deux évoluent ensemble.
JIRA_JQ_ADF_VALID='
  ([.. | objects | select(.type=="text") | select((.text // "") == "")] | length) == 0
  and ([.. | objects | select(.type=="listItem") | (.content // [])[]
        | select((.type // "") as $t
                 | ($t=="paragraph" or $t=="bulletList" or $t=="orderedList") | not)]
       | length) == 0
  and ([.. | objects | select(.type=="bulletList" or .type=="orderedList")
        | (.content // [])[] | select(.type != "listItem")] | length) == 0
  and ([.. | objects | select(.type=="heading")
        | select(((.attrs.level // 0) | (. >= 1 and . <= 6)) | not)] | length) == 0
  and ([.. | objects | select(.type=="codeBlock") | (.content // [])[]
        | select(.type != "text" or has("marks"))] | length) == 0
'

# Convertit du texte multi-lignes (stdin) en document ADF sur stdout.
#
# Filet de sécurité (RD-23) : si la structure produite viole les invariants de
# validité, on replie sur la conversion plate d'origine plutôt que de risquer un
# refus de l'API. Un envoi ne doit JAMAIS échouer à cause de la mise en forme —
# dans jira-transition.sh le commentaire part APRÈS la transition, donc un refus
# laisserait le ticket transitionné sans passation, sans pouvoir rejouer (la
# garde de statut interdit CONCEPTION → CONCEPTION).
jira_text_to_adf() {
  local input adf
  input=$(cat)
  adf=$(printf '%s' "$input" | jq -Rs "$JIRA_JQ_TEXT_TO_ADF")
  if printf '%s' "$adf" | jq -e "$JIRA_JQ_ADF_VALID" >/dev/null 2>&1; then
    # $(...) supprime les retours à la ligne finaux : jq en émet exactement un,
    # et la non-régression octet pour octet en dépend.
    printf '%s\n' "$adf"
  else
    echo "⚠️  Structure ADF invalide — repli sur la conversion plate." >&2
    printf '%s' "$input" | jq -Rs "$JIRA_JQ_TEXT_TO_ADF_FLAT"
  fi
}
