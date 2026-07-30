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

# =====================================================================
# Tâche 1.4 : poste en lecture directe du dépôt → silence
# =====================================================================
t1_4() {
  local tmp; tmp="$(mktemp -d)"
  local home="$tmp/plugins"
  mkdir -p "$home"

  cat > "$home/known_marketplaces.json" <<JSON
{
  "$MARKETPLACE": {
    "source": { "source": "directory", "path": "/some/local/checkout" },
    "installLocation": "/some/local/checkout",
    "lastUpdated": "2020-01-01T00:00:00.000Z"
  }
}
JSON

  # Vieille version dans le cache : même sur ce poste, ne doit rien déclencher.
  mkdir -p "$home/cache/$MARKETPLACE/ezacae-doc/0.1.0/commands"
  touch -t 202001010000 "$home/cache/$MARKETPLACE/ezacae-doc/0.1.0" 2>/dev/null

  local out code
  out=$(run_check "$home"); code=$?
  eq "1.4 source directory → sortie vide" "" "$out"
  eq "1.4 source directory → exit 0" "0" "$code"

  rm -rf "$tmp"
}

t1_4

# =====================================================================
# Tâche 2.1 : la référence se lit dans l'instantané du marketplace, jamais
# dans la copie installée (règle 3). Aucune variable d'environnement ne
# désigne la référence : elle n'est plaçable qu'à l'endroit réel.
# =====================================================================
t2_1() {
  local tmp; tmp="$(mktemp -d)"
  local home="$tmp/plugins"
  local snap="$home/marketplaces/ezacae-claude-tooling"
  mkdir -p "$snap/plugins/ezacae-doc/.claude-plugin"
  mkdir -p "$home"

  # lastUpdated confortablement postérieur à la copie installée : cette
  # tâche ne teste pas encore la fraîcheur (tâche 2.2), juste la source lue.
  cat > "$home/known_marketplaces.json" <<JSON
{
  "$MARKETPLACE": {
    "source": { "source": "git", "url": "git@example.invalid:ezacae/ezacae-claude-tooling.git" },
    "installLocation": "$snap",
    "lastUpdated": "2099-01-01T00:00:00.000Z"
  }
}
JSON

  # La vraie référence : ezacae-doc 0.3.2, dans l'instantané.
  printf 'ezacae-doc 0.3.2\n' > "$snap/versions.lock"
  printf '{ "name": "ezacae-doc", "version": "0.3.2" }\n' > "$snap/plugins/ezacae-doc/.claude-plugin/plugin.json"

  # La copie installée : version 0.1.0, avec sa propre référence embarquée
  # (son propre plugin.json) qui se contredit forcément avec la vraie
  # référence — c'est la référence « figée avec la copie installée » que la
  # règle 3 interdit de lire (elle vaudrait toujours 0.1.0 == 0.1.0 installé).
  mkdir -p "$home/cache/$MARKETPLACE/ezacae-doc/0.1.0/.claude-plugin"
  printf '{ "name": "ezacae-doc", "version": "0.1.0" }\n' > "$home/cache/$MARKETPLACE/ezacae-doc/0.1.0/.claude-plugin/plugin.json"
  touch -t 201001010000 "$home/cache/$MARKETPLACE/ezacae-doc/0.1.0" 2>/dev/null

  local out code
  out=$(run_check "$home"); code=$?
  contains "2.1 référence lue dans l'instantané → 0.3.2 retenu (pas 0.1.0 de la copie installée)" "0.3.2" "$out"
  contains "2.1 dérive détectée nomme le plugin" "ezacae-doc" "$out"
  eq       "2.1 exit 0" "0" "$code"

  rm -rf "$tmp"
}

t2_1

