#!/usr/bin/env bash
# Tests de jira_text_to_adf — écriture texte → ADF (RD-23).
#
# 100% hors-ligne : n'exerce que la conversion, aucun appel réseau, aucun
# credential requis. Lancer : bash plugins/ezacae-jira/tests/test_adf_write.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../scripts/jira-lib.sh"
PASS=0; FAIL=0

ok()   { echo "PASS  $1"; PASS=$((PASS+1)); }
nope() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }

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

echo "----"
echo "Résultat : PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
