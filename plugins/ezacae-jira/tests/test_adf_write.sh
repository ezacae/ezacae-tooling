#!/usr/bin/env bash
# Tests de jira_text_to_adf — écriture texte → ADF (RD-23).
#
# 100% hors-ligne : n'exerce que la conversion, aucun appel réseau, aucun
# credential requis. Lancer : bash plugins/ezacae-jira/tests/test_adf_write.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../scripts/jira-lib.sh"
. "$HERE/harness.sh"

# --- Non-régression : sortie identique OCTET POUR OCTET aux références figées ---
# Un texte sans aucune syntaxe de mise en forme doit produire exactement ce que
# produisait la version d'avant RD-23. Références : fixtures/plain/*.adf.json.
for f in "$HERE"/fixtures/plain/*.txt; do
  label="non-régression $(basename "$f")"
  if jira_text_to_adf < "$f" | diff -q - "${f%.txt}.adf.json" >/dev/null; then
    ok "$label"
  else
    nope "$label"
    jira_text_to_adf < "$f" | diff - "${f%.txt}.adf.json" | head -10 | sed 's/^/      /'
  fi
done

# --- Sûreté littérale : notre vocabulaire traverse l'outil intact ---------------
# Le convertisseur ne regarde que le DÉBUT de ligne. Aucune paire de signes n'est
# cherchée au milieu des phrases : nos noms de fichiers, chemins et globs sont
# pleins de tirets bas et d'étoiles qui seraient corrompus en silence (RD-23).
#
# Trois invariants par ligne : texte restitué à l'identique, aucun mark, un seul
# paragraphe (donc aucune promotion).
check_literal() {
  local label="$1" line="$2" adf text marks blocks
  adf=$(printf '%s' "$line" | jira_text_to_adf)
  text=$(printf '%s' "$adf" | jq -r '[.. | objects | select(.type=="text") | .text] | join("")')
  marks=$(printf '%s' "$adf" | jq '[.. | objects | select(has("marks"))] | length')
  blocks=$(printf '%s' "$adf" | jq -r '[.content[].type] | unique | join(",")')
  [ "$text" = "$line" ]       || { nope "$label — texte altéré : $text"; return; }
  [ "$marks" = "0" ]          || { nope "$label — $marks mark(s) sur du littéral"; return; }
  [ "$blocks" = "paragraph" ] || { nope "$label — blocs : $blocks"; return; }
  ok "$label"
}

check_literal "identifiants snake_case" \
  'jira_text_to_adf est appelée par jira_load_env et jira_require_creds'
check_literal "fichier de test du plugin" \
  'Modèle : plugins/ezacae-jira/tests/test_jira_guard.sh'
check_literal "deux globs doublés" \
  'changes: plugins/**/* et deploy/jira-watcher/**/*'
check_literal "multiplication et exposant" \
  'Coût : 2 * 3 = 6 opérations, complexité n**2'
check_literal "préfixe de passation et parenthèses" \
  '🤖 [Mike] Cadrage terminé (voir docs/conception/cadrage.md)'
check_literal "pathspec git" \
  "git restore -- . ':(exclude)node_modules'"
check_literal "JSON et antislash" \
  '🤖 {"type":"doc"} "guillemets" et \ antislash — 100%'
check_literal "shebang (un seul dièse)" \
  '#!/usr/bin/env bash'
check_literal "quatre dièses" \
  '#### pas un titre'
check_literal "marqueur de titre sans contenu" \
  '## '
check_literal "marqueur de puce sans contenu" \
  '- '
check_literal "puce indentée (pas d'imbrication)" \
  '  - élément indenté'
check_literal "puce sans espace après le tiret" \
  '-pas une puce'

# --- Constructions promues -----------------------------------------------------
# expect_shape <label> <texte> <programme jq booléen>
expect_shape() {
  local label="$1" txt="$2" prog="$3"
  if printf '%s' "$txt" | jira_text_to_adf | jq -e "$prog" >/dev/null 2>&1; then
    ok "$label"
  else
    nope "$label"
    printf '%s' "$txt" | jira_text_to_adf | head -20 | sed 's/^/      /'
  fi
}

expect_shape "## produit un heading de niveau 2" '## Périmètre' \
  '(.content|length)==1 and .content[0].type=="heading" and .content[0].attrs.level==2
   and .content[0].content[0].text=="Périmètre"'
expect_shape "### produit un heading de niveau 3" '### Détail' \
  '.content[0].type=="heading" and .content[0].attrs.level==3'

expect_shape "deux puces consécutives = une seule bulletList" \
  '- un
- deux' \
  '(.content|length)==1 and .content[0].type=="bulletList"
   and (.content[0].content|length)==2
   and .content[0].content[0].type=="listItem"
   and .content[0].content[0].content[0].type=="paragraph"
   and .content[0].content[0].content[0].content[0].text=="un"'

expect_shape "un paragraphe ferme la liste" \
  '- un
