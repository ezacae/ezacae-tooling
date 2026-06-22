#!/usr/bin/env bash
# Hook SessionStart — pré-vérifications déterministes du pipeline Mike ⇄ Sarah.
# Injecte en contexte l'état de synchronisation Git et la disponibilité JIRA,
# en remplacement des blocs bash "Phase 0" de mike.md / sarah.md.
#
# Sortie : JSON sur stdout (hookSpecificOutput.additionalContext). Rien d'autre
# ne doit être écrit sur stdout sous peine de casser le parsing du hook.
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT_DIR" 2>/dev/null || true

# Répertoire des helpers JIRA (jira-attach/jira-download), vivant dans le plugin.
# CLAUDE_PLUGIN_ROOT est défini quand le hook est lancé par Claude Code ; sinon on
# se rabat sur l'emplacement réel du script. Injecté dans le contexte pour que Mike
# retrouve les scripts sans connaître le chemin du cache plugin.
HELPER_DIR="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/scripts"

# Charge .claude/jira.env si les credentials ne sont pas déjà exportés.
if [ -z "${JIRA_BASE_URL:-}" ] && [ -f "$PROJECT_DIR/.claude/jira.env" ]; then
  set -a; . "$PROJECT_DIR/.claude/jira.env"; set +a
fi

# --- Synchronisation Git ---
GIT_CTX=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
  git fetch --quiet origin 2>/dev/null || GIT_CTX="(fetch impossible — hors-ligne ?) "
  UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || echo "")
  DIRTY=$(git status --porcelain 2>/dev/null)
  AHEAD=0; BEHIND=0
  if [ -n "$UPSTREAM" ]; then
    set -- $(git rev-list --left-right --count '@{u}...HEAD' 2>/dev/null || echo "0 0")
    BEHIND="${1:-0}"; AHEAD="${2:-0}"
  fi
  if [ -n "$DIRTY" ]; then
    STATE="modifications non commitées"
  elif [ "$BEHIND" != "0" ] && [ "$AHEAD" != "0" ]; then
    STATE="divergence (retard $BEHIND / avance $AHEAD) — résoudre manuellement"
  elif [ "$BEHIND" != "0" ]; then
    # Working tree propre et strictement en retard (pas de divergence) :
    # mise à jour fast-forward automatique. Le fetch ayant déjà eu lieu,
    # on fusionne l'upstream sans second appel réseau. --ff-only refuse
    # tout merge non trivial : aucun risque d'écraser l'historique local.
    if git merge --ff-only --quiet '@{u}' 2>/dev/null; then
      STATE="mis à jour automatiquement (fast-forward, +$BEHIND commit(s))"
    else
      STATE="en retard de $BEHIND commit(s) — fast-forward impossible, git pull manuel requis"
    fi
  elif [ "$AHEAD" != "0" ]; then
    STATE="en avance de $AHEAD commit(s)"
  else
    STATE="à jour"
  fi
  GIT_CTX="${GIT_CTX}branche '$BRANCH' — $STATE"
else
  GIT_CTX="hors dépôt Git"
fi

# --- Disponibilité JIRA ---
JIRA_MISSING=""
for v in JIRA_BASE_URL JIRA_EMAIL JIRA_API_TOKEN; do
  [ -z "${!v:-}" ] && JIRA_MISSING="$JIRA_MISSING $v"
done
if [ -z "$JIRA_MISSING" ]; then
  JIRA_CTX="credentials présents — pièces jointes (REST) et garde de statut ACTIVES"
else
  JIRA_CTX="credentials manquants :$JIRA_MISSING — pièces jointes et garde de statut INACTIVES (voir le skill jira-pipeline)"
fi
command -v jq >/dev/null 2>&1 || JIRA_CTX="$JIRA_CTX ; ⚠ jq absent (requis pour les helpers/garde)"

CTX="🔧 Pré-checks pipeline Mike⇄Sarah (hook SessionStart)
• Git : ${GIT_CTX}
• JIRA : ${JIRA_CTX}
• Helpers JIRA (REST, auto-autorisés — toutes les opérations JIRA passent par eux, AUCUN MCP ; fonctionnent en headless) :
    lire        : ${HELPER_DIR}/jira-get.sh <KEY> [--comments]
    commenter   : ${HELPER_DIR}/jira-comment.sh <KEY> \"texte\" | -f <fichier>
    transition  : ${HELPER_DIR}/jira-transition.sh <KEY> <STATUT-CIBLE> [--worklog 30m] [--comment \"…\"]
    éditer      : ${HELPER_DIR}/jira-edit.sh <KEY> [--summary|--description|--label|--assignee …]
    PJ          : ${HELPER_DIR}/jira-attach.sh <KEY> <fichier…> ; ${HELPER_DIR}/jira-download.sh <KEY> <dossier> [filtre]
    créer       : ${HELPER_DIR}/jira-create.sh --project <KEY> --type <NOM> --summary \"…\" [--description-file <f>]
    projets     : ${HELPER_DIR}/jira-projects.sh [<PROJECT-KEY>]   (sans arg = liste ; avec = types de ticket)
    rechercher  : ${HELPER_DIR}/jira-search.sh \"<JQL>\" [--max N]
    lier        : ${HELPER_DIR}/jira-link.sh <CLE-INWARD> <CLE-OUTWARD> [--type \"Relates\"]"

if command -v jq >/dev/null 2>&1; then
  jq -n --arg c "$CTX" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
else
  # Repli sans jq : émettre un JSON minimal échappé.
  esc=${CTX//\\/\\\\}; esc=${esc//\"/\\\"}; esc=${esc//$'\n'/\\n}
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}' "$esc"
fi
exit 0
