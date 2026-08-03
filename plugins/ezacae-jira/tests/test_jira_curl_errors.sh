#!/usr/bin/env bash
# Test PASS/FAIL de la remontée d'erreur des helpers JIRA (RD-29).
#
# Hors-ligne : un faux Jira écoute sur 127.0.0.1 et répond 404 avec le corps
# d'erreur réel. Aucun appel sortant, aucun credential réel utilisé.
#
# Trois invariants, dans l'ordre de gravité :
#   1. Un téléchargement échoué ne laisse AUCUN fichier à la destination.
#      Un fichier vide, ou contenant le JSON d'erreur, se fait passer pour la
#      pièce jointe : c'est de la corruption silencieuse.
#   2. Le message de Jira arrive sur stderr.
#   3. Le stdout d'un appel échoué reste vide (il est consommé par jq et par la
#      garde de statut ; y écrire ferait échouer le parsing en silence).
#
# Lancer : bash plugins/ezacae-jira/tests/test_jira_curl_errors.sh
set -uo pipefail

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$ICI/../scripts"
FAUX_JIRA="${FAUX_JIRA:-$ICI/fake-jira.py}"

PASS=0; FAIL=0
ok()   { echo "PASS  $1"; PASS=$((PASS+1)); }
nope() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }

command -v python3 >/dev/null 2>&1 || { echo "⛔ python3 requis"; exit 1; }

TMP=$(mktemp -d)
trap 'kill "${SRV_PID:-}" 2>/dev/null; rm -rf "$TMP"' EXIT

# --- Faux Jira -----------------------------------------------------------------
python3 "$FAUX_JIRA" > "$TMP/port" 2>"$TMP/srv.err" &
SRV_PID=$!
for _ in $(seq 1 50); do [ -s "$TMP/port" ] && break; sleep 0.1; done
PORT=$(cat "$TMP/port")
[ -n "$PORT" ] || { echo "⛔ faux Jira non démarré : $(cat "$TMP/srv.err")"; exit 1; }

export JIRA_BASE_URL="http://127.0.0.1:$PORT"
export JIRA_EMAIL="test@example.invalid"
export JIRA_API_TOKEN="jeton-de-test"

# --- 1. Un téléchargement échoué ne laisse pas de fichier ----------------------
DEST="$TMP/pj"
"$SCRIPTS/jira-download.sh" RD-1 "$DEST" >"$TMP/dl.out" 2>"$TMP/dl.err"
RC=$?

[ "$RC" -ne 0 ] \
  && ok "jira-download.sh sort en erreur quand le contenu de la PJ échoue (rc=$RC)" \
  || nope "jira-download.sh sort en succès alors que le téléchargement a échoué (rc=0)"

if [ -e "$DEST/conception.md" ]; then
  TAILLE=$(wc -c <"$DEST/conception.md" | tr -d ' ')
  if grep -q "errorMessages" "$DEST/conception.md" 2>/dev/null; then
    nope "conception.md contient le JSON d'erreur de Jira ($TAILLE octets) — corruption silencieuse"
  else
    nope "conception.md existe alors que le téléchargement a échoué ($TAILLE octets) — faux fichier"
  fi
else
  ok "aucun fichier laissé à la destination après un téléchargement échoué"
fi

# --- 2. Le message de Jira arrive sur stderr -----------------------------------
grep -q "existe pas" "$TMP/dl.err" \
  && ok "le message de Jira est visible sur stderr" \
  || nope "stderr ne contient pas le message de Jira — sortie obtenue : $(tr -d '\n' <"$TMP/dl.err")"

# --- 3. Le stdout d'un appel échoué reste vide ---------------------------------
# shellcheck disable=SC1090
. "$SCRIPTS/jira-lib.sh"
OUT=$(jira_curl "$JIRA_BASE_URL/rest/api/3/issue/RD-INEXISTANT" 2>"$TMP/curl.err")
[ -z "$OUT" ] \
  && ok "stdout reste vide sur un appel échoué (jq et la garde de statut protégés)" \
  || nope "stdout pollué par le corps d'erreur : $(printf '%s' "$OUT" | head -c 120)"

grep -q "existe pas" "$TMP/curl.err" \
  && ok "jira_curl écrit le message de Jira sur stderr" \
  || nope "jira_curl masque le message : $(tr -d '\n' <"$TMP/curl.err")"

echo "----"
echo "Résultat : PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
