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

  # Les deux dates sont figées explicitement, indépendamment de l'horloge
  # de la machine qui exécute le test : sans ce second gel, le dossier de
  # version en cache porterait sa date de création (mkdir → "maintenant"),
  # et la relation testée dépendrait alors de l'heure courante du runner —
  # vraie aujourd'hui, mais qui s'inverserait sur une machine dont la date
  # réelle précède le 20/01/2026. La copie installée est figée à une date
  # postérieure à l'instantané (24h d'écart : `touch -t` interprète l'heure
  # donnée dans le fuseau local du runner, `lastUpdated` est en UTC — un
  # écart d'un jour entier absorbe n'importe quel décalage de fuseau réel),
  # exactement l'inversion que la règle 4 doit détecter : la référence
  # n'est PAS postérieure à l'installé.
  touch -t 202601200736 "$snap/versions.lock" "$snap" 2>/dev/null
  touch -t 202601211200 "$home/cache/$MARKETPLACE/ezacae-doc/0.1.0" 2>/dev/null

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

# =====================================================================
# Helper commun aux tâches de phase 3 : poste git à jour, instantané
# fraîchement rafraîchi (lastUpdated dans le futur du test).
# =====================================================================
setup_fresh_git_post() {
  # $1 = home, $2 = plugin, $3 = expected version (dans versions.lock)
  local home="$1" plugin="$2" expected="$3"
  local snap="$home/marketplaces/ezacae-claude-tooling"
  mkdir -p "$snap/plugins/$plugin/.claude-plugin"
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
  printf '%s %s\n' "$plugin" "$expected" > "$snap/versions.lock"
  printf '{ "name": "%s", "version": "%s" }\n' "$plugin" "$expected" > "$snap/plugins/$plugin/.claude-plugin/plugin.json"
}

# =====================================================================
# Tâche 3.1 : à jour → silence
# =====================================================================
t3_1() {
  local tmp; tmp="$(mktemp -d)"
  local home="$tmp/plugins"
  setup_fresh_git_post "$home" "ezacae-doc" "0.3.2"
  mkdir -p "$home/cache/$MARKETPLACE/ezacae-doc/0.3.2/commands"

  local out code
  out=$(run_check "$home"); code=$?
  eq "3.1 à jour → sortie vide" "" "$out"
  eq "3.1 à jour → exit 0" "0" "$code"

  rm -rf "$tmp"
}

t3_1

# =====================================================================
# Tâche 3.2 : en retard → avertit
# =====================================================================
t3_2() {
  local tmp; tmp="$(mktemp -d)"
  local home="$tmp/plugins"
  setup_fresh_git_post "$home" "ezacae-doc" "0.3.2"
  mkdir -p "$home/cache/$MARKETPLACE/ezacae-doc/0.1.0/commands"

  local out code
  out=$(run_check "$home"); code=$?
  contains "3.2 en retard → nomme le plugin" "ezacae-doc" "$out"
  contains "3.2 en retard → version attendue" "0.3.2" "$out"
  contains "3.2 en retard → version installée" "0.1.0" "$out"
  eq       "3.2 en retard → exit 0" "0" "$code"

  rm -rf "$tmp"
}

t3_2

# =====================================================================
# Tâche 3.3 : plugin absent → commande d'installation
# =====================================================================
t3_3() {
  local tmp; tmp="$(mktemp -d)"
  local home="$tmp/plugins"
  setup_fresh_git_post "$home" "ezacae-doc" "0.3.2"
  # Pas de cache du tout pour ce plugin : absent du poste.

  local out code
  out=$(run_check "$home"); code=$?
  contains "3.3 absent → commande d'installation" "claude plugin install" "$out"
  contains "3.3 absent → nomme le plugin" "ezacae-doc" "$out"
  eq       "3.3 absent → exit 0" "0" "$code"

  rm -rf "$tmp"
}

t3_3

