#!/usr/bin/env bash
# Tests du hook SessionStart session-start-dev.sh (RD-41, ezacae-dev).
#
# Le hook injecte deux choses en contexte :
#   1. la racine du plugin (conventions de stack partagées entre skills) ;
#   2. la consigne qui neutralise l'appel systématique des méthodes superpowers
#      injecté par le plugin superpowers lui-même (RD-41, voie 1 : Claude Code
#      n'offre aucun réglage pour couper un seul hook d'un plugin installé,
#      vérifié le 10/09/2026 ; la neutralisation est textuelle, non garantie,
#      mesurée au run 3 du banc).
#
# Sortie attendue : un JSON hookSpecificOutput.additionalContext, exit 0.
# Requiert jq (comme la CI).

set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$DIR/../hooks/session-start-dev.sh"

pass=0; fail=0
contains() { if printf '%s' "$3" | grep -qF -- "$2"; then echo "PASS: $1"; pass=$((pass+1))
  else echo "FAIL: $1 — attendu contient «$2» — obtenu: «$3»"; fail=$((fail+1)); fi; }
eq()       { if [ "$2" = "$3" ]; then echo "PASS: $1"; pass=$((pass+1))
  else echo "FAIL: $1 — attendu «$2» — obtenu «$3»"; fail=$((fail+1)); fi; }

out=$(CLAUDE_PLUGIN_ROOT="/tmp/racine-test" bash "$SCRIPT" 2>&1); code=$?
eq "sort 0" "0" "$code"
ctx=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
eq "JSON valide, événement SessionStart" "SessionStart" "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)"
contains "racine du plugin injectée" "/tmp/racine-test/skills/developer/stacks/<stack>.md" "$ctx"
contains "consigne : superpowers seulement sur appel nommé" "superpowers" "$ctx"
contains "consigne : la commande ou l'humain nomme le skill" "commande ezacae ou l'humain" "$ctx"
contains "consigne : ne pas suivre l'appel systématique de using-superpowers" "using-superpowers" "$ctx"

echo "-----"; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
