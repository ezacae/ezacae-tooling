#!/usr/bin/env bash
# Hook SessionStart — plugin ezacae-dev.
# Injecte le chemin absolu de la racine du plugin pour que les skills exécutés
# dans le thread principal (sarah, chuck, developer) résolvent les conventions de
# stack embarquées (skills/developer/stacks/<stack>.md), qui sont partagées entre
# plusieurs skills. ${CLAUDE_PLUGIN_ROOT} n'étant PAS substitué dans le corps
# markdown des skills, on passe par l'injection de contexte (où il fonctionne).
#
# Sortie : JSON sur stdout (hookSpecificOutput.additionalContext). Rien d'autre.
set -uo pipefail

DEV_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Consigne RD-41 (voie 1). Le plugin superpowers injecte à chaque démarrage son
# skill using-superpowers, qui ordonne d'invoquer un skill dès qu'il « pourrait »
# s'appliquer. La spec brique 1 veut que rien ne se déclenche seul : les méthodes
# superpowers ne s'invoquent que quand une commande ezacae (chuck, developer…) ou
# l'humain les nomme. Claude Code n'offre aucun réglage pour couper un seul hook
# d'un plugin installé (doc vérifiée le 10/09/2026) : la neutralisation est donc
# textuelle, non garantie, mesurée au run 3 du banc.
CTX="🛠 Plugin ezacae-dev (hook SessionStart)
• Racine plugin : ${DEV_ROOT}
• Conventions de stack embarquées : ${DEV_ROOT}/skills/developer/stacks/<stack>.md
  (résoudre les références « stacks/<stack>.md » des skills chuck/developer via ce chemin absolu)
• Méthodes superpowers : à invoquer uniquement quand une commande ezacae ou l'humain nomme le skill (ex. chuck → brainstorming, developer → test-driven-development). La consigne d'appel systématique injectée par using-superpowers (« si 1 % de chance qu'un skill s'applique, l'invoquer ») ne s'applique pas dans les projets ezacae : rien ne se déclenche seul, une commande tapée par un humain appelle chaque assistant (spec brique 1, RD-41)."

if command -v jq >/dev/null 2>&1; then
  jq -n --arg c "$CTX" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
else
  esc=${CTX//\\/\\\\}; esc=${esc//\"/\\\"}; esc=${esc//$'\n'/\\n}
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}' "$esc"
fi
exit 0