# =====================================================================
# Tâche 3.4 : version installée non sémantique — message distinct, jamais
# de comparaison chiffrée ni de « en retard ».
# =====================================================================
t3_4_case() {
  local label="$1" dirname="$2"
  local tmp; tmp="$(mktemp -d)"
  local home="$tmp/plugins"
  setup_fresh_git_post "$home" "ezacae-doc" "0.3.2"
  mkdir -p "$home/cache/$MARKETPLACE/ezacae-doc/$dirname/commands"

  local out code
  out=$(run_check "$home"); code=$?
  contains "3.4 $label → nomme le plugin" "ezacae-doc" "$out"
  nonempty "3.4 $label → sortie non vide (version indéterminée signalée)" "$out"
  refutes  "3.4 $label → pas de comparaison chiffrée (0.3.2)" "0.3.2" "$out"
  refutes  "3.4 $label → jamais « en retard »" "en retard" "$out"
  eq       "3.4 $label → exit 0" "0" "$code"

  rm -rf "$tmp"
}

t3_4_case "unknown" "unknown"
t3_4_case "identifiant de commit" "655b7d9c5431"

# =====================================================================
# Tâche 3.5 : plusieurs versions en cache — la plus haute sémantique
# retenue ; un dossier bien formé prime sur un `unknown` côte à côte.
# =====================================================================
t3_5() {
  local tmp; tmp="$(mktemp -d)"
  local home="$tmp/plugins"
  setup_fresh_git_post "$home" "ezacae-doc" "0.3.2"
  mkdir -p "$home/cache/$MARKETPLACE/ezacae-doc/0.1.0/commands"
  mkdir -p "$home/cache/$MARKETPLACE/ezacae-doc/0.3.2/commands"

  local out code
  out=$(run_check "$home"); code=$?
  eq "3.5a deux versions sémantiques → la plus haute retenue (silence, à jour)" "" "$out"
  eq "3.5a exit 0" "0" "$code"
  rm -rf "$tmp"

  tmp="$(mktemp -d)"; home="$tmp/plugins"
  setup_fresh_git_post "$home" "ezacae-doc" "0.3.2"
  mkdir -p "$home/cache/$MARKETPLACE/ezacae-doc/unknown/commands"
  mkdir -p "$home/cache/$MARKETPLACE/ezacae-doc/0.3.2/commands"

  out=$(run_check "$home"); code=$?
  eq "3.5b un dossier bien formé + un unknown → le bien formé retenu (silence, à jour)" "" "$out"
  eq "3.5b exit 0" "0" "$code"
  rm -rf "$tmp"
}

t3_5

# =====================================================================
# Tâche 3.6 : option --detail — affiche les sources, chemins et dates,
# y compris quand tout va bien (silence en mode normal).
# =====================================================================
t3_6() {
  local tmp; tmp="$(mktemp -d)"
  local home="$tmp/plugins"
  setup_fresh_git_post "$home" "ezacae-doc" "0.3.2"
  local snap="$home/marketplaces/ezacae-claude-tooling"
  mkdir -p "$home/cache/$MARKETPLACE/ezacae-doc/0.3.2/commands"

  local out_silent code_silent out_detail code_detail
  out_silent=$(run_check "$home"); code_silent=$?
  eq "3.6 sans --detail, tout va bien → silence" "" "$out_silent"

  out_detail=$(EZACAE_PLUGINS_HOME="$home" bash "$SCRIPT" --detail 2>&1); code_detail=$?
  nonempty "3.6 --detail → sortie non vide même à jour" "$out_detail"
  contains "3.6 --detail → nomme le plugin" "ezacae-doc" "$out_detail"
  contains "3.6 --detail → chemin de l'instantané" "$snap" "$out_detail"
  contains "3.6 --detail → version attendue" "0.3.2" "$out_detail"
  contains "3.6 --detail → date lastUpdated" "2099-01-01" "$out_detail"
  eq       "3.6 --detail → exit 0" "0" "$code_detail"

  rm -rf "$tmp"
}

