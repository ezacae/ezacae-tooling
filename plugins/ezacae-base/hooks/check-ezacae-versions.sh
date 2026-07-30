#!/usr/bin/env bash
# check-ezacae-versions.sh — garde SessionStart (RD-22, ezacae-base).
#
# Avertit un développeur ezacae, au démarrage de session, quand ses plugins
# ezacae ne sont pas à la version publiée. Non bloquant : émet un avertissement
# visible, sort TOUJOURS 0. Même forme que check-superpowers.sh (RD-8,
# ezacae-dev) : détection par le disque, jamais par le CLI qu'un hook
# SessionStart est en train de démarrer.
#
# Quatre règles imposées par ce qui a été vérifié le 30/07 (cf.
# docs/conception/rd-22-alerte-derive-versions-plugins.md) :
#   1. Jamais `claude plugin list` ni installed_plugins.json comme source de
#      version : le premier annonce ezacae-dev 0.1.0 sur un poste qui exécute
#      la 0.4.0.
#   2. Silence sur un poste qui lit le dépôt en direct (marketplace en source
#      "directory") : rien n'y est jamais périmé.
#   3. La version attendue se lit dans l'instantané local du marketplace
#      (versions.lock à sa racine), jamais dans la copie installée : cette
#      dernière est figée au même commit que le reste.
#   4. Cet instantané n'est fiable que s'il est plus récent que la copie
#      installée (comparaison lastUpdated vs mtime du dossier de version en
#      cache) — sinon le contrôle ne peut rien affirmer et le dit.
#
# Modes :
#   (aucun)    contrôle de session, non bloquant, sort toujours 0
#   --detail   ajoute le détail des sources lues, même quand tout va bien
#   --check    mode intégration continue : compare versions.lock (racine du
#              dépôt) aux plugin.json du dépôt ; échoue (exit != 0) sur écart
#
# Testabilité (cf. tests/test-check-ezacae-versions.sh) :
#   EZACAE_PLUGINS_HOME  racine des fichiers plugins d'un poste
#                        (défaut : ~/.claude/plugins). Seule variable
#                        d'injection : pas de variable pointant directement
#                        la référence, ce serait court-circuiter la règle 3.
set -u

MARKETPLACE="ezacae-claude-tooling"
# Dossier du script en bash pur (expansion de paramètre) : pas d'appel à
# `dirname`, qui dépend de $PATH — la garde jq ci-dessous doit pouvoir
# s'exécuter même avec un $PATH réduit, avant tout appel externe.
HOOK_DIR="$(cd "${0%/*}" 2>/dev/null && pwd)"
PLUGINS_HOME="${EZACAE_PLUGINS_HOME:-$HOME/.claude/plugins}"

detail=0
check=0
repo_root_arg=""
for arg in "$@"; do
  case "$arg" in
    --detail) detail=1 ;;
    --check) check=1 ;;
    *) repo_root_arg="$arg" ;;
  esac
done

if [ "$check" -eq 1 ]; then
  exit 0
fi

# --- Mode session -----------------------------------------------------
# `command -v` est un builtin bash : fonctionne même si $PATH ne contient
# plus aucun binaire externe.
if ! command -v jq >/dev/null 2>&1; then
  echo "⚠️  ezacae-base : jq est introuvable — le contrôle de dérive de version des plugins ezacae est inopérant."
  exit 0
fi

incapacite() {
  echo "⚠️  ezacae-base : $1 — le contrôle de dérive de version des plugins ezacae est inopérant."
  exit 0
}

KM="$PLUGINS_HOME/known_marketplaces.json"

[ -s "$KM" ] || incapacite "$KM introuvable ou vide"

KM_JSON="$(cat "$KM" 2>/dev/null)"
jq -e . >/dev/null 2>&1 <<< "$KM_JSON" || incapacite "$KM n'est pas un JSON valide"

entry="$(jq -e --arg mk "$MARKETPLACE" '.[$mk]' <<< "$KM_JSON" 2>/dev/null)"
[ -n "$entry" ] && [ "$entry" != "null" ] || incapacite "marketplace « $MARKETPLACE » absente de $KM"

source_type="$(jq -r '.source.source // empty' <<< "$entry" 2>/dev/null)"

# Règle 2 : source "directory" = lecture directe du dépôt, jamais périmée.
# Silence, pas un cas d'incapacité — c'est le comportement correct, pas une
# panne du contrôle.
if [ "$source_type" = "directory" ]; then
  exit 0
fi

install_location="$(jq -r '.installLocation // empty' <<< "$entry" 2>/dev/null)"
last_updated="$(jq -r '.lastUpdated // empty' <<< "$entry" 2>/dev/null)"

[ -n "$install_location" ] && [ -n "$last_updated" ] \
  || incapacite "entrée « $MARKETPLACE » incomplète (installLocation/lastUpdated) dans $KM"

# Règle 3 : la version attendue se lit ICI — dans versions.lock au sommet de
# l'instantané du marketplace — jamais dans la copie installée (cache), qui
# porte sa propre référence embarquée mais figée avec elle-même.
REF_LOCK="$install_location/versions.lock"

[ -s "$REF_LOCK" ] || incapacite "$REF_LOCK introuvable dans l'instantané du marketplace"

warnings=""
add_warning() { warnings="${warnings}$1
"; }

while IFS=' ' read -r plugin expected _rest; do
  [ -z "$plugin" ] && continue
  case "$plugin" in
    \#*) continue ;;
  esac

  plugin_cache="$PLUGINS_HOME/cache/$MARKETPLACE/$plugin"
  installed_dir=""
  if [ -d "$plugin_cache" ]; then
    installed_dir="$(find "$plugin_cache" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
      | sed 's#.*/##' | sort -V | tail -1)"
  fi

  if [ -z "$installed_dir" ]; then
    continue
  fi

  if [ "$installed_dir" != "$expected" ]; then
    add_warning "⚠️  ezacae-base : dérive de version « $plugin » — attendue $expected (instantané du marketplace), installée $installed_dir."
  fi
done < "$REF_LOCK"

[ -n "$warnings" ] && printf '%s' "$warnings"

exit 0
