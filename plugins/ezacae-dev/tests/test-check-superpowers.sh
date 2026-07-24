#!/usr/bin/env bash
# Tests du garde SessionStart check-superpowers.sh (RD-8).
# Le garde vérifie la présence du plugin superpowers et la dérive de version
# vs superpowers.lock. Non bloquant : sort toujours 0, émet un avertissement.
#
# Détection par le CACHE DISQUE (pas via `claude plugin list` : un hook
# SessionStart ne doit pas invoquer le CLI qu'il démarre — course + latence).
# Chemin stable vérifié 23/07 : ~/.claude/plugins/cache/<marketplace>/superpowers/<version>/
#
# Testabilité :
#   SUPERPOWERS_CACHE_DIR  racine du cache plugins (défaut : ~/.claude/plugins/cache)
#   SUPERPOWERS_LOCK       chemin du lock (défaut : <hook>/../superpowers.lock)

set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$DIR/../hooks/check-superpowers.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
contains() { if printf '%s' "$3" | grep -qF -- "$2"; then echo "PASS: $1"; pass=$((pass+1))
  else echo "FAIL: $1 — attendu contient «$2» — obtenu: «$3»"; fail=$((fail+1)); fi; }
refutes()  { if printf '%s' "$3" | grep -qF -- "$2"; then echo "FAIL: $1 — ne devait PAS contenir «$2» — obtenu: «$3»"; fail=$((fail+1))
  else echo "PASS: $1"; pass=$((pass+1)); fi; }
eq()       { if [ "$2" = "$3" ]; then echo "PASS: $1"; pass=$((pass+1))
  else echo "FAIL: $1 — attendu «$2» — obtenu «$3»"; fail=$((fail+1)); fi; }

echo "6.1.1" > "$TMP/superpowers.lock"
LOCK="$TMP/superpowers.lock"

# --- Cas 1 : superpowers ABSENT du cache → avertit + commande d'install, exit 0 ---
CACHE_ABSENT="$TMP/cache-absent"; mkdir -p "$CACHE_ABSENT/other-mk/other/1.0.0"
out=$(SUPERPOWERS_CACHE_DIR="$CACHE_ABSENT" SUPERPOWERS_LOCK="$LOCK" bash "$SCRIPT" 2>&1); code=$?
contains "absent → commande d'install exacte" "claude plugin install superpowers@claude-plugins-official" "$out"
eq       "absent → non bloquant (exit 0)" "0" "$code"

# --- Cas 2 : superpowers PRÉSENT, version = lock → aucun avertissement, exit 0 ---
CACHE_OK="$TMP/cache-ok"; mkdir -p "$CACHE_OK/claude-plugins-official/superpowers/6.1.1/skills"
out=$(SUPERPOWERS_CACHE_DIR="$CACHE_OK" SUPERPOWERS_LOCK="$LOCK" bash "$SCRIPT" 2>&1); code=$?
refutes  "présent+match → pas de message d'install" "claude plugin install superpowers" "$out"
refutes  "présent+match → pas d'alerte de dérive" "dérive" "$out"
eq       "présent+match → exit 0" "0" "$code"

# --- Cas 3 : superpowers PRÉSENT, version ≠ lock → alerte dérive (2 versions), exit 0 ---
CACHE_DRIFT="$TMP/cache-drift"; mkdir -p "$CACHE_DRIFT/claude-plugins-official/superpowers/6.2.0/skills"
out=$(SUPERPOWERS_CACHE_DIR="$CACHE_DRIFT" SUPERPOWERS_LOCK="$LOCK" bash "$SCRIPT" 2>&1); code=$?
contains "dérive → mentionne la version attendue (lock)" "6.1.1" "$out"
contains "dérive → mentionne la version installée" "6.2.0" "$out"
eq       "dérive → non bloquant (exit 0)" "0" "$code"

echo "-----"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] || exit 1