t3_6

# =====================================================================
# Tâche 4.1 : mode --check (intégration continue). Compare versions.lock
# (racine du dépôt) aux plugin.json du dépôt. Racine déduite de
# l'emplacement du script, ou fournie en argument (ici, toujours fournie :
# arborescence fabriquée, hors-ligne).
# =====================================================================
make_fake_repo() {
  # $1 = racine à créer ; définit ezacae-a 1.0.0 et ezacae-b 2.0.0
  local root="$1"
  mkdir -p "$root/plugins/ezacae-a/.claude-plugin" "$root/plugins/ezacae-b/.claude-plugin"
  printf '{ "name": "ezacae-a", "version": "1.0.0" }\n' > "$root/plugins/ezacae-a/.claude-plugin/plugin.json"
  printf '{ "name": "ezacae-b", "version": "2.0.0" }\n' > "$root/plugins/ezacae-b/.claude-plugin/plugin.json"
}

t4_1() {
  local tmp; tmp="$(mktemp -d)"

  # Cas a : versions.lock conforme → exit 0
  local root="$tmp/repo-ok"; make_fake_repo "$root"
  printf 'ezacae-a 1.0.0\nezacae-b 2.0.0\n' > "$root/versions.lock"
  local out code
  out=$("$BASH_BIN" "$SCRIPT" --check "$root" 2>&1); code=$?
  eq "4.1a conforme → exit 0" "0" "$code"

  # Cas b : écart de version → exit non nul, nomme le plugin fautif
  root="$tmp/repo-ecart"; make_fake_repo "$root"
  printf 'ezacae-a 1.0.0\nezacae-b 1.9.0\n' > "$root/versions.lock"
  out=$("$BASH_BIN" "$SCRIPT" --check "$root" 2>&1); code=$?
  contains "4.1b écart → nomme le plugin fautif" "ezacae-b" "$out"
  [ "$code" != "0" ] && echo "PASS: 4.1b écart → exit non nul" && pass=$((pass+1)) \
    || { echo "FAIL: 4.1b écart → exit non nul — obtenu 0"; fail=$((fail+1)); }

  # Cas c : plugin du dépôt absent de versions.lock → exit non nul
  root="$tmp/repo-manquant"; make_fake_repo "$root"
  printf 'ezacae-a 1.0.0\n' > "$root/versions.lock"
  out=$("$BASH_BIN" "$SCRIPT" --check "$root" 2>&1); code=$?
  contains "4.1c plugin absent du fichier → nomme-le" "ezacae-b" "$out"
  [ "$code" != "0" ] && echo "PASS: 4.1c plugin absent du fichier → exit non nul" && pass=$((pass+1)) \
    || { echo "FAIL: 4.1c plugin absent du fichier → exit non nul — obtenu 0"; fail=$((fail+1)); }

  # Cas d : ligne du fichier sans plugin correspondant → exit non nul
  root="$tmp/repo-orpheline"; make_fake_repo "$root"
  printf 'ezacae-a 1.0.0\nezacae-b 2.0.0\nezacae-fantome 9.9.9\n' > "$root/versions.lock"
  out=$("$BASH_BIN" "$SCRIPT" --check "$root" 2>&1); code=$?
  contains "4.1d ligne orpheline → la nomme" "ezacae-fantome" "$out"
  [ "$code" != "0" ] && echo "PASS: 4.1d ligne orpheline → exit non nul" && pass=$((pass+1)) \
    || { echo "FAIL: 4.1d ligne orpheline → exit non nul — obtenu 0"; fail=$((fail+1)); }

  rm -rf "$tmp"
}

t4_1

