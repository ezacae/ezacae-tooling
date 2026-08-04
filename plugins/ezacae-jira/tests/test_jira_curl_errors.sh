#!/usr/bin/env bash
# Test PASS/FAIL de la remontée d'erreur des helpers JIRA (RD-29).
#
# Hors-ligne : un faux Jira (fake-jira.py) écoute sur 127.0.0.1 et répond avec
# les corps d'erreur réels mesurés sur le vrai Jira. Aucun appel sortant,
# aucun credential réel. Style aligné sur test_jira_guard.sh (HERE, PASS/FAIL).
#
# Invariants couverts, dans l'ordre de gravité de la conception RD-29 :
#   1. Le message de Jira arrive sur stderr — jamais sur stdout (qui est
#      consommé par jq et par la garde de statut).
#   2. errorMessages ET errors sont tous deux remontés (l'échec d'assignation
#      ne remplit QUE `errors`).
#   3. Un corps non-JSON (HTML) se replie sur le code HTTP.
#   4. Le jeton n'apparaît jamais sur stdout ni sur stderr d'un appel échoué.
#   5. Un téléchargement échoué ne laisse aucun fichier ni `.part.*` derrière lui.
#   6. Deux pièces jointes homonymes produisent deux fichiers distincts, comptés.
#   7. Un nom de pièce jointe contenant '..' reste confiné dans DEST (basename).
#   8. Le pré-vol --worklog refuse sans émettre de POST ; les autres champs
#      requis (resolution) sont tentés quand même.
#   9. La comparaison de statut cible reste correcte sur un accent (« Annulé »).
#  10. --assignee par nom d'affichage : une correspondance / zéro / plusieurs.
#
# Lancer : bash plugins/ezacae-jira/tests/test_jira_curl_errors.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$HERE/../scripts"
FAUX_JIRA="${FAUX_JIRA:-$HERE/fake-jira.py}"
FIXTURES="$HERE/fixtures/rd29"

PASS=0; FAIL=0
ok()   { echo "PASS  $1"; PASS=$((PASS+1)); }
nope() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }

command -v python3 >/dev/null 2>&1 || { echo "⛔ python3 requis pour le faux Jira — test ignoré." >&2; exit 0; }

TMP=$(mktemp -d)
trap 'kill "${SRV_PID:-}" 2>/dev/null; rm -rf "$TMP"' EXIT

# --- Démarrage du faux Jira ------------------------------------------------------
python3 "$FAUX_JIRA" > "$TMP/port" 2>"$TMP/srv.err" &
SRV_PID=$!
for _ in $(seq 1 50); do [ -s "$TMP/port" ] && break; sleep 0.1; done
PORT=$(cat "$TMP/port" 2>/dev/null)
[ -n "$PORT" ] || { echo "⛔ faux Jira non démarré : $(cat "$TMP/srv.err" 2>/dev/null)"; exit 1; }

export JIRA_BASE_URL="http://127.0.0.1:$PORT"
export JIRA_EMAIL="test@example.invalid"
export JIRA_API_TOKEN="jeton-secret-de-test"

# shellcheck disable=SC1090
. "$SCRIPTS/jira-lib.sh"

post_count() { curl -s "$JIRA_BASE_URL/post-count" | jq -r '.count'; }
search_count() { curl -s "$JIRA_BASE_URL/search-count" | jq -r '.count'; }

# === 1-4. jira_curl : message, deux champs, non-JSON, stdout, jeton ==============

OUT=$(jira_curl "$(jira_base)/rest/api/3/issue/RD-404" 2>"$TMP/e1")
[ -z "$OUT" ] && ok "jira_curl : stdout vide sur 404" || nope "jira_curl : stdout pollué sur 404 : $(printf '%s' "$OUT" | head -c 120)"
grep -q "n'existe pas" "$TMP/e1" && ok "jira_curl : message Jira sur stderr (404, errorMessages)" \
  || nope "jira_curl : message absent de stderr (404) : $(tr -d '\n' <"$TMP/e1")"

jira_curl "$(jira_base)/rest/api/3/issue/RD-400ERRORS" >"$TMP/o2" 2>"$TMP/e2"
[ ! -s "$TMP/o2" ] && ok "jira_curl : stdout vide sur 400 (errors seul)" || nope "jira_curl : stdout non vide sur 400"
grep -q "assignee" "$TMP/e2" && ok "jira_curl : le champ 'errors' (sans errorMessages) est remonté" \
  || nope "jira_curl : 'errors' non remonté quand errorMessages est vide : $(tr -d '\n' <"$TMP/e2")"

