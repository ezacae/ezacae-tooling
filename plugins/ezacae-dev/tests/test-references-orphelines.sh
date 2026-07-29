#!/usr/bin/env bash
#
# test-references-orphelines.sh — invariant référentiel après la fusion des
# exécuteurs `john` + `morgan` → `developer` (!14).
#
# Ce que le test interdit : les formes OPÉRATIONNELLES des anciens noms, c'est-à-dire
# celles qu'un lecteur (humain ou agent) exécute ou résout :
#   /john, /morgan                     commande à taper
#   skills/john, skills/morgan         chemin de skill
#   agents/john, agents/morgan         chemin d'agent
#   skill john, skill morgan           invocation en prose
#   ezacae-dev:john, ezacae-dev:morgan sous-agent qualifié
#   subagent_type: "john"|"morgan"     dispatch
#   `john`, `morgan`                   nom nu en code inline (se lit comme invocable)
#
# Ce que le test AUTORISE : une mention en prose non exécutable (« l'ancienne paire
# morgan/john »). Formuler l'invariant comme « aucune occurrence du mot » interdirait
# des phrases légitimes ; c'est la forme opérationnelle qui casse, pas le souvenir.
# Formulation reprise de docs/conception/fusion-john-morgan-developer.md (§Risques).
#
# LISTE BLANCHE — fichiers où ces formes sont le SUJET, pas une consigne.
# Une ligne, une raison. Un fichier n'y entre PAS parce qu'il est ancien : il y entre
# parce que le lecteur ne peut pas confondre son contenu avec une instruction à suivre.
# ATTENTION : une conception en attente d'exécution n'est PAS une archive — c'est
# exactement le cas qui a produit le défaut corrigé ici (docs/jira-watcher-mike.md).
#
#   MIGRATION.md                                     commandes de nettoyage des copies héritées
#   README.md                                        phrase qui explique le renommage aux lecteurs
#   docs/superpowers/**                              plans et specs datés (RD-8, 22/06) — exécutés, clos
#   docs/conception/fusion-john-morgan-developer.md   la conception de cette fusion
#   docs/conception/rd-8-alleger-les-skills.md        conception d'un chantier clos
#   docs/conception/corrections-revue-mr14.md         conception des corrections de revue de !14 (RD-27)
#   plugins/ezacae-dev/tests/test-references-orphelines.sh  ce fichier : il énumère les formes interdites
#
# Compatible bash 3.2. Aucune dépendance. Aucun accès réseau.

set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../../.." && pwd)"
[ -d "$ROOT/plugins/ezacae-dev" ] || { echo "FAIL — racine du dépôt introuvable : $ROOT" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "FAIL — git requis" >&2; exit 2; }

# Formes opérationnelles interdites.
MOTIF='/john|/morgan|skills/john|skills/morgan|agents/john|agents/morgan|skill john|skill morgan|ezacae-dev:john|ezacae-dev:morgan|subagent_type: ?.?(john|morgan)|`john`|`morgan`'

autorise() {
  case "$1" in
    MIGRATION.md|README.md) return 0 ;;
    docs/superpowers/*) return 0 ;;
    docs/conception/fusion-john-morgan-developer.md) return 0 ;;
    docs/conception/rd-8-alleger-les-skills.md) return 0 ;;
    docs/conception/corrections-revue-mr14.md) return 0 ;;
    plugins/ezacae-dev/tests/test-references-orphelines.sh) return 0 ;;
    *) return 1 ;;
  esac
}

cd "$ROOT" || exit 2
hits=""
while IFS= read -r f; do
  autorise "$f" && continue
  h="$(grep -nIiE "$MOTIF" -- "$f" 2>/dev/null | sed "s|^|$f:|")"
  [ -n "$h" ] && hits="${hits}${h}
"
done <<EOF
$(git ls-files)
EOF
hits="$(printf '%s' "$hits" | grep -v '^$' || true)"

echo "Invariant référentiel : aucune forme opérationnelle de john/morgan hors liste blanche"
if [ -z "$hits" ]; then
  echo "  ok   — aucune référence orpheline"
  echo
  echo "Invariant référentiel tenu."
  exit 0
fi
printf '%s\n' "$hits" | sed 's|^|      → |'
echo
echo "$(printf '%s\n' "$hits" | grep -c .) référence(s) orpheline(s) — le lecteur y trouve une commande ou un chemin qui n'existe plus."
exit 1
