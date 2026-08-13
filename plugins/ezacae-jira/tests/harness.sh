#!/usr/bin/env bash
# Harnais commun des tests shell du plugin ezacae-jira.
#
# Une seule source de vérité pour le format de sortie (préfixes « PASS  » /
# « FAIL  », pied de page, code de retour) — la convention avait été recopiée
# dans chaque fichier de test, avec le risque de divergence que ça implique.
#
# Usage :
#   . "$(dirname "${BASH_SOURCE[0]}")/test-harness.sh"
#   ok "ce qui a marché" ; nope "ce qui a cassé"
#   test_summary    # dernière ligne du script : affiche le total et sort 0/1

PASS=0; FAIL=0

ok()   { echo "PASS  $1"; PASS=$((PASS+1)); }
nope() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }

# Seuls le comptage et l'affichage sont mutualisés : chaque suite garde ses
# propres assertions métier.

test_summary() {
  echo "----"
  echo "Résultat : PASS=$PASS FAIL=$FAIL"
  [ "$FAIL" -eq 0 ]
}