jira_curl "$(jira_base)/rest/api/3/issue/RD-401HTML" >"$TMP/o3" 2>"$TMP/e3"
[ ! -s "$TMP/o3" ] && ok "jira_curl : stdout vide sur 401 HTML" || nope "jira_curl : stdout non vide sur 401 HTML"
grep -q "401" "$TMP/e3" && ok "jira_curl : repli sur le code HTTP pour un corps non-JSON" \
  || nope "jira_curl : pas de repli sur le code HTTP pour un corps HTML : $(tr -d '\n' <"$TMP/e3")"

grep -q "jeton-secret-de-test" "$TMP/e1" "$TMP/e2" "$TMP/e3" \
  && nope "le jeton apparaît sur stderr" || ok "le jeton n'apparaît jamais sur stderr"

# === 5. Téléchargement échoué : aucun fichier, aucun .part.* =====================

DEST="$TMP/pj-dlfail"
"$SCRIPTS/jira-download.sh" RD-DLFAIL "$DEST" >"$TMP/dl.out" 2>"$TMP/dl.err"
RC=$?
[ "$RC" -ne 0 ] && ok "jira-download.sh sort en erreur si une PJ échoue (rc=$RC)" \
  || nope "jira-download.sh sort en succès malgré l'échec (rc=0)"
if [ -e "$DEST/disparue.md" ]; then
  nope "disparue.md existe malgré l'échec du téléchargement — corruption silencieuse"
else
  ok "aucun fichier laissé après un téléchargement échoué"
fi
if find "$DEST" -maxdepth 1 -name '*.part.*' 2>/dev/null | grep -q .; then
  nope "un fichier .part.* traîne après l'échec"
else
  ok "aucun .part.* laissé après l'échec"
fi
grep -q "existe pas" "$TMP/dl.err" && ok "jira-download.sh affiche le message Jira sur stderr" \
  || nope "jira-download.sh ne montre pas le message Jira : $(tr -d '\n' <"$TMP/dl.err")"

# === 5bis. Correction 1 (bloquant) : échec transport sous set -e =================
# Sous set -e (présent dans les appelants réels), une substitution de commande
# non protégée tue le script AVANT le nettoyage du .part.* et avant le message
# — cf. conception, "Corrections de revue" #1. Reproduction fidèle : la fonction
# est appelée dans un sous-shell bash -c avec set -euo pipefail, exactement les
# options des appelants (jira-download.sh etc.), contre un port fermé local
# (127.0.0.1:1 → connexion refusée immédiate, pas de dépendance réseau externe).

DEST_NET="$TMP/pj-netfail/cible.bin"
mkdir -p "$(dirname "$DEST_NET")"
NETFAIL_SCRIPTS="$SCRIPTS" NETFAIL_DEST="$DEST_NET" \
  JIRA_EMAIL="$JIRA_EMAIL" JIRA_API_TOKEN="$JIRA_API_TOKEN" \
  bash -c '
    set -euo pipefail
    . "$NETFAIL_SCRIPTS/jira-lib.sh"
    jira_curl_to_file "$NETFAIL_DEST" "http://127.0.0.1:1/nope"
  ' >"$TMP/netfail.out" 2>"$TMP/netfail.err"
RC_NET=$?

if find "$(dirname "$DEST_NET")" -maxdepth 1 -name '*.part.*' 2>/dev/null | grep -q .; then
  nope "jira_curl_to_file (échec transport sous set -e) : .part.* orphelin laissé à destination"
else
  ok "jira_curl_to_file (échec transport sous set -e) : aucun .part.* laissé"
fi
grep -q "Échec réseau" "$TMP/netfail.err" && ok "jira_curl_to_file (échec transport sous set -e) : message '⛔ Échec réseau' affiché" \
  || nope "jira_curl_to_file (échec transport sous set -e) : message absent : $(tr -d '\n' <"$TMP/netfail.err")"
[ "$RC_NET" -ne 0 ] && ok "jira_curl_to_file (échec transport sous set -e) : code de retour non nul ($RC_NET)" \
  || nope "jira_curl_to_file (échec transport sous set -e) : code de retour zéro malgré l'échec"

# === 6-7. Homonymes + basename ('..') ============================================

DEST2="$TMP/pj-attach"
"$SCRIPTS/jira-download.sh" RD-ATTACH "$DEST2" >"$TMP/dl2.out" 2>"$TMP/dl2.err"
RC2=$?
[ "$RC2" -eq 0 ] && ok "jira-download.sh réussit sur RD-ATTACH (rc=0)" || nope "jira-download.sh échoue sur RD-ATTACH (rc=$RC2)"

if [ -f "$DEST2/conception.md" ] && [ -f "$DEST2/conception~1002.md" ]; then
  ok "deux homonymes → deux fichiers distincts (conception.md, conception~1002.md)"
else
  nope "les deux homonymes n'ont pas produit deux fichiers distincts : $(ls "$DEST2" 2>/dev/null | tr '\n' ' ')"
