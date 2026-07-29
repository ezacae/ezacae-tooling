#!/usr/bin/env bash
# Tests du rendu ADF → texte lisible (RD-23, côté lecture).
#
# 100% hors-ligne : les documents ADF sont écrits à la main, aucun appel réseau,
# aucun credential requis. Lancer : bash plugins/ezacae-jira/tests/test_adf_read.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../scripts/jira-lib.sh"
PASS=0; FAIL=0

# render <doc-json> → texte rendu.
# JIRA_JQ_ADF_RENDER se termine par un ';' : le corps se concatène SANS barre
# verticale ("$VAR | adf_render" échoue avec « unexpected '|' »).
render() { printf '%s' "$1" | jq -r "$JIRA_JQ_ADF_RENDER adf_render"; }

# expect_contains <label> <doc-json> <sous-chaîne attendue>
expect_contains() {
  local label="$1" doc="$2" want="$3" got
  got=$(render "$doc")
  if [[ "$got" == *"$want"* ]]; then
    echo "PASS  $label"; PASS=$((PASS+1))
  else
    echo "FAIL  $label — attendu «$want» dans :"; printf '%s\n' "$got" | sed 's/^/      /'
    FAIL=$((FAIL+1))
  fi
}

# --- Frontières de blocs -------------------------------------------------------
# Le défaut d'origine : « RD-17PÉRIMÈTRE RÉEL », deux paragraphes concaténés.
DOC_2P='{"type":"doc","version":1,"content":[
  {"type":"paragraph","content":[{"type":"text","text":"RD-17"}]},
  {"type":"paragraph","content":[{"type":"text","text":"PÉRIMÈTRE RÉEL"}]}]}'
expect_contains "deux paragraphes séparés par une ligne vide" \
  "$DOC_2P" 'RD-17

PÉRIMÈTRE RÉEL'

DOC_LIST='{"type":"doc","version":1,"content":[
  {"type":"bulletList","content":[
    {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"un"}]}]},
    {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"deux"}]}]}]}]}'
expect_contains "puces sur des lignes distinctes" "$DOC_LIST" '- un
- deux'

DOC_ORD='{"type":"doc","version":1,"content":[
  {"type":"orderedList","attrs":{"order":3},"content":[
    {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"trois"}]}]}]}]}'
expect_contains "liste numérotée respectant attrs.order" "$DOC_ORD" '3. trois'

DOC_HEAD='{"type":"doc","version":1,"content":[
  {"type":"heading","attrs":{"level":2},"content":[{"type":"text","text":"Périmètre"}]}]}'
expect_contains "titre préfixé de ses dièses" "$DOC_HEAD" '## Périmètre'

DOC_CODE='{"type":"doc","version":1,"content":[
  {"type":"codeBlock","attrs":{"language":"bash"},"content":[{"type":"text","text":"set -e\nexit 0"}]}]}'
expect_contains "bloc de code encadré, langage conservé" "$DOC_CODE" '```bash
set -e
exit 0
```'

# --- Non-perte : rien ne disparaît jamais --------------------------------------
# Défaut OBSERVÉ sur RD-23 : « The linked issue -  has been resolved », la clé du
# ticket lié manquait parce que c'est un nœud inlineCard et non un nœud text.
DOC_CARD='{"type":"doc","version":1,"content":[
  {"type":"paragraph","content":[
    {"type":"text","text":"The linked issue "},
    {"type":"inlineCard","attrs":{"url":"https://ezacae.atlassian.net/browse/RD-17"}},
    {"type":"text","text":" has been resolved"}]}]}'
expect_contains "carte de ticket liée : URL restituée" "$DOC_CARD" "browse/RD-17"

DOC_MENTION='{"type":"doc","version":1,"content":[
  {"type":"paragraph","content":[{"type":"mention","attrs":{"id":"x","text":"@Patrice"}}]}]}'
expect_contains "mention : texte restitué" "$DOC_MENTION" "@Patrice"

DOC_TABLE='{"type":"doc","version":1,"content":[
  {"type":"table","content":[{"type":"tableRow","content":[
    {"type":"tableCell","content":[{"type":"paragraph","content":[{"type":"text","text":"clé"}]}]},
    {"type":"tableCell","content":[{"type":"paragraph","content":[{"type":"text","text":"valeur"}]}]}]}]}]}'
expect_contains "tableau : cellules restituées" "$DOC_TABLE" "clé"

DOC_UNKNOWN='{"type":"doc","version":1,"content":[
  {"type":"blocDuFutur","content":[
    {"type":"paragraph","content":[{"type":"text","text":"contenu inconnu"}]}]}]}'
expect_contains "type inconnu : rien n'est jeté" "$DOC_UNKNOWN" "contenu inconnu"

echo "----"
echo "Résultat : PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
