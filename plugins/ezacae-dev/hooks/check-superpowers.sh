#!/usr/bin/env bash
# check-superpowers.sh — garde SessionStart (RD-8, ezacae-dev).
#
# Les skills ezacae-dev (chuck, developer) délèguent leur méthodologie au
# plugin `superpowers` (couche 1 du harnais). Ce garde vérifie :
#   1. que superpowers est installé — sinon la délégation dégrade en silence ;
#   2. que sa version correspond à `superpowers.lock` — sinon dérive possible.
#
# Détection par le CACHE DISQUE, pas via `claude plugin list` : un hook
# SessionStart ne doit pas invoquer le CLI qu'il démarre (course + latence à
# chaque session). Chemin stable vérifié 23/07 :
#   ~/.claude/plugins/cache/<marketplace>/superpowers/<version>/
#
# Non bloquant : émet un avertissement visible, sort TOUJOURS 0.
#
# Testabilité (cf. tests/test-check-superpowers.sh) :
#   SUPERPOWERS_CACHE_DIR  racine du cache plugins (défaut : ~/.claude/plugins/cache)
#   SUPERPOWERS_LOCK       chemin du lock (défaut : <hook>/../superpowers.lock)
set -u

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE="${SUPERPOWERS_CACHE_DIR:-$HOME/.claude/plugins/cache}"
LOCK="${SUPERPOWERS_LOCK:-$HOOK_DIR/../superpowers.lock}"

# Version installée = nom du dossier <cache>/*/superpowers/<version>/ le plus
# élevé (sort -V). Vide si superpowers absent du cache.
version="$(find "$CACHE" -mindepth 3 -maxdepth 3 -type d -path '*/superpowers/*' 2>/dev/null \
  | sed 's#.*/##' | sort -V | tail -1)"

if [ -z "$version" ]; then
  echo "⚠️  ezacae-dev : plugin « superpowers » non détecté. Les skills chuck / developer délèguent leur méthodologie à superpowers — sans lui, elle est absente."
  echo "    Installe-le : claude plugin install superpowers@claude-plugins-official"
  exit 0
fi

expected=""
[ -f "$LOCK" ] && expected="$(head -1 "$LOCK" | tr -d '[:space:]')"

if [ -n "$expected" ] && [ "$version" != "$expected" ]; then
  echo "⚠️  ezacae-dev : dérive de version superpowers — attendue $expected (superpowers.lock), installée $version."
  echo "    Vérifie que la méthodologie déléguée reste compatible, puis mets à jour superpowers.lock si le changement est validé."
fi

exit 0
