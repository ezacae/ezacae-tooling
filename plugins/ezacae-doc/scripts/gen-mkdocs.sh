#!/usr/bin/env bash
#
# gen-mkdocs.sh — génère mécaniquement mkdocs.yml à partir de l'arbre docs/.
#
# Source unique de vérité pour la navigation de la doc ezacae (RD-2). Remplace
# la génération « à la main » par le LLM dans les commandes Mike : le fichier
# est TOUJOURS produit, cohérent, et reflète exactement les .md présents
# (création ET suppression couvertes par régénération complète idempotente).
#
# Sans mkdocs.yml, la conversion Markdown → HTML ne se fait pas. Ce script
# garantit sa présence.
#
# Usage :
#   gen-mkdocs.sh [REPO_ROOT] [--site-name "Nom"] [--check]
#
#   REPO_ROOT     racine du repo doc (défaut : répertoire courant).
#                 Doit contenir un dossier docs/.
#   --site-name   force le site_name (sinon extrait de .claude/CLAUDE.md,
#                 fallback : nom du dossier REPO_ROOT).
#   --check       n'écrit rien ; sort 0 si mkdocs.yml est déjà à jour,
#                 sort 1 (avec diff sur stderr) s'il est absent ou périmé.
#                 Pour un garde-fou CI / hook pre-commit.
#
# Sortie : écrit REPO_ROOT/mkdocs.yml (créé si absent, écrasé sinon).
# Compatible bash 3.2 (macOS) — pas de tableaux associatifs.

set -euo pipefail

# --- Arguments -----------------------------------------------------------------

REPO_ROOT=""
SITE_NAME_OVERRIDE=""
CHECK=0

while [ $# -gt 0 ]; do
  case "$1" in
    --site-name)    SITE_NAME_OVERRIDE="${2:-}"; shift 2 ;;
    --site-name=*)  SITE_NAME_OVERRIDE="${1#--site-name=}"; shift ;;
    --check)        CHECK=1; shift ;;
    -h|--help)      grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)             echo "gen-mkdocs: option inconnue : $1" >&2; exit 2 ;;
    *)
      if [ -z "$REPO_ROOT" ]; then REPO_ROOT="$1"
      else echo "gen-mkdocs: argument superflu : $1" >&2; exit 2; fi
      shift ;;
  esac
done

[ -n "$REPO_ROOT" ] || REPO_ROOT="$PWD"

if [ ! -d "$REPO_ROOT" ]; then
  echo "gen-mkdocs: REPO_ROOT introuvable : $REPO_ROOT" >&2; exit 1
fi
REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"

DOCS_DIR="$REPO_ROOT/docs"
if [ ! -d "$DOCS_DIR" ]; then
  echo "gen-mkdocs: pas de dossier docs/ dans $REPO_ROOT — rien à générer." >&2
  exit 1
fi

# --- Mapping dossier → section, fichier → label (bash 3.2 : case) --------------

KNOWN_SECTIONS="00_vision 01_product 02_architecture 03_donnees 04_exploitation"

# titlecase : "variables-env" → "Variables env" (fallback fichiers/dossiers hors mapping)
titlecase() {
  local s first rest
  s="$(printf '%s' "$1" | tr '_-' '  ')"
  first="$(printf '%s' "$s" | cut -c1 | tr '[:lower:]' '[:upper:]')"
  rest="$(printf '%s' "$s" | cut -c2-)"
  printf '%s%s' "$first" "$rest"
}

section_title() {
  case "$1" in
    00_vision)       echo "Vision" ;;
    01_product)      echo "Produit" ;;
    02_architecture) echo "Architecture" ;;
    03_donnees)      echo "Données" ;;
    04_exploitation) echo "Exploitation" ;;
    *)               titlecase "$1" ;;
  esac
}

# Ordre des fichiers connus par dossier (les autres suivent, triés).
file_order() {
  case "$1" in
    00_vision)       echo "vision.md" ;;
    01_product)      echo "personas.md processus.md fonctions.md" ;;
    02_architecture) echo "architecture.md auth.md ecrans-ui.md interactions-ui.md fonctions-techniques.md" ;;
    03_donnees)      echo "bdd.md api-endpoints.md" ;;
    04_exploitation) echo "variables-env.md deploiement.md tests.md" ;;
    *)               echo "" ;;
  esac
}

# file_label DIR SUBPATH — label lisible. DIR="" pour la racine de docs/.
# Le mapping connu porte sur les fichiers de profondeur 1 (DIR/base). Les
# fichiers plus profonds ou hors mapping : titlecase du basename sans extension.
file_label() {
  local key="$1/$2"
  case "$key" in
    00_vision/vision.md)                     echo "Vision produit" ;;
    01_product/personas.md)                  echo "Personas" ;;
    01_product/processus.md)                 echo "Processus métier" ;;
    01_product/fonctions.md)                 echo "Fonctionnalités" ;;
    02_architecture/architecture.md)         echo "Architecture stack" ;;
    02_architecture/auth.md)                 echo "Authentification" ;;
    02_architecture/ecrans-ui.md)            echo "Écrans & navigation" ;;
    02_architecture/interactions-ui.md)      echo "Interactions UI" ;;
    02_architecture/fonctions-techniques.md) echo "Fonctions techniques" ;;
    03_donnees/bdd.md)                       echo "Modèle de données" ;;
    03_donnees/api-endpoints.md)             echo "API endpoints" ;;
    04_exploitation/variables-env.md)        echo "Variables d'environnement" ;;
    04_exploitation/deploiement.md)          echo "Déploiement" ;;
    04_exploitation/tests.md)                echo "Tests & qualité" ;;
    /index.md)                               echo "Accueil" ;;
    *)  local base; base="$(basename "$2")"; titlecase "${base%.md}" ;;
  esac
}

