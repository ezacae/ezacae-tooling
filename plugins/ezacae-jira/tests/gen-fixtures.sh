#!/usr/bin/env bash
# Régénère les références de non-régression de jira_text_to_adf.
#
# ⚠️ À ne relancer QUE volontairement, en connaissance de cause : ces fichiers
# figent le comportement d'AVANT la mise en forme (RD-23). Les régénérer après
# une modification de la fonction rendrait le test de non-régression tautologique.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../scripts/jira-lib.sh"

for f in "$HERE"/fixtures/plain/*.txt; do
  jira_text_to_adf < "$f" > "${f%.txt}.adf.json"
  echo "→ ${f%.txt}.adf.json"
done