suite' \
  '[.content[].type] == ["bulletList","paragraph"]'

expect_shape "une ligne vide ferme la liste et reste un paragraphe vide" \
  '- un

- deux' \
  '[.content[].type] == ["bulletList","paragraph","bulletList"]
   and (.content[1] | has("content") | not)'

expect_shape "liste numérotée démarrant à 1 : pas d'attrs" \
  '1. un
2. deux' \
  '.content[0].type=="orderedList" and (.content[0]|has("attrs")|not)
   and (.content[0].content|length)==2'

expect_shape "liste numérotée démarrant à 3 : attrs.order=3" \
  '3. trois' \
  '.content[0].type=="orderedList" and .content[0].attrs.order==3'

expect_shape "bloc de code avec langage" \
  '```bash
set -e
exit 0
```' \
  '(.content|length)==1 and .content[0].type=="codeBlock"
   and .content[0].attrs.language=="bash"
   and .content[0].content[0].text=="set -e\nexit 0"'

expect_shape "rien n'est promu à l'intérieur d'un bloc de code" \
  '```
## pas un titre
- pas une puce
```' \
  '(.content|length)==1 and .content[0].type=="codeBlock"
   and (.content[0]|has("attrs")|not)
   and .content[0].content[0].text=="## pas un titre\n- pas une puce"'

expect_shape "bloc de code vide : pas de nœud texte vide" \
  '```
```' \
  '.content[0].type=="codeBlock" and (.content[0]|has("content")|not)'

expect_shape "bloc jamais fermé : dégradation en paragraphes, ordre conservé" \
  '```bash
set -e' \
  '[.content[].type] == ["paragraph","paragraph"]
   and .content[0].content[0].text=="```bash"
   and .content[1].content[0].text=="set -e"'

# Espaces écrits en \x20 : un éditeur ou un hook de format effacerait des espaces
# de fin invisibles dans le source, et le test ne testerait plus rien.
FENCE_SPACED=$'```\x20\x20\x20bash\x20\x20\x20\necho ok\n```'
expect_shape "langage du bloc de code entièrement détrimé" "$FENCE_SPACED" \
  '.content[0].attrs.language=="bash"'

FENCE_BLANK=$'```\x20\x20\x20\necho ok\n```'
expect_shape "langage réduit à des espaces : aucun attrs" "$FENCE_BLANK" \
  '.content[0].type=="codeBlock" and (.content[0]|has("attrs")|not)'

# --- Validité structurelle -----------------------------------------------------
# Sous-ensemble des règles d'imbrication de Jira : première cause de refus d'envoi.
expect_valid() {
  local label="$1" txt="$2"
  if printf '%s' "$txt" | jira_text_to_adf | jq -e "$JIRA_JQ_ADF_VALID" >/dev/null 2>&1; then
    ok "validité — $label"
  else
    nope "validité — $label"
  fi
}

expect_valid "document mixte" '## Titre

- un
- deux

1. étape

```sh
echo ok
```
Fin.'
expect_valid "corpus json-hostile" "$(cat "$HERE/fixtures/plain/json-hostile.txt")"

# --- Filet de sécurité ---------------------------------------------------------
# Si le convertisseur produisait une structure invalide, l'envoi doit tout de
# même aboutir : repli sur la conversion plate, avertissement sur stderr.
# On force le cas en substituant un programme volontairement invalide (nœud
# texte vide), ce qu'aucune entrée ne peut provoquer par elle-même.
ERRFILE=$(mktemp)
BROKEN='{type:"doc",version:1,content:[{type:"paragraph",content:[{type:"text",text:""}]}]}'
fb_out=$(printf 'Passation critique.' | JIRA_JQ_TEXT_TO_ADF="$BROKEN" jira_text_to_adf 2>"$ERRFILE")
fb_err=$(cat "$ERRFILE"); rm -f "$ERRFILE"
fb_txt=$(printf '%s' "$fb_out" | jq -r '[.. | objects | select(.type=="text") | .text] | join("")')
if [ "$fb_txt" = "Passation critique." ] && [[ "$fb_err" == *"repli sur la conversion plate"* ]]; then
  ok "filet de sécurité — repli plat, texte préservé, avertissement émis"
else
  nope "filet de sécurité — texte=«$fb_txt» stderr=«$fb_err»"
fi

# --- Silence au chargement -----------------------------------------------------
# Le hook jira-guard.sh parse son propre stdout en JSON : si jira-lib.sh écrit
# quoi que ce soit au chargement, TOUTES les opérations JIRA du dépôt cassent.
LOAD_OUT=$(bash -c '. "'"$HERE"'/../scripts/jira-lib.sh"' 2>/dev/null)
if [ -z "$LOAD_OUT" ]; then
  ok "jira-lib.sh est muet au chargement"
else
  nope "jira-lib.sh écrit au chargement : $LOAD_OUT"
fi

test_summary