# yaml_escape : échappe pour un scalaire YAML entre guillemets doubles.
yaml_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# --- site_name -----------------------------------------------------------------

resolve_site_name() {
  if [ -n "$SITE_NAME_OVERRIDE" ]; then
    printf '%s' "$SITE_NAME_OVERRIDE"; return
  fi
  local claude_md="$REPO_ROOT/.claude/CLAUDE.md" name=""
  if [ -f "$claude_md" ]; then
    name="$(grep -m1 '^# ' "$claude_md" 2>/dev/null | sed -e 's/^# *//' -e 's/[[:space:]]*$//')"
  fi
  [ -n "$name" ] || name="$(basename "$REPO_ROOT")"
  printf 'Documentation — %s' "$name"
}

# --- Listing -------------------------------------------------------------------
# Chemins .md relatifs à docs/, triés (LC_ALL=C) pour un rendu déterministe.
list_md() {
  ( cd "$DOCS_DIR" && find . -type f -name '*.md' 2>/dev/null \
      | sed 's#^\./##' | LC_ALL=C sort )
}

# Sous-chemins .md à la racine de docs/ (sans "/").
root_files() {
  list_md | while IFS= read -r rel; do
    case "$rel" in */*) : ;; *) printf '%s\n' "$rel" ;; esac
  done
}

# Sous-dossiers de docs/ contenant au moins un .md (profondeur 1), triés-uniques.
dirs_with_md() {
  list_md | while IFS= read -r rel; do
    case "$rel" in */*) printf '%s\n' "${rel%%/*}" ;; esac
  done | LC_ALL=C sort -u
}

# Sous-chemins .md à l'intérieur de docs/DIR (relatifs à DIR, toute profondeur).
subpaths_in() {
  local dir="$1"
  list_md | while IFS= read -r rel; do
    case "$rel" in "$dir"/*) printf '%s\n' "${rel#$dir/}" ;; esac
  done
}

# ordered_subpaths DIR : mapping d'abord (profondeur 1), puis le reste trié.
ordered_subpaths() {
  local dir="$1" present known f
  present="$(subpaths_in "$dir")"
  [ -n "$present" ] || return 0
  known="$(file_order "$dir")"
  # 1) fichiers connus (profondeur 1), dans l'ordre, s'ils sont présents.
  for f in $known; do
    printf '%s\n' "$present" | grep -qx "$f" && printf '%s\n' "$f"
  done
  # 2) le reste (dont sous-dossiers profonds), trié, en excluant les connus déjà émis.
  printf '%s\n' "$present" | LC_ALL=C sort | while IFS= read -r f; do
    [ -n "$f" ] || continue
    case " $known " in *" $f "*) continue ;; esac
    printf '%s\n' "$f"
  done
}

# --- Génération ----------------------------------------------------------------

if [ -z "$(list_md)" ]; then
  echo "gen-mkdocs: aucun .md dans docs/ — mkdocs.yml non généré." >&2
  exit 1
fi

MKDOCS_FILE="$REPO_ROOT/mkdocs.yml"
TMP="$(mktemp "${TMPDIR:-/tmp}/mkdocs.XXXXXX")"
trap 'rm -f "$TMP"' EXIT

SITE_NAME="$(resolve_site_name)"

{
  printf 'site_name: "%s"\n' "$(yaml_escape "$SITE_NAME")"
  printf 'docs_dir: docs\n'
  printf 'theme:\n'
  printf '  name: material\n'
  printf 'nav:\n'

  # 1) Racine de docs/ : index.md → Accueil en premier, puis les autres.
  root="$(root_files)"
  if printf '%s\n' "$root" | grep -qx "index.md"; then
    printf '  - %s: %s\n' "$(file_label "" "index.md")" "index.md"
  fi
  printf '%s\n' "$root" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ "$f" = "index.md" ] && continue
    printf '  - %s: %s\n' "$(file_label "" "$f")" "$f"
  done

  # 2) Sections connues (ordre fixe), puis inconnues (triées).
  present_dirs="$(dirs_with_md)"
  emit_section() {
    local d="$1" files
    files="$(ordered_subpaths "$d")"
    [ -n "$files" ] || return 0
    printf '  - %s:\n' "$(section_title "$d")"
    printf '%s\n' "$files" | while IFS= read -r f; do
      [ -n "$f" ] || continue
      printf '      - %s: %s/%s\n' "$(file_label "$d" "$f")" "$d" "$f"
    done
  }
  for d in $KNOWN_SECTIONS; do
    printf '%s\n' "$present_dirs" | grep -qx "$d" && emit_section "$d"
  done
  printf '%s\n' "$present_dirs" | while IFS= read -r d; do
    [ -n "$d" ] || continue
    case " $KNOWN_SECTIONS " in *" $d "*) continue ;; esac
    emit_section "$d"
  done
} > "$TMP"

if [ "$CHECK" -eq 1 ]; then
  if [ -f "$MKDOCS_FILE" ] && diff -q "$MKDOCS_FILE" "$TMP" >/dev/null 2>&1; then
    echo "gen-mkdocs: mkdocs.yml à jour."
    exit 0
  fi
  if [ -f "$MKDOCS_FILE" ]; then
    echo "gen-mkdocs: mkdocs.yml PÉRIMÉ — régénération nécessaire (diff attendu → actuel) :" >&2
    diff -u "$MKDOCS_FILE" "$TMP" >&2 || true
  else
    echo "gen-mkdocs: mkdocs.yml ABSENT — régénération nécessaire." >&2
  fi
  exit 1
fi

mv "$TMP" "$MKDOCS_FILE"
trap - EXIT
echo "gen-mkdocs: $MKDOCS_FILE généré ($(list_md | grep -c .) fichiers .md)."
