#!/usr/bin/env bash
# Hook SessionStart — plugin ezacae-base.
# Injecte les conventions globales ezacae (conventions.md) en contexte de session.
# C'est le mécanisme de distribution d'instructions d'équipe via plugin : un plugin
# ne peut pas écrire dans le CLAUDE.md de chacun, mais un hook SessionStart peut
# fournir du contexte additionnel à chaque session.
#
# ${CLAUDE_PLUGIN_ROOT} EST défini pour le sous-processus de hook (contrairement au
# corps markdown), donc on lit le fichier source par ce chemin.
#
# Sortie : JSON sur stdout (hookSpecificOutput.additionalContext). Rien d'autre.
set -uo pipefail

ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONV="$ROOT/conventions.md"

if [ ! -f "$CONV" ]; then
  # Pas de conventions trouvées : ne rien injecter, ne pas casser la session.
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":""}}'
  exit 0
fi

HEADER="📐 Conventions globales ezacae (plugin ezacae-base) — à respecter ; le CLAUDE.md du projet prime en cas de conflit."

if command -v jq >/dev/null 2>&1; then
  jq -n --arg h "$HEADER" --rawfile c "$CONV" \
    '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:($h + "\n\n" + $c)}}'
else
  # Repli sans jq : échapper le contenu pour un JSON sur une ligne.
  body="$HEADER

$(cat "$CONV")"
  esc=${body//\\/\\\\}; esc=${esc//\"/\\\"}; esc=${esc//$'\t'/\\t}; esc=${esc//$'\n'/\\n}
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}' "$esc"
fi
exit 0