# =====================================================================
# Tâche 2.2 : référence pas plus récente que la copie installée →
# le contrôle avertit de son incapacité à se prononcer (règle 4).
#
# Reprise du test de revue critique (test-reference-figee.sh) : un poste
# dont l'instantané de marketplace n'a jamais été rafraîchi depuis
# l'installation a un lastUpdated aussi vieux que la copie installée.
# Comparer les deux versions conclurait à tort « à jour ».
# =====================================================================
t2_2() {
  local tmp; tmp="$(mktemp -d)"
  local home="$tmp/plugins"
  local snap="$home/marketplaces/ezacae-claude-tooling"
  mkdir -p "$snap/plugins/ezacae-doc/.claude-plugin"
  mkdir -p "$home/cache/$MARKETPLACE/ezacae-doc/0.1.0"

  cat > "$home/known_marketplaces.json" <<JSON
{
  "$MARKETPLACE": {
    "source": { "source": "git", "url": "git@example.invalid:ezacae/ezacae-claude-tooling.git" },
    "installLocation": "$snap",
    "lastUpdated": "2026-01-20T07:36:54.571Z"
  }
}
JSON

  # La référence embarquée dans l'instantané est figée à la même version que
  # la copie installée. La version réellement publiée depuis est 0.3.2 —
  # invisible d'ici, et c'est tout le problème.
  printf 'ezacae-doc 0.1.0\n' > "$snap/versions.lock"
  printf '{ "name": "ezacae-doc", "version": "0.1.0" }\n' > "$snap/plugins/ezacae-doc/.claude-plugin/plugin.json"

  # Vieillir l'instantané, SANS toucher la copie installée (laissée à sa
  # date de création, donc plus récente qu'un instantané jamais rafraîchi
  # depuis l'installation — exactement l'inversion que la règle 4 doit
  # détecter : la référence n'est PAS postérieure à l'installé).
  touch -t 202601200736 "$snap/versions.lock" "$snap" 2>/dev/null

  local out code
  out=$(run_check "$home"); code=$?
  contains "2.2 référence figée → nomme le plugin concerné" "ezacae-doc" "$out"
  contains "2.2 référence figée → donne le geste qui lève le doute" "claude plugin marketplace update" "$out"
  refutes  "2.2 référence figée → ne conclut jamais « à jour »" "à jour" "$out"
  nonempty "2.2 référence figée → ne reste pas muet" "$out"
  eq       "2.2 référence figée → reste non bloquant" "0" "$code"

  rm -rf "$tmp"
}

t2_2

# =====================================================================
# Tâche 2.3 : arborescence attendue absente de l'instantané → incapacité.
# La lecture de la référence suppose que l'instantané contient
# l'arborescence du dépôt (versions.lock à sa racine,
# plugins/<nom>/.claude-plugin/plugin.json) — vrai pour nos plugins
# internes, pas pour un marketplace externe (ex. claude-plugins-official,
# qui ne recopie pas les plugins externes sous plugins/).
# =====================================================================
t2_3() {
  local tmp; tmp="$(mktemp -d)"
  local home="$tmp/plugins"
  local snap="$home/marketplaces/ezacae-claude-tooling"
  mkdir -p "$snap"
  mkdir -p "$home"

  cat > "$home/known_marketplaces.json" <<JSON
{
  "$MARKETPLACE": {
    "source": { "source": "git", "url": "git@example.invalid:ezacae/ezacae-claude-tooling.git" },
    "installLocation": "$snap",
    "lastUpdated": "2099-01-01T00:00:00.000Z"
  }
}
JSON
  # Ni versions.lock, ni plugins/<nom>/.claude-plugin/plugin.json dans
  # l'instantané : structure absente, pas seulement vieille.

  local out code
  out=$(run_check "$home"); code=$?
  nonempty "2.3 arborescence absente → sortie non vide" "$out"
  refutes  "2.3 arborescence absente → ne conclut jamais « à jour »" "à jour" "$out"
  eq       "2.3 arborescence absente → exit 0" "0" "$code"

  rm -rf "$tmp"
}

t2_3

echo "-----"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] || exit 1
