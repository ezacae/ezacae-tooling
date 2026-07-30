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
  # --- Mode intégration continue -------------------------------------
  # Racine du dépôt : déduite de l'emplacement du script (hooks/ → trois
  # niveaux au-dessus : hooks → ezacae-base → plugins → racine), ou
  # fournie en argument pour les tests. Ce n'est PAS EZACAE_PLUGINS_HOME
  # (le dossier plugins d'un poste) : deux entrées distinctes.
  if [ -n "$repo_root_arg" ]; then
    REPO_ROOT="$repo_root_arg"
  else
    REPO_ROOT="$(cd "$HOOK_DIR/../../.." 2>/dev/null && pwd)"
  fi

  CHECK_LOCK="$REPO_ROOT/versions.lock"
  if [ ! -f "$CHECK_LOCK" ]; then
    echo "✗ versions.lock introuvable : $CHECK_LOCK"
    exit 1
  fi

  check_status=0

  # Chaque plugin présent sous plugins/ doit être déclaré dans
  # versions.lock, avec la même version que son plugin.json.
  for plugin_dir in "$REPO_ROOT"/plugins/*/; do
    [ -d "$plugin_dir" ] || continue
    plugin_name="$(basename "$plugin_dir")"
    plugin_manifest="${plugin_dir}.claude-plugin/plugin.json"
    [ -f "$plugin_manifest" ] || continue
    real_version="$(jq -r '.version // empty' "$plugin_manifest" 2>/dev/null)"
    lock_line="$(grep -E "^${plugin_name} " "$CHECK_LOCK" | head -1)"
    if [ -z "$lock_line" ]; then
      echo "✗ $plugin_name : présent sous plugins/ mais absent de versions.lock"
      check_status=1
      continue
    fi
    lock_version="$(printf '%s' "$lock_line" | awk '{print $2}')"
    if [ "$real_version" != "$lock_version" ]; then
      echo "✗ $plugin_name : versions.lock annonce $lock_version, plugin.json déclare $real_version"
      check_status=1
    fi
  done

  # Chaque ligne de versions.lock doit correspondre à un plugin réel.
  while IFS=' ' read -r lock_plugin _lock_ver _lock_rest; do
    [ -z "$lock_plugin" ] && continue
    case "$lock_plugin" in
      \#*) continue ;;
    esac
    if [ ! -f "$REPO_ROOT/plugins/$lock_plugin/.claude-plugin/plugin.json" ]; then
      echo "✗ $lock_plugin : présent dans versions.lock mais aucun plugin correspondant sous plugins/"
      check_status=1
    fi
  done < "$CHECK_LOCK"

  exit $check_status
fi

# --- Mode session -----------------------------------------------------
incapacite() {
  echo "⚠️  ezacae-base : $1 — le contrôle de dérive de version des plugins ezacae est inopérant."
  exit 0
}

# `command -v` est un builtin bash : fonctionne même si $PATH ne contient
# plus aucun binaire externe. incapacite() ne dépend pas de jq : la définir
# avant cette garde permet de l'appeler ici au lieu de recopier son gabarit.
if ! command -v jq >/dev/null 2>&1; then
  incapacite "jq est introuvable"
fi

KM="$PLUGINS_HOME/known_marketplaces.json"

[ -s "$KM" ] || incapacite "$KM introuvable ou vide"

KM_JSON="$(cat "$KM" 2>/dev/null)"
jq -e . >/dev/null 2>&1 <<< "$KM_JSON" || incapacite "$KM n'est pas un JSON valide"

entry="$(jq -e --arg mk "$MARKETPLACE" '.[$mk]' <<< "$KM_JSON" 2>/dev/null)"
[ -n "$entry" ] && [ "$entry" != "null" ] || incapacite "marketplace « $MARKETPLACE » absente de $KM"

source_type="$(jq -r '.source.source // empty' <<< "$entry" 2>/dev/null)"
install_location="$(jq -r '.installLocation // empty' <<< "$entry" 2>/dev/null)"
last_updated="$(jq -r '.lastUpdated // empty' <<< "$entry" 2>/dev/null)"

# Règle 2 : source "directory" = lecture directe du dépôt, jamais périmée.
# Silence en mode normal — pas un cas d'incapacité, c'est le comportement
# correct. --detail reste utile ici : il montre ce qu'il y a à voir (aucune
# dérive possible n'empêche de comprendre un poste dont on doute).
if [ "$source_type" = "directory" ]; then
  if [ "$detail" -eq 1 ]; then
    echo "ℹ️  ezacae-base — détail des sources lues :
    marketplace : $MARKETPLACE (source : directory — lecture directe du dépôt, aucune dérive possible)
    dépôt       : $install_location"
    if [ -n "$install_location" ] && [ -s "$install_location/versions.lock" ]; then
      while IFS=' ' read -r d_plugin d_version _rest; do
        [ -z "$d_plugin" ] && continue
        case "$d_plugin" in \#*) continue ;; esac
        echo "    $d_plugin : $d_version (versions.lock du dépôt)"
      done < "$install_location/versions.lock"
    fi
  fi
  exit 0
fi

[ -n "$install_location" ] && [ -n "$last_updated" ] \
  || incapacite "entrée « $MARKETPLACE » incomplète (installLocation/lastUpdated) dans $KM"

# Règle 3 : la version attendue se lit ICI — dans versions.lock au sommet de
# l'instantané du marketplace — jamais dans la copie installée (cache), qui
# porte sa propre référence embarquée mais figée avec elle-même.
REF_LOCK="$install_location/versions.lock"

[ -s "$REF_LOCK" ] || incapacite "$REF_LOCK introuvable dans l'instantané du marketplace"

# --- Portabilité : le poste de dev est BSD (macOS), la CI tourne sur
# alpine (busybox). `stat -f`/`date -j -f` (BSD) et `stat -c`/`date -d`
# (GNU/busybox) diffèrent ; on tente les deux formes et on ne garde que le
# premier résultat purement numérique (une erreur d'une des deux formes peut
# écrire du texte sur stdout, pas seulement stderr — busybox `stat -f` le
# fait — donc on filtre, on ne se fie pas qu'au code de sortie).
numeric_only() {
  case "$1" in
    ''|*[!0-9]*) printf '' ;;
    *) printf '%s' "$1" ;;
  esac
}

epoch_of_mtime() {
  local f="$1" out
  out="$(numeric_only "$(stat -f %m "$f" 2>/dev/null)")"
  [ -n "$out" ] || out="$(numeric_only "$(stat -c %Y "$f" 2>/dev/null)")"
  printf '%s' "$out"
}

epoch_of_iso() {
  local iso="$1" clean out
  clean="${iso%Z}"
  clean="${clean%%.*}"
  out="$(numeric_only "$(date -j -u -f '%Y-%m-%dT%H:%M:%S' "$clean" +%s 2>/dev/null)")"
  [ -n "$out" ] || out="$(numeric_only "$(date -u -d "$iso" +%s 2>/dev/null)")"
  [ -n "$out" ] || out="$(numeric_only "$(date -u -D '%Y-%m-%dT%H:%M:%S' -d "$clean" +%s 2>/dev/null)")"
  [ -n "$out" ] || out="$(numeric_only "$(date -u -d "${clean/T/ }" +%s 2>/dev/null)")"
  printf '%s' "$out"
}

lu_epoch="$(epoch_of_iso "$last_updated")"
[ -n "$lu_epoch" ] || incapacite "date « $last_updated » illisible (lastUpdated) dans $KM"

warnings=""
add_warning() { warnings="${warnings}$1
"; }

details=""
add_detail() { details="${details}$1
"; }
[ "$detail" -eq 1 ] && add_detail "ℹ️  ezacae-base — détail des sources lues :
    marketplace : $MARKETPLACE (source : $source_type)
    instantané  : $install_location
    lastUpdated : $last_updated"

# Version sémantique simple X.Y.Z. Les formes non sémantiques constatées
# (`unknown`, identifiant de commit type `655b7d9c5431`) ne se comparent
# pas numériquement : un avertissement permanent qu'aucune mise à jour ne
# ferait taire serait pire que pas d'avertissement.
is_semver() {
  case "$1" in
    [0-9]*.[0-9]*.[0-9]*)
      case "$1" in
        *[!0-9.]*) return 1 ;;
        *) return 0 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

while IFS=' ' read -r plugin expected _rest; do
  [ -z "$plugin" ] && continue
  case "$plugin" in
    \#*) continue ;;
  esac

  plugin_cache="$PLUGINS_HOME/cache/$MARKETPLACE/$plugin"
  installed_dir=""
  if [ -d "$plugin_cache" ]; then
    all_dirs="$(find "$plugin_cache" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's#.*/##')"
    semver_dirs=""
    while IFS= read -r d; do
      [ -z "$d" ] && continue
      if is_semver "$d"; then
        semver_dirs="${semver_dirs}${d}
