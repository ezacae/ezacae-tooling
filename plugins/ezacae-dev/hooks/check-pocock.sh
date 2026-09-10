#!/usr/bin/env bash
# check-pocock.sh — garde SessionStart (RD-42, ezacae-dev).
#
# Les compétences de Matt Pocock autorisées par la spec brique 1 (grill-me et sa
# dépendance grilling, handoff, to-tickets) sont installées EN RÉFÉRENCE sur
# chaque poste, jamais copiées dans ce dépôt :
#   npx skills add mattpocock/skills -g -a claude-code -s grill-me -s grilling -s handoff -s to-tickets -y
# L'outil `skills` copie chaque compétence dans ~/.claude/skills/<nom>/ et note
# son empreinte (skillFolderHash) dans ~/.agents/.skill-lock.json. Ce garde
# compare ces empreintes à `pocock.lock` (racine du plugin : « nom empreinte »
# par ligne, commentaires « # » ignorés) — même rôle que superpowers.lock.
#
# Non bloquant : émet un avertissement visible, sort TOUJOURS 0.
# Détection par le disque, jamais par un CLI (règle des hooks SessionStart).
#
# Testabilité (cf. tests/test-check-pocock.sh) :
#   POCOCK_SKILLS_DIR  dossier des compétences du poste (défaut : ~/.claude/skills)
#   POCOCK_CLI_LOCK    verrou écrit par l'outil skills (défaut : ~/.agents/.skill-lock.json)
#   POCOCK_LOCK        verrou du plugin (défaut : <hook>/../pocock.lock)
set -u

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="${POCOCK_SKILLS_DIR:-$HOME/.claude/skills}"
CLI_LOCK="${POCOCK_CLI_LOCK:-$HOME/.agents/.skill-lock.json}"
LOCK="${POCOCK_LOCK:-$HOOK_DIR/../pocock.lock}"
INSTALL_CMD="npx skills add mattpocock/skills -g -a claude-code"

[ -f "$LOCK" ] || exit 0

missing=""    # compétences absentes du poste
drift=""      # lignes « nom : attendue X, installée Y »
unverified="" # présentes sur le disque mais inconnues du verrou de l'outil

while read -r name expected _; do
  case "$name" in ''|'#'*) continue ;; esac
  if [ ! -f "$SKILLS_DIR/$name/SKILL.md" ]; then
    missing="$missing $name"; continue
  fi
  installed=""
  if [ -f "$CLI_LOCK" ] && command -v jq >/dev/null 2>&1; then
    installed="$(jq -r --arg n "$name" '.skills[$n].skillFolderHash // empty' "$CLI_LOCK" 2>/dev/null)"
  fi
  if [ -z "$installed" ]; then
    unverified="$unverified $name"
  elif [ "$installed" != "$expected" ]; then
    drift="$drift
    • $name : attendue $expected (pocock.lock), installée $installed"
  fi
done < "$LOCK"

if [ -n "$missing" ]; then
  flags=""; for n in $missing; do flags="$flags -s $n"; done
  echo "⚠️  ezacae-dev : compétence(s) Pocock absente(s) du poste :${missing}. /scope et /to-tickets en dépendent."
  echo "    Installe-les : ${INSTALL_CMD}${flags} -y"
fi
if [ -n "$drift" ]; then
  echo "⚠️  ezacae-dev : dérive de version des compétences Pocock :${drift}"
  echo "    Vérifie que le comportement reste compatible, puis mets à jour pocock.lock si le changement est validé."
fi
if [ -n "$unverified" ]; then
  echo "⚠️  ezacae-dev : compétence(s) Pocock présente(s) mais installée(s) hors de l'outil skills :${unverified}. Version non vérifiable."
  echo "    Réinstalle-les en référence : ${INSTALL_CMD} -s <nom> -y"
fi
exit 0