fi

if [ -f "$DEST2/evil-hors-dest.txt" ]; then
  ok "le nom de PJ avec '..' est réduit à son basename, dans DEST"
else
  nope "le fichier basename attendu est absent : $(ls "$DEST2" 2>/dev/null | tr '\n' ' ')"
fi
if [ -e "$TMP/evil-hors-dest.txt" ]; then
  nope "le nom de PJ avec '..' a ÉCHAPPÉ à DEST (traversée de chemin)"
else
  ok "aucune évasion hors DEST pour le nom de PJ traître"
fi

COUNT_LINE=$(grep -c "pièce(s) jointe(s) récupérée(s)" "$TMP/dl2.out" || true)
if grep -q "^✅ 3 pièce(s) jointe(s) récupérée(s)" "$TMP/dl2.out"; then
  ok "compteur honnête : 3 pièce(s) jointe(s) récupérée(s)"
else
  nope "compteur inattendu : $(grep 'pièce' "$TMP/dl2.out" || echo '(absent)')"
fi

# === contenu binaire intact (octet nul) ==========================================

DEST3="$TMP/pj-bin"
"$SCRIPTS/jira-download.sh" RD-BINARY "$DEST3" >"$TMP/dl3.out" 2>"$TMP/dl3.err"
if [ -f "$DEST3/binaire.dat" ]; then
  TAILLE=$(wc -c <"$DEST3/binaire.dat" | tr -d ' ')
  [ "$TAILLE" -gt 0 ] && ok "contenu binaire (avec octet nul) téléchargé, $TAILLE octets" \
    || nope "fichier binaire vide"
else
  nope "fichier binaire absent après un téléchargement réussi"
fi

# === 8. Pré-vol --worklog : refus sans POST, tentative pour 'resolution' ========

BEFORE=$(post_count)
if "$SCRIPTS/jira-transition.sh" RD-WORKLOG "CONCEPTION VALIDATION" >"$TMP/tr1.out" 2>"$TMP/tr1.err"; then
  nope "jira-transition.sh aurait dû refuser sans --worklog (worklog requis)"
else
  ok "jira-transition.sh refuse sans --worklog quand il est requis (rc≠0)"
fi
AFTER=$(post_count)
[ "$BEFORE" = "$AFTER" ] && ok "aucun POST émis quand --worklog manque et est requis" \
  || nope "un POST a été émis malgré le refus en pré-vol ($BEFORE → $AFTER)"
grep -q -- "--worklog" "$TMP/tr1.err" && ok "le refus cite l'option --worklog" \
  || nope "le refus ne cite pas --worklog : $(tr -d '\n' <"$TMP/tr1.err")"

# === 9. Accent : 'Annulé' avec --worklog seul (resolution non fournie) ==========

BEFORE2=$(post_count)
if "$SCRIPTS/jira-transition.sh" RD-ANNULE "annulé" --worklog 30m >"$TMP/tr2.out" 2>"$TMP/tr2.err"; then
  ok "jira-transition.sh RD-ANNULE → 'annulé' (insensible à l'accent/casse) avec --worklog seul : rc=0"
else
  nope "jira-transition.sh échoue sur la cible accentuée avec --worklog seul : $(tr -d '\n' <"$TMP/tr2.err")"
fi
AFTER2=$(post_count)
[ "$AFTER2" -gt "$BEFORE2" ] && ok "le POST a bien été tenté pour la cible 'Annulé' (resolution non pré-filtrée)" \
  || nope "aucun POST tenté pour 'Annulé' ($BEFORE2 → $AFTER2)"

# === 10. --assignee par nom d'affichage ==========================================

RESOLVE_OUT=$(jira_resolve_assignee RD-1 "Alexandre" 2>"$TMP/resolve1.err")
RESOLVE_ACCOUNT_ID="${RESOLVE_OUT%%$'\t'*}"
if [ "$RESOLVE_ACCOUNT_ID" = "6256cf820630bd0070761e65" ]; then
  ok "jira_resolve_assignee : une correspondance → accountId résolu"
else
  nope "jira_resolve_assignee : résolution unique incorrecte : '$RESOLVE_OUT' ($(tr -d '\n' <"$TMP/resolve1.err"))"
fi
case "$RESOLVE_OUT" in
  *$'\t'"Alexandre Husset") ok "jira_resolve_assignee : renvoie accountId<TAB>displayName (Correction 2)" ;;
  *) nope "jira_resolve_assignee : displayName absent ou mal formé dans la sortie : '$RESOLVE_OUT'" ;;
esac