# =====================================================================
# Tâche 5.2 (découvert à l'exécution réelle) : --detail doit montrer les
# plugins même sur un poste en source directory — pas seulement rester
# silencieux comme en mode normal (tâche 1.4). C'est le cas du poste de
# maintenance : sans ce test, --detail y serait muet, contredisant sa
# propre raison d'être (« comprendre un avertissement surprenant sans
# refaire l'enquête, et mesurer un poste dont on doute »).
# =====================================================================
t5_2_detail_directory() {
  local tmp; tmp="$(mktemp -d)"
  local home="$tmp/plugins"
  local repo="$tmp/repo-checkout"
  mkdir -p "$home" "$repo"

  cat > "$home/known_marketplaces.json" <<JSON
{
  "$MARKETPLACE": {
    "source": { "source": "directory", "path": "$repo" },
    "installLocation": "$repo",
    "lastUpdated": "2020-01-01T00:00:00.000Z"
  }
}
JSON
  printf 'ezacae-base 0.2.0\nezacae-jira 0.2.0\nezacae-doc 0.3.2\nezacae-dev 0.4.0\n' > "$repo/versions.lock"

  local out_silent code_silent out_detail code_detail
  out_silent=$(run_check "$home"); code_silent=$?
  eq "5.2 directory sans --detail → silence (déjà couvert, verrouillé ici aussi)" "" "$out_silent"
  eq "5.2 directory sans --detail → exit 0" "0" "$code_silent"

  out_detail=$(EZACAE_PLUGINS_HOME="$home" bash "$SCRIPT" --detail 2>&1); code_detail=$?
  nonempty "5.2 directory --detail → sortie non vide" "$out_detail"
  contains "5.2 directory --detail → mentionne ezacae-base" "ezacae-base" "$out_detail"
  contains "5.2 directory --detail → mentionne ezacae-jira" "ezacae-jira" "$out_detail"
  contains "5.2 directory --detail → mentionne ezacae-doc" "ezacae-doc" "$out_detail"
  contains "5.2 directory --detail → mentionne ezacae-dev" "ezacae-dev" "$out_detail"
  eq       "5.2 directory --detail → exit 0" "0" "$code_detail"

  rm -rf "$tmp"
}

t5_2_detail_directory

# =====================================================================
# Addendum — correctifs issus de la revue de code de la MR 18 (RD-22)
# =====================================================================

# ---------------------------------------------------------------------
# Tâche A.2 : la garde jq doit appeler incapacite() au lieu de recopier
# son gabarit de message. Les deux gabarits sont déjà, aujourd'hui,
# identiques au caractère près (duplication texte-à-texte, pas encore
# divergente) — une comparaison de sortie ne peut donc pas capturer le
# défaut réel : c'est une duplication du SOURCE, pas un écart observable
# en boîte noire. Le test verrouille donc directement le fait que le
# gabarit n'est plus écrit qu'une seule fois dans le script (à
# l'intérieur de incapacite()) ; avant le correctif, il est écrit deux
# fois, à trois lignes d'intervalle.
# =====================================================================
t_a2() {
  local boilerplate="le contrôle de dérive de version des plugins ezacae est inopérant."
  local occurrences
  occurrences="$(grep -c -- "$boilerplate" "$SCRIPT")"
  eq "A.2 gabarit d'incapacité écrit une seule fois dans la source (jq appelle incapacite)" "1" "$occurrences"

  # Verrou fonctionnel complémentaire : une fois la garde jq réécrite pour
  # appeler incapacite(), le message qu'elle produit reste, par
  # construction, le même gabarit que les autres cas d'incapacité — on le
  # vérifie en le comparant, une fois la raison neutralisée, à un autre
  # cas d'incapacité réel (known_marketplaces.json absent, tâche 1.3a).
  local tmp; tmp="$(mktemp -d)"
  local home="$tmp/plugins"; mkdir -p "$home"
  local emptybin="$tmp/emptybin"; mkdir -p "$emptybin"

  local jq_absent_out other_incapacite_out
  jq_absent_out=$(EZACAE_PLUGINS_HOME="$tmp/plugins-inexistant" PATH="$emptybin" "$BASH_BIN" "$SCRIPT" 2>&1)
  other_incapacite_out=$(run_check "$home")

  local jq_absent_suffix other_suffix
  jq_absent_suffix="${jq_absent_out#*—}"
  other_suffix="${other_incapacite_out#*—}"
  eq "A.2 gabarit jq absent = gabarit des autres incapacités (suffixe identique)" "$other_suffix" "$jq_absent_suffix"

  rm -rf "$tmp"
}