"
      fi
    done <<< "$all_dirs"
    if [ -n "$semver_dirs" ]; then
      # Plusieurs versions sémantiques en cache (ex. superpowers 6.1.1 et
      # 6.2.0 côte à côte) : la plus haute (sort -V) est retenue.
      installed_dir="$(printf '%s' "$semver_dirs" | sort -V | tail -1)"
    else
      # Aucun dossier sémantique : version indéterminée, on en retient un
      # (peu importe lequel, aucune comparaison chiffrée n'en sera faite).
      installed_dir="$(printf '%s' "$all_dirs" | sort | tail -1)"
    fi
  fi

  if [ -z "$installed_dir" ]; then
    add_warning "⚠️  ezacae-base : plugin « $plugin » attendu (versions.lock) mais absent du poste.
    Installe-le : claude plugin install $plugin@$MARKETPLACE"
    [ "$detail" -eq 1 ] && add_detail "    $plugin : attendu $expected — absent du cache ($plugin_cache)"
    continue
  fi

  if ! is_semver "$installed_dir"; then
    add_warning "⚠️  ezacae-base : version installée de « $plugin » indéterminée ($installed_dir) — impossible de la comparer à la référence attendue."
    [ "$detail" -eq 1 ] && add_detail "    $plugin : attendu $expected — installé $installed_dir (non sémantique, $plugin_cache/$installed_dir)"
    continue
  fi

  installed_mtime="$(epoch_of_mtime "$plugin_cache/$installed_dir")"

  # Règle 4 : l'instantané ne peut rien affirmer de plus récent que ce qui
  # est déjà installé. Condition sans seuil arbitraire : lastUpdated doit
  # être STRICTEMENT postérieur au dossier de version en cache.
  if [ -z "$installed_mtime" ] || [ "$lu_epoch" -le "$installed_mtime" ]; then
    add_warning "⚠️  ezacae-base : impossible de se prononcer sur « $plugin » — l'instantané du marketplace n'est pas plus récent que la copie installée, sa référence ne prouve rien de plus.
    Rafraîchis-le : claude plugin marketplace update $MARKETPLACE"
    [ "$detail" -eq 1 ] && add_detail "    $plugin : attendu $expected — installé $installed_dir ($plugin_cache/$installed_dir) — instantané pas plus récent"
    continue
  fi

  if [ "$installed_dir" != "$expected" ]; then
    add_warning "⚠️  ezacae-base : dérive de version « $plugin » — attendue $expected (instantané du marketplace), installée $installed_dir."
  fi
  [ "$detail" -eq 1 ] && add_detail "    $plugin : attendu $expected — installé $installed_dir ($plugin_cache/$installed_dir)"
done < "$REF_LOCK"

[ -n "$warnings" ] && printf '%s' "$warnings"
[ "$detail" -eq 1 ] && printf '%s' "$details"

exit 0
