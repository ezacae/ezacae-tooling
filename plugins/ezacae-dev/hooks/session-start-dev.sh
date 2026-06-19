#!/usr/bin/env bash
# Hook SessionStart — plugin ezacae-dev.
# Injecte le chemin absolu de la racine du plugin pour que les skills exécutés
# dans le thread principal (sarah, chuck, morgan) résolvent les conventions de
# stack embarquées (skills/john/stacks/<stack>.md), qui sont partagées entre
# plusieurs skills. ${CLAUDE_PLUGIN_ROOT} n'étant PAS substitué dans le corps
# markdown des skills, on passe par l'injection de contexte (où il fonctionne).
#
# Sortie : JSON sur stdout (hookSpecificOutput.additionalContext). Rien d'autre.
set -uo pipefail

DEV_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

CTX="🛠 Plugin ezacae-dev (hook SessionStart)
• Racine plugin : ${DEV_ROOT}
• Conventions de stack embarquées : ${DEV_ROOT}/skills/john/stacks/<stack>.md
  (résoudre les références « stacks/<stack>.md » des skills chuck/john/morgan via ce chemin absolu)"

if command -v jq >/dev/null 2>&1; then
  jq -n --arg c "$CTX" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
else
  esc=${CTX//\\/\\\\}; esc=${esc//\"/\\\"}; esc=${esc//$'\n'/\\n}
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}' "$esc"
fi
exit 0