t_a2

# ---------------------------------------------------------------------
# Tâche A.3 : le préfixe d'avertissement doit appartenir à la fonction
# qui construit le message, pas à chaque appelant. Comme pour A.2, les
# messages actuels sont déjà, aujourd'hui, correctement préfixés (la
# duplication n'a pas encore divergé) : le verrou structurel (occurrence
# unique du préfixe littéral dans la source) est donc l'assertion qui
# distingue vraiment l'avant du après. Le verrou fonctionnel (chaque
# première ligne d'avertissement commence par le préfixe, tous chemins
# de code confondus) complète en verrouillant le comportement observable.
# =====================================================================
t_a3() {
  local prefix="⚠️  ezacae-base : "

  local occurrences
  occurrences="$(grep -o -- "$prefix" "$SCRIPT" | wc -l | tr -d ' ')"
  eq "A.3 préfixe écrit une seule fois dans la source (fonction d'émission)" "1" "$occurrences"

  local tmp home out first_line got

  # add_warning : plugin absent
  tmp="$(mktemp -d)"; home="$tmp/plugins"
  setup_fresh_git_post "$home" "ezacae-doc" "0.3.2"
  out=$(run_check "$home")
  first_line="$(printf '%s' "$out" | head -1)"
  case "$first_line" in "$prefix"*) got="$prefix" ;; *) got="$first_line" ;; esac
  eq "A.3 préfixe — plugin absent" "$prefix" "$got"
  rm -rf "$tmp"

  # add_warning : version non sémantique
  tmp="$(mktemp -d)"; home="$tmp/plugins"
  setup_fresh_git_post "$home" "ezacae-doc" "0.3.2"
  mkdir -p "$home/cache/$MARKETPLACE/ezacae-doc/unknown/commands"
  out=$(run_check "$home")
  first_line="$(printf '%s' "$out" | head -1)"
  case "$first_line" in "$prefix"*) got="$prefix" ;; *) got="$first_line" ;; esac
  eq "A.3 préfixe — version non sémantique" "$prefix" "$got"
  rm -rf "$tmp"

  # add_warning : dérive de version
  tmp="$(mktemp -d)"; home="$tmp/plugins"
  setup_fresh_git_post "$home" "ezacae-doc" "0.3.2"
  mkdir -p "$home/cache/$MARKETPLACE/ezacae-doc/0.1.0/commands"
  out=$(run_check "$home")
  first_line="$(printf '%s' "$out" | head -1)"
  case "$first_line" in "$prefix"*) got="$prefix" ;; *) got="$first_line" ;; esac
  eq "A.3 préfixe — dérive de version" "$prefix" "$got"
  rm -rf "$tmp"

  # incapacite : jq absent
  tmp="$(mktemp -d)"
  local emptybin="$tmp/emptybin"; mkdir -p "$emptybin"
  out=$(EZACAE_PLUGINS_HOME="$tmp/plugins" PATH="$emptybin" "$BASH_BIN" "$SCRIPT" 2>&1)
  first_line="$(printf '%s' "$out" | head -1)"
  case "$first_line" in "$prefix"*) got="$prefix" ;; *) got="$first_line" ;; esac
  eq "A.3 préfixe — jq absent (incapacite)" "$prefix" "$got"
  rm -rf "$tmp"
}

t_a3

echo "-----"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] || exit 1
