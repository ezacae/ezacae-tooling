#!/usr/bin/env bash
# Tests du garde SessionStart check-pocock.sh (RD-42, ezacae-dev).
#
# Les compétences de Matt Pocock autorisées (grill-me, grilling, handoff,
# to-tickets) sont installées EN RÉFÉRENCE sur chaque poste par l'outil
# `skills` (npx skills add mattpocock/skills -g -a claude-code -s …), jamais
# copiées dans le dépôt. L'outil écrit un verrou global ~/.agents/.skill-lock.json
# (skillFolderHash par compétence) et copie chaque compétence dans
# ~/.claude/skills/<nom>/. Le garde compare ce verrou à pocock.lock du plugin.
#
# Non bloquant : avertit, sort TOUJOURS 0 (même forme que check-superpowers.sh).
#
# Testabilité :
#   POCOCK_SKILLS_DIR  dossier des compétences du poste (défaut : ~/.claude/skills)
#   POCOCK_CLI_LOCK    verrou écrit par l'outil skills (défaut : ~/.agents/.skill-lock.json)
#   POCOCK_LOCK        verrou du plugin (défaut : <hook>/../pocock.lock)

set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$DIR/../hooks/check-pocock.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
contains() { if printf '%s' "$3" | grep -qF -- "$2"; then echo "PASS: $1"; pass=$((pass+1))
  else echo "FAIL: $1 — attendu contient «$2» — obtenu: «$3»"; fail=$((fail+1)); fi; }
refutes()  { if printf '%s' "$3" | grep -qF -- "$2"; then echo "FAIL: $1 — ne devait PAS contenir «$2» — obtenu: «$3»"; fail=$((fail+1))
  else echo "PASS: $1"; pass=$((pass+1)); fi; }
eq()       { if [ "$2" = "$3" ]; then echo "PASS: $1"; pass=$((pass+1))
  else echo "FAIL: $1 — attendu «$2» — obtenu «$3»"; fail=$((fail+1)); fi; }

# Verrou du plugin : deux compétences suffisent pour les cas.
cat > "$TMP/pocock.lock" <<EOF
# source mattpocock/skills
grill-me aaaa1111
handoff  bbbb2222
EOF
LOCK="$TMP/pocock.lock"

cli_lock() { # $1 = fichier, puis paires nom hash
  local f="$1"; shift
  local json='{"version":3,"skills":{}}'
  while [ "$#" -gt 0 ]; do
    json=$(printf '%s' "$json" | jq --arg n "$1" --arg h "$2" '.skills[$n]={source:"mattpocock/skills",skillFolderHash:$h}')
    shift 2
  done
  printf '%s' "$json" > "$f"
}
mk_skill() { mkdir -p "$1/$2"; printf -- '---\nname: %s\n---\n' "$2" > "$1/$2/SKILL.md"; }

# --- Cas 1 : rien d'installé → avertit + commande d'installation exacte, exit 0 ---
S1="$TMP/s1"; mkdir -p "$S1"
out=$(POCOCK_SKILLS_DIR="$S1" POCOCK_CLI_LOCK="$TMP/absent.json" POCOCK_LOCK="$LOCK" bash "$SCRIPT" 2>&1); code=$?
eq "absent → exit 0 (non bloquant)" "0" "$code"
contains "absent → nomme grill-me" "grill-me" "$out"
contains "absent → nomme handoff" "handoff" "$out"
contains "absent → commande d'installation" "npx skills add mattpocock/skills -g -a claude-code" "$out"

# --- Cas 2 : tout installé, empreintes = verrou → silence, exit 0 ---
S2="$TMP/s2"; mk_skill "$S2" grill-me; mk_skill "$S2" handoff
cli_lock "$TMP/cli2.json" grill-me aaaa1111 handoff bbbb2222
out=$(POCOCK_SKILLS_DIR="$S2" POCOCK_CLI_LOCK="$TMP/cli2.json" POCOCK_LOCK="$LOCK" bash "$SCRIPT" 2>&1); code=$?
eq "conforme → exit 0" "0" "$code"
eq "conforme → aucune sortie" "" "$out"

# --- Cas 3 : installé mais empreinte différente → alerte dérive avec les deux empreintes ---
cli_lock "$TMP/cli3.json" grill-me aaaa1111 handoff cccc3333
out=$(POCOCK_SKILLS_DIR="$S2" POCOCK_CLI_LOCK="$TMP/cli3.json" POCOCK_LOCK="$LOCK" bash "$SCRIPT" 2>&1); code=$?
eq "dérive → exit 0" "0" "$code"
contains "dérive → nomme la compétence" "handoff" "$out"
contains "dérive → empreinte attendue" "bbbb2222" "$out"
contains "dérive → empreinte installée" "cccc3333" "$out"
refutes  "dérive → grill-me (conforme) n'est pas cité en dérive" "grill-me" "$out"

# --- Cas 4 : SKILL.md présent mais absent du verrou de l'outil → installé hors outil, non vérifiable ---
S4="$TMP/s4"; mk_skill "$S4" grill-me; mk_skill "$S4" handoff
cli_lock "$TMP/cli4.json" grill-me aaaa1111
out=$(POCOCK_SKILLS_DIR="$S4" POCOCK_CLI_LOCK="$TMP/cli4.json" POCOCK_LOCK="$LOCK" bash "$SCRIPT" 2>&1); code=$?
eq "hors outil → exit 0" "0" "$code"
contains "hors outil → nomme handoff" "handoff" "$out"
contains "hors outil → dit que la version n'est pas vérifiable" "non vérifiable" "$out"

# --- Cas 5 : une compétence manque, l'autre est conforme → seule la manquante est citée ---
S5="$TMP/s5"; mk_skill "$S5" grill-me
cli_lock "$TMP/cli5.json" grill-me aaaa1111
out=$(POCOCK_SKILLS_DIR="$S5" POCOCK_CLI_LOCK="$TMP/cli5.json" POCOCK_LOCK="$LOCK" bash "$SCRIPT" 2>&1); code=$?
contains "manquante → nomme handoff" "handoff" "$out"
refutes  "manquante → ne cite pas grill-me" "grill-me" "$out"
contains "manquante → commande d'installation ciblée sur handoff" "-s handoff" "$out"

echo "-----"; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
