#!/usr/bin/env bash
#
# test-hard-gate-coherence.sh — invariant du HARD-GATE de `developer`.
#
# La MR !14 pose une règle absolue : « il n'existe AUCUNE voie d'implémentation
# sans conception » (developer/SKILL.md HARD-GATE, agents/developer.md HARD-GATE,
# et chemin de conception = argument OBLIGATOIRE du skill).
#
# Une règle absolue n'est tenue que si AUCUN document du plugin ne documente ni
# ne sous-entend une route de correction sans conception. Sinon un orchestrateur
# qui suit la prose se retrouve à invoquer `developer` sans conception : soit
# STOP net (pipeline coincé), soit improvisation — c'est-à-dire du code écrit
# sans conception, exactement ce que le HARD-GATE prétend rendre impossible.
#
# Ce test échoue tant qu'une telle formulation subsiste.
#
# Compatible bash 3.2. Aucune dépendance.

set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
DEV="$(cd "$DIR/.." && pwd)"
[ -d "$DEV/skills" ] || { echo "FAIL — racine du plugin introuvable : $DEV" >&2; exit 2; }

FAILS=0
pass() { echo "  ok   — $1"; }
fail() { echo "  FAIL — $1"; FAILS=$((FAILS + 1)); }

DOCS="$(find "$DEV" -name '*.md' -not -path '*/stacks/*')"

# --- C1 — route de correction confiée à developer sans mentionner la conception
echo "C1 : aucune route de correction vers developer sans conception"
# Le motif est cherché dans le CONTENU seul : le chemin des fichiers contient
# « developer », il ferait matcher toutes les lignes s'il restait dans le flux.
hits_c1=""
for f in $DOCS; do
  h="$(awk -v F="$f" '
    { line = tolower($0) }
    line ~ /corrig|correction/ && line ~ /developer/ && line !~ /conception/ \
      { printf "%s:%d:%s\n", F, NR, $0 }
  ' "$f")"
  [ -n "$h" ] && hits_c1="${hits_c1}${h}
"
done
hits_c1="$(printf '%s' "$hits_c1" | grep -v '^$' || true)"
if [ -z "$hits_c1" ]; then
  pass "aucune formulation trouvée"
else
  printf '%s\n' "$hits_c1" | sed "s|^$DEV/|      → plugins/ezacae-dev/|"
  fail "$(printf '%s\n' "$hits_c1" | grep -c .) formulation(s) envoient corriger via developer sans exiger de conception"
fi

# --- C2 — conception présentée comme conditionnelle -------------------------
echo "C2 : la conception n'est jamais présentée comme conditionnelle"
hits_c2="$(grep -nEi 'conception' $DOCS \
  | grep -Ei 'si le correctif|si non trivial|non trivial|si la modif|si nécessaire|le cas échéant|optionnel' || true)"
if [ -z "$hits_c2" ]; then
  pass "aucune formulation conditionnelle trouvée"
else
  printf '%s\n' "$hits_c2" | sed "s|^$DEV/|      → plugins/ezacae-dev/|"
  fail "$(printf '%s\n' "$hits_c2" | grep -c .) formulation(s) rendent la conception conditionnelle, en contradiction avec le HARD-GATE"
fi

echo
if [ "$FAILS" -eq 0 ]; then
  echo "Invariant du HARD-GATE tenu."
  exit 0
fi
echo "$FAILS violation(s) de l'invariant du HARD-GATE."
exit 1