# --- Correction 2 (recommandé) : un seul appel réseau au search sur --assignee <nom> ---
SEARCH_BEFORE=$(search_count)
"$SCRIPTS/jira-edit.sh" RD-1 --assignee Alexandre >"$TMP/editassignee.out" 2>"$TMP/editassignee.err"
RC_EDITASSIGNEE=$?
SEARCH_AFTER=$(search_count)
[ "$RC_EDITASSIGNEE" -eq 0 ] && ok "jira-edit.sh --assignee Alexandre réussit (rc=0)" \
  || nope "jira-edit.sh --assignee Alexandre échoue (rc=$RC_EDITASSIGNEE) : $(tr -d '\n' <"$TMP/editassignee.err")"
SEARCH_DELTA=$((SEARCH_AFTER - SEARCH_BEFORE))
[ "$SEARCH_DELTA" -eq 1 ] && ok "jira-edit.sh --assignee <nom> : un seul appel réseau au search (delta=$SEARCH_DELTA)" \
  || nope "jira-edit.sh --assignee <nom> : $SEARCH_DELTA appel(s) réseau au search (attendu 1)"

if jira_resolve_assignee RD-1 "Personne" >"$TMP/resolve0.out" 2>"$TMP/resolve0.err"; then
  nope "jira_resolve_assignee : aurait dû refuser sur zéro correspondance"
else
  ok "jira_resolve_assignee : refuse sur zéro correspondance"
fi
grep -q "aucun utilisateur assignable" "$TMP/resolve0.err" && ok "message explicite sur zéro correspondance" \
  || nope "message absent sur zéro correspondance : $(tr -d '\n' <"$TMP/resolve0.err")"

if jira_resolve_assignee RD-1 "Homonyme" >"$TMP/resolveN.out" 2>"$TMP/resolveN.err"; then
  nope "jira_resolve_assignee : aurait dû refuser sur plusieurs correspondances"
else
  ok "jira_resolve_assignee : refuse sur plusieurs correspondances"
fi
grep -q "accountId" "$TMP/resolveN.err" && ok "la liste d'homonymes rappelle qu'un accountId est accepté" \
  || nope "pas de rappel accountId sur homonymes : $(tr -d '\n' <"$TMP/resolveN.err")"

# === Correction 3 (recommandé) : jira_looks_like_account_id, comportement figé ===
# Verrouille le comportement avant/après le remplacement des 24 [0-9a-fA-F] du
# case par une regex [[ =~ ]] : mêmes cas vrais/faux, y compris les bornes
# (23/25 caractères) et le cas ':' (compte de service).
check_account_id() {  # $1 = valeur, $2 = attendu (0=oui, 1=non), $3 = libellé
  jira_looks_like_account_id "$1"
  local rc=$?
  [ "$rc" -eq "$2" ] && ok "jira_looks_like_account_id : $3" \
    || nope "jira_looks_like_account_id : $3 (rc=$rc, attendu $2)"
}
check_account_id "6256cf820630bd0070761e65" 0 "24 hex (mesuré) → accountId"
check_account_id "6256cf820630bd0070761e6" 1 "23 hex → pas un accountId"
check_account_id "6256cf820630bd0070761e655" 1 "25 hex → pas un accountId"
check_account_id "GGGGcf820630bd0070761e65" 1 "caractères non-hex → pas un accountId"
check_account_id "service:xyz" 0 "contient ':' (compte de service) → accountId"
check_account_id "Alexandre Husset" 1 "nom d'affichage → pas un accountId"

# === Fixtures d'or : chemins de succès inchangés, octet pour octet =============
# La sortie d'une lecture réussie ne doit pas bouger d'un octet avec la
# réécriture de jira_curl (plus de --fail). Référence figée et commitée, jamais
# capturée à l'exécution (pas de git stash/checkout au milieu d'une suite).

jira_curl "$(jira_base)/rest/api/3/issue/RD-OK" > "$TMP/rd-ok.json"
if cmp -s "$TMP/rd-ok.json" "$FIXTURES/issue-rd-ok.json"; then
  ok "jira_curl : sortie d'une lecture réussie identique à la fixture d'or (octet pour octet)"
else
  nope "jira_curl : sortie divergente de la fixture d'or : $(cmp "$TMP/rd-ok.json" "$FIXTURES/issue-rd-ok.json" 2>&1)"
fi

jira_curl_to_file "$TMP/binaire-obtenu.bin" "$JIRA_BASE_URL/attachment/content/2001"
if cmp -s "$TMP/binaire-obtenu.bin" "$FIXTURES/binaire-attendu.bin"; then
  ok "jira_curl_to_file : contenu binaire (octet nul) identique à la fixture d'or"
else
  nope "jira_curl_to_file : contenu binaire divergent de la fixture d'or : $(cmp "$TMP/binaire-obtenu.bin" "$FIXTURES/binaire-attendu.bin" 2>&1)"
fi

echo "----"
echo "Résultat : PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
