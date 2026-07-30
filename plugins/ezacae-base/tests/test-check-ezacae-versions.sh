#!/usr/bin/env bash
# Tests du garde SessionStart check-ezacae-versions.sh (RD-22, ezacae-base).
#
# Le garde avertit un développeur ezacae quand ses plugins ne sont pas à la
# version publiée, et dit quand il ne peut pas se prononcer. Non bloquant en
# mode session : sort toujours 0. Le mode --check (CI) est l'exception : il
# échoue en cas d'écart entre versions.lock et les plugin.json du dépôt.
#
# Détection par le disque (jamais `claude plugin list` : source prouvée fausse
# le 30/07 — cf. docs/conception/rd-22-alerte-derive-versions-plugins.md).
#
# Testabilité :
#   EZACAE_PLUGINS_HOME  racine des fichiers plugins d'un poste
#                        (défaut : ~/.claude/plugins)
#
# Hors-ligne, aucun appel réseau. Arborescences fabriquées dans un dossier
# temporaire par cas de test.

set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${EZACAE_CHECK_SCRIPT:-$DIR/../hooks/check-ezacae-versions.sh}"
MARKETPLACE="ezacae-claude-tooling"
BASH_BIN="$(command -v bash)"

pass=0; fail=0
contains() { if printf '%s' "$3" | grep -qF -- "$2"; then echo "PASS: $1"; pass=$((pass+1))
  else echo "FAIL: $1 — attendu contient «$2» — obtenu: «$3»"; fail=$((fail+1)); fi; }
refutes()  { if printf '%s' "$3" | grep -qF -- "$2"; then echo "FAIL: $1 — ne devait PAS contenir «$2» — obtenu: «$3»"; fail=$((fail+1))
  else echo "PASS: $1"; pass=$((pass+1)); fi; }
eq()       { if [ "$2" = "$3" ]; then echo "PASS: $1"; pass=$((pass+1))
  else echo "FAIL: $1 — attendu «$2» — obtenu «$3»"; fail=$((fail+1)); fi; }
nonempty() { if [ -n "$(printf '%s' "$2" | tr -d '[:space:]')" ]; then echo "PASS: $1"; pass=$((pass+1))
  else echo "FAIL: $1 — sortie vide, le contrôle est resté muet"; fail=$((fail+1)); fi; }

# =====================================================================
# Tâche 1.1 : squelette, sortie toujours en succès
# =====================================================================
t1_1() {
  local tmp; tmp="$(mktemp -d)"
  local out code
  out=$(EZACAE_PLUGINS_HOME="$tmp/inexistant" bash "$SCRIPT" 2>&1); code=$?
  eq "1.1 arborescence vide → exit 0 quelle que soit la sortie" "0" "$code"
  rm -rf "$tmp"
}

t1_1

# =====================================================================
# Tâche 1.2 : jq absent → une ligne, pas le silence
# =====================================================================
t1_2() {
  local tmp; tmp="$(mktemp -d)"
  # PATH réduit à un dossier sans jq (ni aucun binaire système, y compris
  # bash lui-même — on le relance donc via son chemin absolu, pas via $PATH).
  local emptybin="$tmp/emptybin"; mkdir -p "$emptybin"
  local out code
  out=$(EZACAE_PLUGINS_HOME="$tmp/plugins" PATH="$emptybin" "$BASH_BIN" "$SCRIPT" 2>&1); code=$?
  nonempty "1.2 jq absent → sortie non vide" "$out"
  contains "1.2 jq absent → mentionne jq" "jq" "$out"
  eq       "1.2 jq absent → exit 0" "0" "$code"
  rm -rf "$tmp"
}

t1_2

# =====================================================================
# Tâche 1.3 : structures illisibles → une ligne, pas le silence
# =====================================================================
run_check() {
  # $1 = EZACAE_PLUGINS_HOME
  EZACAE_PLUGINS_HOME="$1" bash "$SCRIPT" 2>&1
}

t1_3() {
  local tmp; tmp="$(mktemp -d)"
  local home="$tmp/plugins"

  # Cas a : known_marketplaces.json absent
  mkdir -p "$home"
  local out code
  out=$(run_check "$home"); code=$?
  nonempty "1.3a known_marketplaces.json absent → sortie non vide" "$out"
  eq       "1.3a known_marketplaces.json absent → exit 0" "0" "$code"

  # Cas b : known_marketplaces.json vide
  : > "$home/known_marketplaces.json"
  out=$(run_check "$home"); code=$?
  nonempty "1.3b known_marketplaces.json vide → sortie non vide" "$out"
  eq       "1.3b known_marketplaces.json vide → exit 0" "0" "$code"

  # Cas c : known_marketplaces.json JSON invalide
  printf '{ceci-nest-pas-du-json' > "$home/known_marketplaces.json"
  out=$(run_check "$home"); code=$?
  nonempty "1.3c JSON invalide → sortie non vide" "$out"
  eq       "1.3c JSON invalide → exit 0" "0" "$code"

  # Cas d : JSON valide mais sans entrée ezacae-claude-tooling
  printf '{"une-autre-marketplace": {"source": {"source": "git"}}}' > "$home/known_marketplaces.json"
  out=$(run_check "$home"); code=$?
  nonempty "1.3d marketplace absente → sortie non vide" "$out"
  eq       "1.3d marketplace absente → exit 0" "0" "$code"

  rm -rf "$tmp"
}

t1_3

echo "-----"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] || exit 1
